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

var session = ActivitySession()
expect(!session.sample(now: 0, idle: 0, interval: 1800, restThreshold: 120), "Start without alert")
for second in 1..<1800 {
    expect(!session.sample(now: Double(second), idle: 0, interval: 1800, restThreshold: 120), "No early alert")
}
expect(session.sample(now: 1800, idle: 0, interval: 1800, restThreshold: 120), "Alert at 30 minutes")
session.deferReminder(now: 1800, seconds: 300)
for second in 1801..<2100 {
    expect(!session.sample(now: Double(second), idle: 0, interval: 1800, restThreshold: 120), "Honor snooze")
}
expect(session.sample(now: 2100, idle: 0, interval: 1800, restThreshold: 120), "Alert after snooze")
expect(!session.sample(now: 2101, idle: 120, interval: 1800, restThreshold: 120), "Rest resets")
expect(session.startedAt == nil && session.deferredUntil == nil, "Clear session and snooze")
expect(!session.sample(now: 2102, idle: 0, interval: 1800, restThreshold: 120), "Fresh session")
expect(!session.sample(now: 2103, idle: 30, interval: 1800, restThreshold: 120), "Brief pause")
expect(session.startedAt == 2102, "Brief pause preserves start")
expect(!session.sample(now: 3000, idle: 0, interval: 1800, restThreshold: 120), "Sleep gap resets")
expect(session.startedAt == 3000, "Wake starts new session")
session.paused = true
expect(!session.sample(now: 3001, idle: 0, interval: 6, restThreshold: 120), "Paused doesn't remind")
expect(session.startedAt == nil, "Pause clears start")
session.paused = false
expect(!session.sample(now: 3002, idle: 50, interval: 6, restThreshold: 120), "Wait for activity on launch")
expect(session.startedAt == nil, "Idle launch does not start session")
expect(!session.sample(now: 3003, idle: 0, interval: 6, restThreshold: 120), "Start short test interval")
for second in 3004...3010 {
    expect(!session.sample(now: Double(second), idle: 5, interval: 6, restThreshold: 120), "Don't interrupt while idle")
}
expect(!session.sample(now: 3011, idle: 0, interval: 6, restThreshold: 120), "Exercise suggestion replaces immediate modal on early return")
expect(session.feedback == .needsMoreRest, "Due session suggests exercise on early return")
expect(!session.sample(now: 3012, idle: .infinity, interval: 6, restThreshold: 120), "Invalid idle is safe")
// A genuine rest celebrates exactly once, on input rather than during idle.
var returning = ActivitySession()
_ = returning.sample(now: 0, idle: 0, interval: 30, restThreshold: 10)
for second in 1...12 {
    _ = returning.sample(now: Double(second), idle: Double(second), interval: 30, restThreshold: 10)
    expect(returning.feedback == nil, "No celebration before return")
}
expect(!returning.sample(now: 13, idle: 0, interval: 30, restThreshold: 10), "Return starts fresh")
expect(returning.feedback == .welcomeBack, "Completed rest celebrates")
expect(returning.startedAt == 13, "Return resets countdown")
_ = returning.sample(now: 14, idle: 0, interval: 30, restThreshold: 10)
expect(returning.feedback == nil, "Celebrate once")

var shortRest = ActivitySession()
_ = shortRest.sample(now: 0, idle: 0, interval: 30, restThreshold: 20)
shortRest.beginRest(now: 0, seconds: 20)
for second in 1...7 {
    _ = shortRest.sample(now: Double(second), idle: Double(second), interval: 30, restThreshold: 20)
}
_ = shortRest.sample(now: 8, idle: 0, interval: 30, restThreshold: 20)
expect(shortRest.feedback == .needsMoreRest, "Early return suggests exercise")
for second in 9...14 {
    _ = shortRest.sample(now: Double(second), idle: Double(second - 8), interval: 30, restThreshold: 20)
}
_ = shortRest.sample(now: 15, idle: 0, interval: 30, restThreshold: 20)
expect(shortRest.feedback == nil, "Exercise suggestion has cooldown")
for second in 16...36 {
    _ = shortRest.sample(now: Double(second), idle: Double(second - 15), interval: 30, restThreshold: 20)
}
_ = shortRest.sample(now: 37, idle: 0, interval: 30, restThreshold: 20)
expect(shortRest.feedback == .welcomeBack, "Full rest after early return celebrates")

var normalPause = ActivitySession()
_ = normalPause.sample(now: 0, idle: 0, interval: 1800, restThreshold: 120)
for second in 1...8 {
    _ = normalPause.sample(now: Double(second), idle: Double(second), interval: 1800, restThreshold: 120)
}
_ = normalPause.sample(now: 9, idle: 0, interval: 1800, restThreshold: 120)
expect(normalPause.feedback == nil, "Ordinary brief pauses don't nag")
var idleLaunch = ActivitySession()
_ = idleLaunch.sample(now: 0, idle: 200, interval: 30, restThreshold: 10)
_ = idleLaunch.sample(now: 1, idle: 0, interval: 30, restThreshold: 10)
expect(idleLaunch.feedback == nil, "No false celebration on idle launch")
idleLaunch.reset()
expect(idleLaunch.feedback == nil, "Reset clears feedback")
print("PASS: timing, snooze, rest reset, sleep, pause, idle launch, welcome on return, single celebration, exercise suggestion, cooldown, recovery after short rest, ordinary pause")
