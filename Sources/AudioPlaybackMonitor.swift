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

import CoreAudio
import Foundation

/// Only scalar levels and timestamps survive a callback; audio buffers are never retained.
struct AudioSignalLevel {
    static func hasSound(_ samples: UnsafeBufferPointer<Float>) -> Bool {
        guard !samples.isEmpty else { return false }
        var energy: Double = 0
        var peak: Float = 0
        for value in samples where value.isFinite {
            energy += Double(value) * Double(value)
            peak = max(peak, abs(value))
        }
        // Ignore numerical noise below -80 dBFS, while preserving quiet playback.
        return energy / Double(samples.count) >= 0.00000001 || peak >= 0.0003
    }
}

final class AudioPlaybackMonitor {
    enum State: Equatable { case playing, silent, unavailable }
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var deviceID = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private let queue = DispatchQueue(label: "local.restreminder.audio-level")
    private let lock = NSLock()
    // This clock includes system sleep, so pre-sleep sound cannot look fresh after waking.
    private let clock = RestContinuousClock()
    private var lastSoundAt: RestContinuousClock.Instant?
    private var lastBufferAt: RestContinuousClock.Instant?
    private var startedAt: RestContinuousClock.Instant?
    private(set) var errorDescription: String?

    func start() {
        stop()
        guard #available(macOS 14.2, *) else {
            errorDescription = "需要 macOS 14.2 或更新版本"
            return
        }
        let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [])
        description.name = "歇一会儿 · 仅计算音量"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        var status = AudioHardwareCreateProcessTap(description, &tapID)
        guard status == noErr else { fail("系统音频权限或音频连接不可用", status); return }

        var format = AudioStreamBasicDescription()
        var address = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        status = AudioObjectGetPropertyData(tapID, &address, 0, nil, &size, &format)
        guard status == noErr, format.mFormatID == kAudioFormatLinearPCM,
              format.mFormatFlags & kAudioFormatFlagIsFloat != 0, format.mBitsPerChannel == 32 else {
            fail("无法读取系统音频格式", status); return
        }
        let device: [String: Any] = [
            kAudioAggregateDeviceNameKey: "歇一会儿音量检测",
            kAudioAggregateDeviceUIDKey: "local.restreminder.level.\(UUID().uuidString)",
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: true,
            kAudioAggregateDeviceTapListKey: [[
                kAudioSubTapUIDKey: description.uuid.uuidString,
                kAudioSubTapDriftCompensationKey: true
            ]]
        ]
        status = AudioHardwareCreateAggregateDevice(device as CFDictionary, &deviceID)
        guard status == noErr else { fail("无法建立音量检测连接", status); return }
        status = AudioDeviceCreateIOProcIDWithBlock(&ioProc, deviceID, queue) { [weak self] _, input, _, _, _ in
            var hasData = false
            var hasSound = false
            for buffer in UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)) {
                guard let data = buffer.mData, buffer.mDataByteSize > 0 else { continue }
                let samples = UnsafeBufferPointer(start: data.assumingMemoryBound(to: Float.self),
                                                  count: Int(buffer.mDataByteSize) / MemoryLayout<Float>.size)
                hasData = true
                if AudioSignalLevel.hasSound(samples) { hasSound = true }
            }
            guard let self, hasData else { return }
            let now = self.clock.now
            self.lock.lock()
            self.lastBufferAt = now
            if hasSound { self.lastSoundAt = now }
            self.lock.unlock()
        }
        guard status == noErr, let ioProc else { fail("无法启动音量检测", status); return }
        startedAt = clock.now
        status = AudioDeviceStart(deviceID, ioProc)
        guard status == noErr else { fail("请检查系统音频录制权限", status); return }
        errorDescription = nil
    }

    func state() -> State {
        guard let startedAt else { return .unavailable }
        let now = clock.now
        lock.lock()
        let sound = lastSoundAt
        let buffer = lastBufferAt
        lock.unlock()
        if let sound, sound.duration(to: now) < 1.5 { return .playing }
        // No delivered data is an unknown state, never evidence of audible playback.
        if (buffer ?? startedAt).duration(to: now) > 3 { return .unavailable }
        return .silent
    }

    func stop() {
        if let ioProc {
            AudioDeviceStop(deviceID, ioProc)
            AudioDeviceDestroyIOProcID(deviceID, ioProc)
        }
        ioProc = nil
        if deviceID != kAudioObjectUnknown { AudioHardwareDestroyAggregateDevice(deviceID) }
        deviceID = AudioObjectID(kAudioObjectUnknown)
        if #available(macOS 14.2, *), tapID != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tapID) }
        tapID = AudioObjectID(kAudioObjectUnknown)
        startedAt = nil
        lock.lock()
        lastSoundAt = nil
        lastBufferAt = nil
        lock.unlock()
    }

    private func fail(_ message: String, _ status: OSStatus) {
        stop()
        errorDescription = "\(message)（\(status)）"
    }

    deinit { stop() }
}

/// Only a real audio signal extends quiet time. Missing permission must not pause reminders forever.
struct AudioQuietPeriod {
    private var quietAfter: Double?
    private(set) var suppressesReminders = false

    mutating func update(state: AudioPlaybackMonitor.State, now: Double) -> Bool {
        if state == .playing { quietAfter = now + 10 }
        suppressesReminders = quietAfter.map { now < $0 } ?? false
        return suppressesReminders
    }
}
