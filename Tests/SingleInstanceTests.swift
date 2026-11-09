// SPDX-License-Identifier: CPAL-1.0
//
// EXHIBIT A. Common Public Attribution License Version 1.0.
//
// The contents of this file are subject to the Common Public Attribution License Version 1.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at https://opensource.org/license/cpal-1-0. The License is based on the Mozilla Public License Version 1.1 but Sections 14 and 15 have been added to cover use of software over a computer network and provide for limited attribution for the Original Developer. In addition, Exhibit A has been modified to be consistent with Exhibit B.
//
// Software distributed under the License is distributed on an "AS IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for the specific language governing rights and limitations under the License.
//
// The Original Code is RestReminder (歇一会儿), including the original source code, tests and build scripts distributed in this repository. Third-party photographs identified in Resources/PHOTO-CREDITS.md are excluded and remain subject to their original licenses.
// The Initial Developer of the Original Code is 广州迈润网络科技有限公司 (迈润智人 RaCIO).
// The Original Developer is the Initial Developer.
// All portions of the code written by the Initial Developer are Copyright (c) 2026 广州迈润网络科技有限公司. All Rights Reserved.
// Contributor(s): see individual source notices and project history.
// No alternative license is designated for the Original Code.
//
// [NOTE: The text of this Exhibit A may differ slightly from the text of the notices in the Source Code files of the Original Code. You should use the text of this Exhibit A rather than the text found in the Original Code Source Code for Your Modifications.]
//
// For Exhibit B Attribution Information, see the root LICENSE file.

import Darwin
import Foundation

@main
struct SingleInstanceTests {
    struct TestFailure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }

    static func expect(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !condition() { throw TestFailure(message) }
    }

    // Both parent and exec child verify the same private temporary root before touching a file.
    // No test invokes acquire() (the production Application Support path).
    static func verifiedRoot(_ path: String) throws -> URL {
        let root = URL(fileURLWithPath: path, isDirectory: true).standardizedFileURL
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let prefix = "restreminder-instance-tests-"
        try expect(root.deletingLastPathComponent() == temporary, "Root must be directly inside the OS temp directory")
        try expect(root.lastPathComponent.hasPrefix(prefix), "Unexpected test root")
        try expect(UUID(uuidString: String(root.lastPathComponent.dropFirst(prefix.count))) != nil, "Root needs a unique UUID")
        try expect(root.resolvingSymlinksInPath() == root, "Test root must not be a symlink")
        let marker = try String(contentsOf: root.appendingPathComponent(".test-root"), encoding: .utf8)
        try expect(marker == root.lastPathComponent, "Missing unique test-root marker")
        return root
    }

    static func lockURL(_ root: URL, _ name: String) throws -> URL {
        let verified = try verifiedRoot(root.path)
        try expect(["contention.lock", "crash.lock", "unrelated.lock", "permissions.lock",
                    "directory.lock", "symlink.lock"].contains(name), "Unexpected lock fixture name")
        return verified.appendingPathComponent(name)
    }

    static func readByte(_ handle: FileHandle) throws -> UInt8 {
        var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN), revents: 0)
        var status: Int32
        repeat { status = Darwin.poll(&descriptor, 1, 10_000) } while status < 0 && errno == EINTR
        try expect(status > 0, "Timed out waiting for isolated child protocol")
        let data = handle.readData(ofLength: 1)
        guard let byte = data.first else { throw TestFailure("Unexpected child EOF") }
        return byte
    }

    final class Child {
        let process = Process()
        let input = Pipe()
        let output = Pipe()
        let ended = DispatchSemaphore(value: 0)

        init(root: URL, name: String) throws {
            _ = try lockURL(root, name)
            process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
            process.arguments = ["--instance-worker", root.path, name]
            process.standardInput = input
            process.standardOutput = output
            process.standardError = FileHandle.standardError
            let completion = ended
            process.terminationHandler = { _ in completion.signal() }
            try process.run()
            // Close the parent's duplicate child pipe ends; EOF must be observable.
            input.fileHandleForReading.closeFile()
            output.fileHandleForWriting.closeFile()
        }

        func response() throws -> UInt8 { try SingleInstanceTests.readByte(output.fileHandleForReading) }
        func send(_ byte: UInt8) { input.fileHandleForWriting.write(Data([byte])) }
        func wait() throws {
            try SingleInstanceTests.expect(ended.wait(timeout: .now() + 10) == .success,
                                           "Isolated child did not exit")
            process.waitUntilExit()
        }

        deinit {
            input.fileHandleForWriting.closeFile()
            output.fileHandleForReading.closeFile()
            if process.isRunning {
                // This Process was spawned above; never look up or signal any app PID.
                process.terminate()
                if ended.wait(timeout: .now() + 2) != .success,
                   process.processIdentifier > 0, process.processIdentifier != getpid() {
                    Darwin.kill(process.processIdentifier, SIGKILL)
                    process.waitUntilExit()
                }
            }
        }
    }

    static func worker(rootPath: String, name: String) throws {
        let url = try lockURL(verifiedRoot(rootPath), name)
        switch SingleInstanceGuard.acquire(at: url) {
        case .acquired(let instance):
            try withExtendedLifetime(instance) {
                FileHandle.standardOutput.write(Data([65])) // A: acquired and ready
                switch try readByte(.standardInput) {
                case 82: return // R: release by returning, closing the descriptor
                case 67:
                    // C: abrupt death of this test child only; deinit cannot release its lock.
                    Darwin.raise(SIGKILL)
                    Darwin._exit(99)
                default: throw TestFailure("Unknown worker command")
                }
            }
        case .alreadyRunning:
            FileHandle.standardOutput.write(Data([66])) // B: blocked by another process
        case .failed(let failure): throw failure
        }
    }

    static func acquired(_ url: URL) throws -> SingleInstanceGuard {
        switch SingleInstanceGuard.acquire(at: url) {
        case .acquired(let instance): return instance
        case .alreadyRunning: throw TestFailure("Unexpected already-running result: \(url.lastPathComponent)")
        case .failed(let failure): throw failure
        }
    }

    static func isBlocked(_ url: URL) -> Bool {
        if case .alreadyRunning = SingleInstanceGuard.acquire(at: url) { return true }
        return false
    }

    static func isIOFailure(_ url: URL) -> Bool {
        if case .failed = SingleInstanceGuard.acquire(at: url) { return true }
        return false
    }

    static func suite(root: URL) throws {
        let contested = try lockURL(root, "contention.lock")
        var owner: SingleInstanceGuard? = try acquired(contested)
        let initial = try FileManager.default.attributesOfItem(atPath: contested.path)
        try expect((initial[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Instance lock must be 0600")
        try withExtendedLifetime(owner) {
            let contender = try Child(root: root, name: "contention.lock")
            try expect(try contender.response() == 66, "An independent exec process must observe contention")
            try contender.wait()
            try expect(contender.process.terminationStatus == 0, "Contender exited cleanly")

            let unrelated = try Child(root: root, name: "unrelated.lock")
            try expect(try unrelated.response() == 65, "Different temporary locks must remain independent")
            unrelated.send(82)
            try unrelated.wait()
            try expect(unrelated.process.terminationStatus == 0, "Unrelated owner released cleanly")
        }
        owner = nil
        let successor = try Child(root: root, name: "contention.lock")
        try expect(try successor.response() == 65, "Normal release permits the next process")
        successor.send(82)
        try successor.wait()
        let final = try FileManager.default.attributesOfItem(atPath: contested.path)
        try expect(initial[.systemFileNumber] as? NSNumber == final[.systemFileNumber] as? NSNumber,
                   "Release must preserve the original lock inode")

        let crashURL = try lockURL(root, "crash.lock")
        let crash = try Child(root: root, name: "crash.lock")
        try expect(try crash.response() == 65, "Crash fixture acquired its private lock")
        try expect(isBlocked(crashURL), "Live child lock prevents parent acquisition")
        crash.send(67)
        try crash.wait()
        try expect(crash.process.terminationReason == .uncaughtSignal && crash.process.terminationStatus == SIGKILL,
                   "Only the isolated worker crashed")
        try withExtendedLifetime(acquired(crashURL)) {
            try expect(isBlocked(crashURL), "Reacquired lock remains exclusive after crash recovery")
        }

        let permissions = try lockURL(root, "permissions.lock")
        try Data().write(to: permissions)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: permissions.path)
        try withExtendedLifetime(acquired(permissions)) {
            let attributes = try FileManager.default.attributesOfItem(atPath: permissions.path)
            try expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600, "Repair an older permissive lock to 0600")
        }
        let blockedParent = root.appendingPathComponent("not-a-directory")
        try Data().write(to: blockedParent)
        try expect(isIOFailure(blockedParent.appendingPathComponent("instance.lock")), "Directory IO failure is not already-running")
        let directory = try lockURL(root, "directory.lock")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try expect(isIOFailure(directory), "A directory cannot be a lock file")
        let symlink = try lockURL(root, "symlink.lock")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: contested)
        try expect(isIOFailure(symlink), "Do not follow lock-file symlinks")
        try expect(isIOFailure(URL(string: "https://example.invalid/instance.lock")!), "Reject nonlocal lock URLs")

        let validIntent = Notification(name: SingleInstanceGuard.notificationName,
            object: SingleInstanceGuard.notificationObject, userInfo: ["intent": "openHistory"])
        try expect(SingleInstanceGuard.intent(from: validIntent) == .openHistory, "Decode benign UI intent")
        let invalidIntent = Notification(name: SingleInstanceGuard.notificationName,
            object: SingleInstanceGuard.notificationObject, userInfo: ["intent": "deleteHistory"])
        try expect(SingleInstanceGuard.intent(from: invalidIntent) == nil, "Reject non-allowlisted intents")
        try expect(SingleInstanceGuard.intent(from: Notification(name: .init("unrelated"))) == nil,
                   "Reject unrelated notifications")
        print("PASS: interprocess exclusion, independent locks, lifetime release, crash recovery, stable inode, 0600, IO errors, symlinks, benign intents")
    }

    static func main() throws {
        if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--instance-worker" {
            try worker(rootPath: CommandLine.arguments[2], name: CommandLine.arguments[3])
            return
        }
        try expect(CommandLine.arguments.count == 1, "Unexpected test arguments")
        let temporary = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
        let root = temporary.appendingPathComponent("restreminder-instance-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false,
                                               attributes: [.posixPermissions: 0o700])
        try root.lastPathComponent.write(to: root.appendingPathComponent(".test-root"), atomically: false, encoding: .utf8)
        defer {
            // suite has returned, so all lifetime guards and child processes have ended.
            if let verified = try? verifiedRoot(root.path), verified == root {
                try? FileManager.default.removeItem(at: verified)
            }
        }
        try suite(root: verifiedRoot(root.path))
    }
}
