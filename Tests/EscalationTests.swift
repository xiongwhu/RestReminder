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

@main struct EscalationTests {
    static func main() {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var policy = RestEscalation()
        var session = ActivitySession()
        var reminders: [Int] = []
        _ = session.sample(now: 0, idle: 0, interval: 1800, restThreshold: 300)
        for second in 1...2700 {
            let due = session.sample(now: Double(second), idle: 0, interval: 1800, restThreshold: 300)
            if due {
                if policy.nextAction == .gentleReminder {
                    reminders.append(second)
                    policy.didPresentGentleReminder()
                    session.deferReminder(now: Double(second), seconds: 300)
                } else {
                    expect(second == 2700, "Strong rest must wait until fourth deadline")
                    policy.beginStrongRest(at: base.addingTimeInterval(Double(second)), workSeconds: Double(second))
                }
            }
        }
        expect(reminders == [1800, 2100, 2400], "30/35/40-minute soft reminders")
        expect(policy.reminderCount == 3 && policy.isStrongRestActive, "45-minute escalation")
        expect(policy.workSecondsAtStart == 2700, "Freeze work duration at page entry")
        expect(policy.remaining(at: base.addingTimeInterval(2700), idle: 0, restThreshold: 300) == 300, "Start full countdown")
        expect(policy.remaining(at: base.addingTimeInterval(2850), idle: 150, restThreshold: 300) == 150, "Idle reduces countdown")
        expect(policy.remaining(at: base.addingTimeInterval(2851), idle: 0, restThreshold: 300) == 300, "Input restarts continuous idle")
        expect(policy.remaining(at: base.addingTimeInterval(2852), idle: .infinity, restThreshold: 300) == 300, "Unknown idle cannot complete rest")
        policy.emergencyDefer(at: base.addingTimeInterval(2710))
        expect(!policy.isStrongRestActive && policy.reminderCount == 3, "Emergency preserves strikes")
        session.deferReminder(now: 2710, seconds: 300)
        for second in 2711..<3010 {
            expect(!session.sample(now: Double(second), idle: 0, interval: 1800, restThreshold: 300), "Honor five-minute emergency deferral")
        }
        expect(session.sample(now: 3010, idle: 0, interval: 1800, restThreshold: 300), "Emergency expires at five minutes")
        expect(policy.nextAction == .strongRest, "Emergency returns straight to strong rest")
        policy.beginStrongRest(at: base.addingTimeInterval(3010), workSeconds: 3010)
        expect(!policy.observeIdle(299, restThreshold: 300), "Partial rest doesn't clear strikes")
        expect(policy.observeIdle(300, restThreshold: 300), "Full rest clears strikes")
        expect(policy.reminderCount == 0 && !policy.isStrongRestActive && policy.nextAction == .gentleReminder, "Fresh reminder cycle")
        expect(!policy.observeIdle(301, restThreshold: 300), "Completion emitted only once")

        // Accepting an early reminder enters the same fullscreen state without
        // manufacturing the remaining strikes. Its emergency/restart path stays fullscreen.
        for count in 1...2 {
            var accepted = RestEscalation(reminderCount: count)
            accepted.beginStrongRest(at: base, workSeconds: 1800)
            expect(accepted.isStrongRestActive && accepted.reminderCount == count,
                   "Accepting reminder \(count) immediately enters rest without extra strikes")
            expect(accepted.remaining(at: base, idle: 120, restThreshold: 300) == 300,
                   "Accepted rest starts with the whole configured duration")
            accepted.emergencyDefer(at: base.addingTimeInterval(10))
            expect(accepted.nextAction == .strongRest && accepted.reminderCount == count,
                   "Emergency returns to the accepted page rather than issuing a new gentle reminder")
            expect(!accepted.shouldResumeStrongRest(at: base.addingTimeInterval(309), idle: 0),
                   "Accepted rest honors the whole emergency delay")
            let reopened = RestEscalation(reminderCount: accepted.reminderCount,
                                          emergencyDueAt: accepted.emergencyDueAt)
            expect(reopened.nextAction == .strongRest && reopened.reminderCount == count &&
                   reopened.shouldResumeStrongRest(at: base.addingTimeInterval(310), idle: 0),
                   "Restart preserves unfinished accepted rest and its original deadline")
            expect(!reopened.shouldResumeStrongRest(at: base.addingTimeInterval(310), idle: 0, suppressReminders: true),
                   "Protection also suppresses resuming accepted rest")
            expect(accepted.observeIdle(300, restThreshold: 300) && accepted.reminderCount == 0 &&
                   accepted.emergencyDueAt == nil && accepted.nextAction == .gentleReminder,
                   "A full voluntary rest clears both the accepted page and its original strikes")
        }
        expect(RestEscalation(reminderCount: 0, emergencyDueAt: base).emergencyDueAt == nil,
               "A stale deadline alone cannot invent an unfinished cycle")

        var audio = RestEscalation()
        var audioSession = ActivitySession()
        _ = audioSession.sample(now: 0, idle: 0, interval: 6, restThreshold: 300)
        for second in 1...100 {
            if audioSession.sample(now: Double(second), idle: 0, interval: 6, restThreshold: 300, suppressReminders: true) {
                audio.didPresentGentleReminder()
            }
        }
        expect(audio.reminderCount == 0, "Suppressed reminders do not count")
        for _ in 0..<3 { audio.didPresentGentleReminder() }
        audio.beginStrongRest(at: base, workSeconds: 1800)
        // Hiding the view for audio changes no policy; a genuine rest can complete while hidden.
        expect(audio.observeIdle(300, restThreshold: 300), "Rest during audio still completes the cycle")

        var locked = RestEscalation()
        for _ in 0..<3 { locked.didPresentGentleReminder() }
        locked.beginStrongRest(at: base, workSeconds: 1800)
        locked.suspend(at: base, idle: 0)
        locked.suspend(at: base.addingTimeInterval(20), idle: 0)
        expect(locked.resume(at: base.addingTimeInterval(1260), restThreshold: 300), "Sleep-inclusive 21-minute rest clears strikes")
        expect(!locked.isStrongRestActive && locked.reminderCount == 0, "Long lock exits strong rest")
        for _ in 0..<3 { locked.didPresentGentleReminder() }
        locked.suspend(at: base, idle: 0)
        expect(!locked.resume(at: base.addingTimeInterval(10), restThreshold: 300), "Short lock preserves strikes")
        expect(locked.reminderCount == 3, "Short lock doesn't erase escalation")
        locked.suspend(at: base, idle: 180)
        expect(locked.resume(at: base.addingTimeInterval(120), restThreshold: 300), "Idle before auto-lock contributes to rest")

        var interrupted = RestEscalation(reminderCount: 3)
        interrupted.emergencyDefer(at: base)
        interrupted.suspend(at: base.addingTimeInterval(100), idle: 0)
        _ = interrupted.resume(at: base.addingTimeInterval(120), restThreshold: 300)
        expect(interrupted.emergencyRemaining(at: base.addingTimeInterval(120)) == 180, "Short lock preserves original emergency deadline")
        expect(!interrupted.shouldResumeStrongRest(at: base.addingTimeInterval(299), idle: 0), "Do not resume early")
        expect(interrupted.shouldResumeStrongRest(at: base.addingTimeInterval(300), idle: 0), "Five minutes includes time spent briefly locked")
        expect(!interrupted.shouldResumeStrongRest(at: base.addingTimeInterval(301), idle: 0, suppressReminders: true), "Audio pauses emergency escalation")
        expect(!interrupted.shouldResumeStrongRest(at: base.addingTimeInterval(301), idle: 0, paused: true), "Pause hides emergency escalation")
        expect(!interrupted.shouldResumeStrongRest(at: base.addingTimeInterval(301), idle: 30), "Wait for input if already resting")
        let restored = RestEscalation(reminderCount: interrupted.reminderCount, emergencyDueAt: interrupted.emergencyDueAt)
        expect(restored.shouldResumeStrongRest(at: base.addingTimeInterval(301), idle: 0), "Reloading stored state preserves deadline and strikes")
        expect(RestEscalation(reminderCount: -9).reminderCount == 0, "Clamp negative restored count")
        expect(RestEscalation(reminderCount: 99).reminderCount == 3, "Clamp excessive restored count")
        expect(interrupted.observeIdle(300, restThreshold: 300), "Qualified rest clears emergency deadline")
        expect(interrupted.emergencyDueAt == nil, "No stale emergency after completion")

        var modal = ActivitySession()
        _ = modal.sample(now: 0, idle: 0, interval: 6, restThreshold: 300)
        modal.acknowledgeCompletedRest(now: 400, idle: 300)
        _ = modal.sample(now: 400, idle: 300, interval: 6, restThreshold: 300)
        expect(modal.feedback == nil, "Complete without celebrating while user is away")
        _ = modal.sample(now: 401, idle: 0, interval: 6, restThreshold: 300)
        expect(modal.feedback == .welcomeBack, "Returning after fullscreen or modal rest celebrates")
        _ = modal.sample(now: 402, idle: 0, interval: 6, restThreshold: 300)
        expect(modal.feedback == nil, "Celebrate completion once")
        modal.suspend(at: base)
        modal.acknowledgeCompletedRest(now: 700, idle: 300)
        modal.resume(at: base.addingTimeInterval(1260), now: 701, restThreshold: 300)
        _ = modal.sample(now: 701, idle: 1260, interval: 6, restThreshold: 300)
        expect(modal.feedback == .welcomeBack, "Completion keeps lock return available for Touch ID")
        print("PASS: fourth-deadline escalation, emergency deadline and preserved strikes, continuous-idle reset, audio suppression, lock/sleep completion, single welcome")
    }
}
