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

@main
struct AudioTests {
    static func main() {
        var quiet = AudioQuietPeriod()
        expect(!quiet.update(state: .silent, now: 0), "Normal silent launch")
        expect(quiet.update(state: .playing, now: 1), "Playback suppresses reminders")
        expect(quiet.update(state: .playing, now: 10), "Playback renews grace period")
        expect(quiet.update(state: .silent, now: 19), "Short pause stays quiet")
        expect(!quiet.update(state: .silent, now: 20), "Resume after 10 seconds")
        expect(!quiet.update(state: .unavailable, now: 21), "Missing permission does not suppress forever")
        expect(!quiet.update(state: .silent, now: 31), "Recover after query error")
        expect(quiet.update(state: .playing, now: 40), "New real sound suppresses")
        expect(quiet.update(state: .unavailable, now: 45), "Existing grace survives temporary disconnect")
        expect(!quiet.update(state: .unavailable, now: 50), "Disconnect cannot extend grace")

        func audible(_ samples: [Float]) -> Bool {
            samples.withUnsafeBufferPointer { AudioSignalLevel.hasSound($0) }
        }
        expect(!audible([]), "Empty buffer is not sound")
        expect(!audible(Array(repeating: 0, count: 4096)), "Open silent stream must not mean playing")
        expect(!audible(Array(repeating: 0.000001, count: 4096)), "Ignore numerical noise")
        expect(audible(Array(repeating: 0.001, count: 4096)), "Quiet signal counts as sound")
        expect(audible((0..<4096).map { sin(Float($0) * 0.1) * 0.01 }), "Music-like signal counts")
        expect(!audible([.nan, .infinity, -.infinity, 0]), "Invalid samples do not create sound")
        expect(!audible(Array(repeating: 0, count: 4096)), "Silence after sound clears signal")

        var session = ActivitySession()
        _ = session.sample(now: 0, idle: 0, interval: 6, restThreshold: 10)
        for second in 1...12 {
            expect(!session.sample(now: Double(second), idle: 0, interval: 6,
                                   restThreshold: 10, suppressReminders: true), "No modal during playback")
        }
        expect(session.startedAt == 0, "Audio does not reset work timer")
        expect(session.sample(now: 13, idle: 0, interval: 6, restThreshold: 10), "Due reminder can resume after audio")
        for second in 14...25 {
            _ = session.sample(now: Double(second), idle: Double(second - 13), interval: 6,
                               restThreshold: 10, suppressReminders: true)
        }
        expect(session.startedAt == nil, "Rest still resets while audio plays")
        _ = session.sample(now: 26, idle: 0, interval: 6, restThreshold: 10, suppressReminders: true)
        expect(session.feedback == nil, "No welcome over a video")
        expect(session.startedAt == 26, "Returning during audio starts a fresh timer")
        _ = session.sample(now: 27, idle: 0, interval: 6, restThreshold: 10)
        expect(session.feedback == nil, "No delayed celebration after playback")

        session.beginRest(now: 27, seconds: 10)
        for second in 28...32 {
            _ = session.sample(now: Double(second), idle: Double(second - 27), interval: 6,
                               restThreshold: 10, suppressReminders: true)
        }
        expect(!session.sample(now: 33, idle: 0, interval: 6, restThreshold: 10,
                               suppressReminders: true), "No modal on early return during playback")
        expect(session.feedback == nil, "No exercise panel during playback")
        print("PASS: playback suppression, grace period, error recovery, work timing, rest reset, welcome discarded, exercise suppressed")
    }
}
