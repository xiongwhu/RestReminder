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

/// Counts only visible automatic reminders. Preview, audio suppression, and timer resets do not count.
struct RestEscalation {
    enum Action { case gentleReminder, strongRest }
    private(set) var reminderCount = 0
    private(set) var isStrongRestActive = false
    private(set) var workSecondsAtStart: TimeInterval = 0
    private(set) var emergencyDueAt: Date?
    private var strongRestStartedAt: Date?
    private var systemRestStartedAt: Date?

    init(reminderCount: Int = 0, emergencyDueAt: Date? = nil) {
        self.reminderCount = min(3, max(0, reminderCount))
        // A user can accept fullscreen rest before the third reminder. Preserve that
        // unfinished page/deadline without inventing extra reminder strikes.
        self.emergencyDueAt = self.reminderCount > 0 ? emergencyDueAt : nil
    }

    var nextAction: Action { emergencyDueAt != nil || reminderCount >= 3 ? .strongRest : .gentleReminder }

    mutating func didPresentGentleReminder() {
        reminderCount = min(3, reminderCount + 1)
    }

    mutating func beginStrongRest(at date: Date, workSeconds: TimeInterval) {
        guard !isStrongRestActive else { return }
        isStrongRestActive = true
        emergencyDueAt = nil
        strongRestStartedAt = date
        workSecondsAtStart = max(0, workSeconds)
    }

    /// Returns true once when a full rest clears an outstanding reminder cycle.
    @discardableResult
    mutating func observeIdle(_ idle: TimeInterval, restThreshold: TimeInterval) -> Bool {
        guard idle.isFinite, idle >= 0, restThreshold.isFinite, restThreshold > 0,
              idle >= restThreshold else { return false }
        let completed = reminderCount > 0 || isStrongRestActive
        clearCycle()
        return completed
    }

    func remaining(at date: Date, idle: TimeInterval, restThreshold: TimeInterval) -> TimeInterval {
        guard let start = strongRestStartedAt else { return max(0, restThreshold) }
        guard idle.isFinite, idle >= 0 else { return max(0, restThreshold) }
        // Do not credit idle from before the page appeared. Any new input restarts this countdown.
        let elapsed = max(0, date.timeIntervalSince(start))
        return max(0, restThreshold - min(idle, elapsed))
    }

    func emergencyRemaining(at date: Date) -> TimeInterval? {
        emergencyDueAt.map { max(0, $0.timeIntervalSince(date)) }
    }

    func shouldResumeStrongRest(at date: Date, idle: TimeInterval,
                                paused: Bool = false, suppressReminders: Bool = false) -> Bool {
        guard let due = emergencyDueAt else { return false }
        return date >= due && idle.isFinite && idle >= 0 && idle <= 2 && !paused && !suppressReminders
    }

    mutating func emergencyDefer(at date: Date) {
        isStrongRestActive = false
        strongRestStartedAt = nil
        emergencyDueAt = date.addingTimeInterval(300)
        // A sleep-inclusive deadline survives short locks and work-timer resets.
    }

    mutating func suspend(at date: Date, idle: TimeInterval) {
        guard systemRestStartedAt == nil else { return }
        let priorIdle = idle.isFinite ? max(0, idle) : 0
        systemRestStartedAt = date.addingTimeInterval(-priorIdle)
    }

    @discardableResult
    mutating func resume(at date: Date, restThreshold: TimeInterval) -> Bool {
        guard let start = systemRestStartedAt else { return false }
        systemRestStartedAt = nil
        guard restThreshold.isFinite, restThreshold > 0,
              date.timeIntervalSince(start) >= restThreshold else { return false }
        let completed = reminderCount > 0 || isStrongRestActive
        clearCycle()
        return completed
    }

    private mutating func clearCycle() {
        reminderCount = 0
        isStrongRestActive = false
        strongRestStartedAt = nil
        workSecondsAtStart = 0
        emergencyDueAt = nil
        // Preserve system-rest timing until its matching unlock/wake event.
    }
}
