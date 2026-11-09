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

import Foundation

/// Lock, sleep, and user-session events overlap; only the final return exposes the desktop.
struct SystemRestState {
    enum Reason: Hashable { case screenLock, sleep, inactiveSession }
    enum Transition { case left, returned }
    private var reasons: Set<Reason> = []
    var isInactive: Bool { !reasons.isEmpty }

    mutating func update(_ reason: Reason, inactive: Bool) -> Transition? {
        let wasInactive = isInactive
        if inactive { reasons.insert(reason) } else { reasons.remove(reason) }
        if !wasInactive && isInactive { return .left }
        if wasInactive && !isInactive { return .returned }
        return nil
    }
}

/// Monotonic timestamps keep clock changes from affecting a session.
struct ActivitySession {
    var startedAt: TimeInterval?
    var deferredUntil: TimeInterval?
    var paused = false
    enum Feedback { case welcomeBack, needsMoreRest }
    private(set) var feedback: Feedback?
    private var previousSample: TimeInterval?
    private var previousIdle: TimeInterval?
    private var previousInputAt: TimeInterval?
    private var completedRest = false
    private var awaitingRest = false
    private var nextEncouragementAt: TimeInterval = 0
    private var systemRestStartedAt: Date?
    private var systemReturnPending = false

    mutating func suspend(at date: Date) {
        guard systemRestStartedAt == nil else { return }
        let alreadyRested = completedRest || systemReturnPending
        reset()
        completedRest = alreadyRested
        systemRestStartedAt = date
    }

    mutating func resume(at date: Date, now: TimeInterval, restThreshold: TimeInterval) {
        guard let start = systemRestStartedAt else { return }
        // Wall time includes closed-lid sleep, unlike uptime on some macOS versions.
        let qualified = completedRest || date.timeIntervalSince(start) >= restThreshold
        reset()
        systemReturnPending = qualified && !paused
        previousSample = now
    }

    mutating func beginRest(now: TimeInterval, seconds: TimeInterval) {
        awaitingRest = true
        previousSample = now
        previousInputAt = now
        previousIdle = 0
        deferredUntil = now + seconds
    }

    mutating func reset() {
        startedAt = nil
        deferredUntil = nil
        previousSample = nil
        previousIdle = nil
        previousInputAt = nil
        completedRest = false
        awaitingRest = false
        nextEncouragementAt = 0
        feedback = nil
        systemRestStartedAt = nil
        systemReturnPending = false
    }

    mutating func acknowledgeCompletedRest(now: TimeInterval, idle: TimeInterval) {
        startedAt = nil
        deferredUntil = nil
        completedRest = true
        awaitingRest = false
        previousSample = now
        previousInputAt = now - max(0, idle)
        previousIdle = max(0, idle)
        nextEncouragementAt = 0
        feedback = nil
        // Keep a matching lock/sleep start intact so Touch ID can still produce a return event.
    }

    mutating func deferReminder(now: TimeInterval, seconds: TimeInterval) {
        previousSample = now
        previousInputAt = now
        previousIdle = 0
        deferredUntil = now + seconds
    }

    mutating func sample(now: TimeInterval, idle: TimeInterval,
                         interval: TimeInterval, restThreshold: TimeInterval,
                         suppressReminders: Bool = false) -> Bool {
        // Consume return events during audio without queuing a celebration for later.
        defer { if suppressReminders { feedback = nil } }
        feedback = nil
        guard !paused else { reset(); return false }
        guard systemRestStartedAt == nil else { return false }
        guard idle.isFinite, idle >= 0 else { reset(); return false }
        // A long scheduling gap resets work timing, but cannot consume a pending system return.
        if let previousSample, now - previousSample > 10 {
            let pending = systemReturnPending
            let rested = completedRest
            reset()
            systemReturnPending = pending
            completedRest = rested
        }
        if systemReturnPending {
            systemReturnPending = false
            feedback = .welcomeBack
            // Unlocking itself is the return event (including Touch ID, which may not reset idle).
            startedAt = idle <= 2 ? now : nil
            previousSample = now
            previousInputAt = now - idle
            previousIdle = idle
            return false
        }
        previousSample = now
        let inputAt = now - idle
        let resumed = previousInputAt.map { inputAt > $0 + 0.05 } ?? false
        let breakDuration = previousInputAt.map { inputAt - $0 } ?? 0
        let hadShortBreak = (previousIdle ?? 0) >= min(5, restThreshold / 2)
        previousInputAt = inputAt
        defer { previousIdle = idle }

        if idle >= restThreshold {
            if startedAt != nil { completedRest = true }
            startedAt = nil
            deferredUntil = nil
            return false
        }
        if resumed && idle <= 2 {
            if completedRest || (startedAt != nil && breakDuration >= restThreshold) {
                feedback = .welcomeBack
                completedRest = false
                awaitingRest = false
                deferredUntil = nil
                startedAt = now
                return false
            }
            let isDue = startedAt.map { now - $0 >= interval } ?? false
            if hadShortBreak && (awaitingRest || isDue) && now >= nextEncouragementAt {
                feedback = .needsMoreRest
                nextEncouragementAt = now + 30
                // Give the suggestion time to be read before the next modal reminder.
                deferredUntil = max(deferredUntil ?? now, now + 30)
            }
        }
        if startedAt == nil {
            // Wait for fresh activity rather than counting pre-launch idle time.
            if idle <= 2 { startedAt = now }
            return false
        }
        guard idle <= 2, !suppressReminders else { return false }
        if let deferredUntil { return now >= deferredUntil }
        return now - startedAt! >= interval
    }

    func remaining(now: TimeInterval, interval: TimeInterval) -> TimeInterval {
        if let deferredUntil { return max(0, deferredUntil - now) }
        guard let startedAt else { return interval }
        return max(0, interval - (now - startedAt))
    }
}
