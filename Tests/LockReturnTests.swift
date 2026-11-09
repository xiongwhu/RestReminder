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

func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError(message) }
}

@main struct LockReturnTests {
    static func main() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var lifecycle = SystemRestState()
        var session = ActivitySession()
        _ = session.sample(now: 0, idle: 0, interval: 1800, restThreshold: 120)
        expect(lifecycle.update(.screenLock, inactive: true) == .left, "First lock starts system rest")
        session.suspend(at: base)
        expect(lifecycle.update(.screenLock, inactive: true) == nil, "Duplicate lock is ignored")
        expect(lifecycle.update(.sleep, inactive: true) == nil, "Sleep while locked does not restart rest")
        session.suspend(at: base.addingTimeInterval(60)) // Also defend against repeated begin calls.
        expect(!session.sample(now: 10, idle: 0, interval: 1800, restThreshold: 120), "Locked input cannot trigger a reminder")
        expect(session.feedback == nil, "No welcome over lock screen")
        expect(lifecycle.update(.sleep, inactive: false) == nil, "Wake while still locked does not expose welcome")
        expect(lifecycle.isInactive, "Still locked after waking")
        expect(lifecycle.update(.screenLock, inactive: false) == .returned, "Final unlock returns")
        // Only 15 uptime seconds pass, while 21 minutes elapse including sleep.
        session.resume(at: base.addingTimeInterval(1260), now: 15, restThreshold: 120)
        expect(!session.sample(now: 15, idle: 0, interval: 1800, restThreshold: 120), "No stale work alert on unlock")
        expect(session.feedback == .welcomeBack, "21-minute locked rest welcomes")
        expect(session.startedAt == 15, "Work restarts on unlock")
        expect(lifecycle.update(.screenLock, inactive: false) == nil, "Duplicate unlock is ignored")
        session.resume(at: base.addingTimeInterval(1261), now: 16, restThreshold: 120)
        _ = session.sample(now: 16, idle: 0, interval: 1800, restThreshold: 120)
        expect(session.feedback == nil, "No duplicate welcome")

        var touchID = ActivitySession()
        touchID.suspend(at: base)
        touchID.resume(at: base.addingTimeInterval(1300), now: 2, restThreshold: 120)
        _ = touchID.sample(now: 2, idle: 1300, interval: 1800, restThreshold: 120)
        expect(touchID.feedback == .welcomeBack, "Touch ID unlock welcomes even without fresh keyboard idle")
        _ = touchID.sample(now: 3, idle: 1301, interval: 1800, restThreshold: 120)
        expect(touchID.feedback == nil, "Continuing idle does not repeat welcome")
        _ = touchID.sample(now: 4, idle: 0, interval: 1800, restThreshold: 120)
        expect(touchID.feedback == nil && touchID.startedAt == 4, "First mouse movement starts work without second sun")

        var delayed = ActivitySession()
        delayed.suspend(at: base)
        delayed.resume(at: base.addingTimeInterval(1300), now: 2, restThreshold: 120)
        _ = delayed.sample(now: 30, idle: 0, interval: 1800, restThreshold: 120)
        expect(delayed.feedback == .welcomeBack, "Scheduling gap cannot erase pending welcome")

        var audio = ActivitySession()
        audio.suspend(at: base)
        audio.resume(at: base.addingTimeInterval(1300), now: 2, restThreshold: 120)
        _ = audio.sample(now: 2, idle: 0, interval: 1800, restThreshold: 120, suppressReminders: true)
        expect(audio.feedback == nil, "Audio still suppresses unlock celebration")
        _ = audio.sample(now: 3, idle: 0, interval: 1800, restThreshold: 120)
        expect(audio.feedback == nil, "Suppressed unlock celebration is not queued")

        var short = ActivitySession()
        short.suspend(at: base)
        short.resume(at: base.addingTimeInterval(10), now: 10, restThreshold: 120)
        _ = short.sample(now: 10, idle: 0, interval: 1800, restThreshold: 120)
        expect(short.feedback == nil, "Short lock doesn't claim a full rest")

        var paused = ActivitySession()
        paused.paused = true
        paused.suspend(at: base)
        paused.resume(at: base.addingTimeInterval(1300), now: 2, restThreshold: 120)
        _ = paused.sample(now: 2, idle: 0, interval: 1800, restThreshold: 120)
        expect(paused.feedback == nil, "Paused reminders remain paused after unlock")

        var overlap = SystemRestState()
        expect(overlap.update(.inactiveSession, inactive: true) == .left, "User switch starts rest")
        _ = overlap.update(.screenLock, inactive: true)
        _ = overlap.update(.sleep, inactive: true)
        expect(overlap.update(.screenLock, inactive: false) == nil, "Unlock alone cannot finish multiple inactive reasons")
        expect(overlap.update(.inactiveSession, inactive: false) == nil, "Wait for wake too")
        expect(overlap.update(.sleep, inactive: false) == .returned, "Final reason cleared returns exactly once")
        print("PASS: 21-minute lock, sleep-inclusive duration, notification overlap/deduplication, no locked-screen UI, Touch ID, delayed tick, audio suppression, short lock, pause")
    }
}
