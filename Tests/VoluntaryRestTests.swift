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

private func expect(_ value: @autoclosure () -> Bool, _ message: String) {
    guard value() else { fatalError(message) }
}

@main struct VoluntaryRestTests {
    static func main() {
        var rest = VoluntaryRestSession()
        expect(!rest.isActive && rest.elapsed(at: 100) == 0, "Inactive session has no elapsed rest")
        expect(!rest.start(at: .nan) && !rest.start(at: -.infinity) && !rest.start(at: -1), "Invalid starts are rejected")
        expect(rest.start(at: 10), "Explicit rest starts immediately")
        expect(!rest.start(at: 60) && rest.elapsed(at: 135) == 125, "Repeated start cannot reset elapsed time")
        expect(rest.elapsed(at: 3610) == 3600 && rest.isActive, "Rest can exceed its old target without auto-ending")
        expect(rest.elapsed(at: 7210) == 7200, "Sleep-inclusive monotonic advance counts the whole explicit rest")
        expect(rest.elapsed(at: 9) == 0 && rest.elapsed(at: .infinity) == 0, "Invalid or backwards readings are safe")
        expect(rest.finish(at: 7210) == 7200 && !rest.isActive, "End returns the recorded duration")
        expect(rest.finish(at: 7211) == nil, "Ending twice does not produce another rest")
        expect(rest.start(at: 8000) && rest.elapsed(at: 8002) == 2, "A new session has a fresh origin")

        let base = Date(timeIntervalSince1970: 1_800_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let history = ActivityHistory(storageURL: nil)
        history.sample(at: base, uptime: 0, idle: 0, restThreshold: 300)
        // Work needs observations: the existing model deliberately leaves >10s
        // unsampled work gaps unrecorded instead of inventing work time.
        for second in 1...120 {
            history.sample(at: base.addingTimeInterval(Double(second)), uptime: Double(second), idle: 0, restThreshold: 300)
        }
        let start = base.addingTimeInterval(120)
        history.suspend(at: start, reason: "主动休息")
        history.sample(at: base.addingTimeInterval(160), uptime: 160, idle: 0, restThreshold: 300)
        // System departure overlaps the explicit rest; its suspend must not split or relabel it.
        history.suspend(at: base.addingTimeInterval(180), reason: "屏幕锁定")
        history.sample(at: base.addingTimeInterval(240), uptime: 1000, idle: 0, restThreshold: 300)
        let end = base.addingTimeInterval(420)
        history.sample(at: end, uptime: 1180, idle: 0, restThreshold: 300)
        var day = history.day(base, now: end, calendar: calendar, restThreshold: 300)
        expect(day.workSeconds == 120 && day.restSeconds == 300, "Keyboard input and uptime gaps cannot turn explicit rest into work")
        expect(day.intervals.filter { $0.reason == "主动休息" }.count == 1 && day.completedRestCount == 0,
               "Overlapping lock preserves one ongoing explicit rest interval")
        history.resume(at: end)
        history.sample(at: end, uptime: 1180, idle: 0, restThreshold: 300)
        history.sample(at: end.addingTimeInterval(10), uptime: 1190, idle: 0, restThreshold: 300)
        day = history.day(base, now: end.addingTimeInterval(10), calendar: calendar, restThreshold: 300)
        expect(day.workSeconds == 130 && day.restSeconds == 300 && day.completedRestCount == 1,
               "End closes the rest at the click boundary and starts work once")
        let manual = day.intervals.first { $0.reason == "主动休息" }
        expect(manual?.start == start && manual?.end == end, "History records exact explicit start/end")

        let url = URL(fileURLWithPath: "build/voluntary-history.json")
        let saved = ActivityHistory(storageURL: url)
        saved.sample(at: base, uptime: 0, idle: 0, restThreshold: 300)
        saved.suspend(at: base, reason: "主动休息")
        saved.sample(at: base.addingTimeInterval(30), uptime: 30, idle: 0, restThreshold: 300)
        saved.finish(at: base.addingTimeInterval(35))
        let reloaded = ActivityHistory(storageURL: url)
        let archived = reloaded.day(base, now: base.addingTimeInterval(3000), calendar: calendar)
        expect(archived.restSeconds == 35, "Quit closes the archive; relaunch cannot fabricate stopped-app time")
        expect(!VoluntaryRestSession().isActive, "No unfinished explicit timer is silently restored")
        print("PASS: voluntary count-up, explicit end, independent input, overlapping lock/sleep history, exact boundaries and quit/reload")
    }
}
