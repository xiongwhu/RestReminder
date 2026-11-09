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

/// Advisory per-user lock. Keep the acquired object alive before constructing AppDelegate,
/// and until app.run() returns. Closing (including process death) releases the flock.
/// The lock file is intentionally never removed: unlinking it would permit two locked inodes.
final class SingleInstanceGuard {
    struct Failure: Error, LocalizedError {
        let operation: String
        let path: String
        let underlyingDescription: String
        var errorDescription: String? { "\(operation): \(path): \(underlyingDescription)" }
    }

    enum Acquisition {
        case acquired(SingleInstanceGuard)
        case alreadyRunning
        case failed(Failure)
    }

    /// Distributed notifications carry only these benign UI requests. Never accept paths,
    /// commands, preference mutations, or requests to start audio capture over this channel.
    enum Intent: String { case activate, openHistory, openSettings }
    static let notificationName = Notification.Name("local.restreminder.mac.instanceIntent")
    static let notificationObject = "local.restreminder.mac"

    private let descriptor: Int32
    private init(descriptor: Int32) { self.descriptor = descriptor }
    deinit { Darwin.close(descriptor) }

    static func acquire() -> Acquisition {
        do {
            let support = try FileManager.default.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: false)
            return acquire(at: support.appendingPathComponent("RestReminder", isDirectory: true)
                .appendingPathComponent("instance.lock"))
        } catch {
            return .failed(Failure(operation: "Locate Application Support", path: "RestReminder",
                                   underlyingDescription: error.localizedDescription))
        }
    }

    /// Explicit path injection is for isolated tests and tools. Production calls acquire().
    static func acquire(at lockURL: URL) -> Acquisition {
        guard lockURL.isFileURL, !lockURL.lastPathComponent.isEmpty else {
            return .failed(Failure(operation: "Validate lock URL", path: lockURL.absoluteString,
                                   underlyingDescription: "Expected a local lock file URL"))
        }
        do {
            try FileManager.default.createDirectory(at: lockURL.deletingLastPathComponent(),
                withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        } catch {
            return .failed(Failure(operation: "Create lock directory", path: lockURL.path,
                                   underlyingDescription: error.localizedDescription))
        }
        // No symlink following, truncation, PID probing, or inherited lock in an exec child.
        let fd = Darwin.open(lockURL.path, O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, mode_t(0o600))
        guard fd >= 0 else { return failure("Open instance lock", lockURL, errno) }
        var keepDescriptor = false
        defer { if !keepDescriptor { Darwin.close(fd) } }

        var metadata = stat()
        guard Darwin.fstat(fd, &metadata) == 0 else { return failure("Inspect instance lock", lockURL, errno) }
        guard metadata.st_mode & mode_t(S_IFMT) == mode_t(S_IFREG), metadata.st_uid == getuid(),
              metadata.st_nlink == 1 else {
            return .failed(Failure(operation: "Validate instance lock", path: lockURL.path,
                                   underlyingDescription: "Expected a regular file owned by the current user with one link"))
        }
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            let code = errno
            if code == EINTR { continue }
            if code == EWOULDBLOCK || code == EAGAIN { return .alreadyRunning }
            return failure("Acquire instance lock", lockURL, code)
        }
        guard Darwin.fchmod(fd, mode_t(0o600)) == 0 else { return failure("Secure instance lock", lockURL, errno) }
        keepDescriptor = true
        return .acquired(SingleInstanceGuard(descriptor: fd))
    }

    static func forward(_ intent: Intent) {
        DistributedNotificationCenter.default().postNotificationName(notificationName,
            object: notificationObject, userInfo: ["intent": intent.rawValue], deliverImmediately: true)
    }

    static func intent(from notification: Notification) -> Intent? {
        guard notification.name == notificationName,
              notification.object as? String == notificationObject,
              let raw = notification.userInfo?["intent"] as? String else { return nil }
        return Intent(rawValue: raw)
    }

    private static func failure(_ operation: String, _ url: URL, _ code: Int32) -> Acquisition {
        .failed(Failure(operation: operation, path: url.path,
                        underlyingDescription: String(cString: strerror(code))))
    }
}
