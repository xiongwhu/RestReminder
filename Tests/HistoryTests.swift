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

private func tryData(_ url: URL) -> Data { try! Data(contentsOf: url) }

private final class MemoryHistoryPreferences: ActivityHistoryPreferences {
    var historyRetentionDays: Int
    init(_ days: Int = 0) { historyRetentionDays = days }
}

@main struct HistoryTests {
    static func main() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let base = calendar.date(from: DateComponents(year: 2026, month: 11, day: 5, hour: 12))!
        func date(_ seconds: Double) -> Date { base.addingTimeInterval(seconds) }
        let history = ActivityHistory(storageURL: nil)
        for second in 0...30 {
            history.sample(at: date(Double(second)), uptime: Double(second), idle: 0, restThreshold: 10)
        }
        for second in 31...40 {
            history.sample(at: date(Double(second)), uptime: Double(second), idle: Double(second - 30), restThreshold: 10)
        }
        var day = history.day(base, now: date(40), calendar: calendar)
        expect(day.workSeconds == 30 && day.restSeconds == 10, "Backdate rest to last input")
        expect(day.intervals.count == 2 && day.intervals[1].start == date(30), "Exact rest boundary")
        history.sample(at: date(41), uptime: 41, idle: 0, restThreshold: 10)
        history.sample(at: date(42), uptime: 42, idle: 0, restThreshold: 10)
        day = history.day(base, now: date(42), calendar: calendar)
        expect(day.workSeconds == 31 && day.restSeconds == 11, "Returning starts work")
        expect(day.ongoingStart == date(41), "Ongoing work tagged")
        expect(history.day(base, now: date(40), calendar: calendar, restThreshold: 10).completedRestCount == 0,
               "A rest ending after the query time is not completed yet")
        expect(history.day(base, now: date(42), calendar: calendar, restThreshold: 10).completedRestCount == 1,
               "Closed qualifying short rest counts once")
        expect(day.completedRestCount == 0, "Default threshold preserves existing day call syntax")

        let brief = ActivityHistory(storageURL: nil)
        brief.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        for second in 1...5 { brief.sample(at: date(Double(second)), uptime: Double(second), idle: Double(second), restThreshold: 10) }
        brief.sample(at: date(6), uptime: 6, idle: 0, restThreshold: 10)
        expect(brief.day(base, now: date(6), calendar: calendar).workSeconds == 6, "Brief idle stays work")

        let sleep = ActivityHistory(storageURL: nil)
        sleep.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        sleep.sample(at: date(5), uptime: 5, idle: 0, restThreshold: 10)
        sleep.suspend(at: date(5))
        sleep.suspend(at: date(6))
        sleep.resume(at: date(100))
        sleep.sample(at: date(100), uptime: 100, idle: 0, restThreshold: 10)
        sleep.sample(at: date(105), uptime: 105, idle: 0, restThreshold: 10)
        day = sleep.day(base, now: date(105), calendar: calendar)
        expect(day.workSeconds == 10 && day.restSeconds == 95, "Sleep is rest without duplicate intervals")

        let gap = ActivityHistory(storageURL: nil)
        gap.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        gap.sample(at: date(5), uptime: 5, idle: 0, restThreshold: 10)
        gap.sample(at: date(100), uptime: 100, idle: 0, restThreshold: 10)
        gap.sample(at: date(105), uptime: 105, idle: 0, restThreshold: 10)
        expect(gap.day(base, now: date(105), calendar: calendar).workSeconds == 10, "Unobserved gap is not fabricated")
        gap.sample(at: date(104), uptime: 106, idle: 0, restThreshold: 10)
        expect(gap.day(base, now: date(105), calendar: calendar).workSeconds == 10, "Clock rollback creates no overlap")

        let midnight = calendar.startOfDay(for: base).addingTimeInterval(86400)
        let crossDay = ActivityHistory(storageURL: nil)
        crossDay.suspend(at: midnight.addingTimeInterval(-60))
        crossDay.resume(at: midnight.addingTimeInterval(60))
        expect(crossDay.day(base, now: midnight.addingTimeInterval(60), calendar: calendar).restSeconds == 60, "Clip before midnight")
        expect(crossDay.day(midnight, now: midnight.addingTimeInterval(60), calendar: calendar).restSeconds == 60, "Clip after midnight")
        var dstCalendar = calendar
        dstCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let dstDate = dstCalendar.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))!
        let dstRange = dstCalendar.dateInterval(of: .day, for: dstDate)!
        let dst = ActivityHistory(storageURL: nil)
        dst.suspend(at: dstRange.start)
        dst.resume(at: dstRange.end)
        let dstDay = dst.day(dstDate, now: dstRange.end, calendar: dstCalendar)
        expect(dstDay.awaySeconds == 23 * 3600 && dstDay.restSeconds == 0, "Spring DST uses actual day length for away")
        let fallDate = dstCalendar.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))!
        let fallRange = dstCalendar.dateInterval(of: .day, for: fallDate)!
        let fall = ActivityHistory(storageURL: nil)
        fall.suspend(at: fallRange.start)
        fall.resume(at: fallRange.end)
        expect(fall.day(fallDate, now: fallRange.end, calendar: dstCalendar).awaySeconds == 25 * 3600,
               "Fall DST uses actual day length for away")

        let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/history-tests-\(UUID().uuidString)", isDirectory: true)
        let file = directory.appendingPathComponent("history.json")
        let persisted = ActivityHistory(storageURL: file)
        persisted.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        persisted.sample(at: date(5), uptime: 5, idle: 0, restThreshold: 10)
        persisted.finish(at: date(5))
        expect(persisted.persistenceError == nil, "History saves locally")
        let reloaded = ActivityHistory(storageURL: file)
        reloaded.sample(at: date(100), uptime: 100, idle: 0, restThreshold: 10)
        reloaded.sample(at: date(105), uptime: 105, idle: 0, restThreshold: 10)
        reloaded.finish(at: date(105))
        expect(reloaded.day(base, now: date(105), calendar: calendar).workSeconds == 10, "Restart loads history without counting downtime")
        reloaded.suspend(at: date(100))
        expect(reloaded.day(base, now: date(110), calendar: calendar).restSeconds == 0,
               "A suspend notification before the loaded archive end cannot create overlapping records")
        let corruptFile = directory.appendingPathComponent("corrupt.json")
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: corruptFile)
        let corrupt = ActivityHistory(storageURL: corruptFile)
        expect(corrupt.persistenceError != nil, "Corruption is visible")
        corrupt.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        corrupt.finish(at: date(5))
        let preservedData = try Data(contentsOf: corruptFile)
        expect(preservedData == corruptData, "Never overwrite unreadable history")
        // Independently write the original v1 archive shape; no presentation category is persisted.
        func fixture(_ name: String, _ records: [ActivityRecord]) throws -> ActivityHistory {
            let entries: [[String: Any]] = records.map {
                ["start": $0.start.timeIntervalSince1970 * 1000,
                 "end": $0.end.timeIntervalSince1970 * 1000,
                 "kind": $0.kind.rawValue, "reason": $0.reason]
            }
            let data = try JSONSerialization.data(withJSONObject: ["version": 1, "records": entries])
            let url = directory.appendingPathComponent(name + ".json")
            try data.write(to: url)
            let loaded = ActivityHistory(storageURL: url)
            expect(loaded.persistenceError == nil, "Valid original v1 archive loads: \(name)")
            return loaded
        }
        func record(_ start: Double, _ end: Double, _ kind: ActivityKind) -> ActivityRecord {
            ActivityRecord(start: date(start), end: date(end), kind: kind, reason: "v1 fixture")
        }

        func display(_ start: Double, _ end: Double, _ kind: ActivityDisplayKind = .work,
                     _ reason: String = "detail fixture") -> ActivityDisplayInterval {
            ActivityDisplayInterval(start: date(start), end: date(end), kind: kind, reason: reason)
        }
        let limits = [display(0, 10), display(130, 140), display(261, 271),
                      display(271, 281, .rest), display(282, 292)]
        let limitGroups = ActivityDetailGroup.grouped(limits, calendar: calendar)
        expect(limitGroups.map { $0.intervals.count } == [2, 1, 1, 1],
               "Exactly 120 seconds merges; 121 seconds and intervening display kinds split details")
        expect(limitGroups[0].duration == 20 && limitGroups[0].gapDuration == 120 &&
               limitGroups[0].start == date(0) && limitGroups[0].end == date(140),
               "A group's recorded sum excludes the gap inside its displayed envelope")
        expect(ActivityDetailGroup.grouped(Array(limits.reversed()), calendar: calendar).map { $0.start } ==
               limitGroups.map { $0.start }, "Unordered input produces chronological groups")
        let adjacent = [display(0, 10), display(10, 20), display(20.5, 30)]
        for invalidLimit in [-1.0, Double.nan, Double.infinity, -Double.infinity] {
            expect(ActivityDetailGroup.grouped(adjacent, maximumGap: invalidLimit, calendar: calendar)
                .map { $0.intervals.count } == [2, 1],
                   "Invalid gap limits allow exact adjacency but never a positive-gap merge")
        }
        expect(ActivityDetailGroup.grouped([display(0, 10), display(40, 50), display(81, 91)],
               maximumGap: 30, calendar: calendar).map { $0.intervals.count } == [2, 1],
               "A custom positive maximum gap is inclusive")
        expect(ActivityDetailGroup.grouped([], calendar: calendar).isEmpty &&
               ActivityHistory(storageURL: nil).day(base, calendar: calendar).detailGroups.isEmpty,
               "Empty history and empty grouping have no detail rows")
        let kinds = ActivityDetailGroup.grouped([display(0, 10), display(10, 10.5, .rest),
            display(10.5, 20), display(20, 20.5, .away), display(20.5, 30, .rest)], calendar: calendar)
        expect(kinds.map { $0.kind } == [.work, .rest, .work, .away, .rest],
               "Every opposite display kind, including a subsecond one, remains a grouping barrier")
        for malformed in [display(11, 11), display(11, 10), display(11, .nan), display(11, .infinity),
                          display(.nan, 11), display(-.infinity, 11)] {
            let groups = ActivityDetailGroup.grouped([display(0, 10), malformed, display(12, 22)], calendar: calendar)
            expect(groups.count == 2 && groups.allSatisfy { $0.intervals.count == 1 },
                   "Malformed intervals are discarded as barriers rather than bridged")
        }
        expect(ActivityDetailGroup.grouped([display(0, 10), display(9, 11), display(12, 22)], calendar: calendar)
            .map { $0.intervals.count } == [1, 1, 1], "Overlapping members split groups on both sides")
        expect(ActivityDetailGroup.grouped([display(0, 100), display(10, 20), display(30, 40), display(110, 120)],
            calendar: calendar).count == 4, "A nested overlap cannot bridge across an earlier occupied span")
        let original = display(0, 10, .rest, "idle")
        let reasons = ActivityDetailGroup.grouped([original, display(11, 21, .rest, "sleep"),
            display(22, 32, .rest, "idle"), display(33, 43, .rest, "manual；detail")], calendar: calendar)[0]
        expect(reasons.reason == "idle；sleep；manual；detail", "Distinct original reasons retain chronological order")
        expect(reasons.contains(original) && !reasons.contains(display(0, 10, .rest, "sleep")) &&
               !reasons.contains(display(0, 10, .work, "idle")) && !reasons.contains(display(0, 11, .rest, "idle")) &&
               !reasons.contains(display(1, 10, .rest, "idle")) && !reasons.contains(display(10, 11, .rest, "idle")),
               "Membership matches all original fields exactly, including boundaries, kind and reason")
        let midnightMembers = [ActivityDisplayInterval(start: midnight.addingTimeInterval(-60), end: midnight,
            kind: .work, reason: "before midnight"), ActivityDisplayInterval(start: midnight,
            end: midnight.addingTimeInterval(60), kind: .work, reason: "after midnight")]
        expect(ActivityDetailGroup.grouped(midnightMembers, calendar: calendar).count == 2,
               "Adjacent half-open intervals on different local dates never merge")
        var easternCalendar = calendar
        easternCalendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        expect(ActivityDetailGroup.grouped(midnightMembers, calendar: easternCalendar).count == 1,
               "The supplied calendar determines whether timestamps share a date")
        for transitionRange in [dstRange, fallRange] {
            let firstEnd = transitionRange.start.addingTimeInterval(2 * 3600 - 10)
            let secondStart = transitionRange.start.addingTimeInterval(2 * 3600 + 10)
            let transition = ActivityDetailGroup.grouped([
                ActivityDisplayInterval(start: firstEnd.addingTimeInterval(-10), end: firstEnd, kind: .work, reason: "first"),
                ActivityDisplayInterval(start: secondStart, end: secondStart.addingTimeInterval(10), kind: .work, reason: "second")
            ], calendar: dstCalendar)
            expect(transition.count == 1 && transition[0].duration == 20 && transition[0].gapDuration == 20,
                   "Spring skipped hours and fall repeated hours use elapsed gap seconds on the same local day")
        }

        let screenshotRecords = [ActivityRecord(start: date(0), end: date(300), kind: .work, reason: "work A"),
            ActivityRecord(start: date(329), end: date(629), kind: .work, reason: "work A"),
            ActivityRecord(start: date(693), end: date(993), kind: .work, reason: "work B"),
            ActivityRecord(start: date(1000), end: date(1600), kind: .rest, reason: "idle"),
            ActivityRecord(start: date(1697), end: date(2297), kind: .rest, reason: "sleep"),
            ActivityRecord(start: date(2304), end: date(2604), kind: .work, reason: "work before update")]
        let screenshot = try fixture("detail-screenshot", screenshotRecords)
        screenshot.sample(at: date(2633), uptime: 0, idle: 0, restThreshold: 120)
        screenshot.sample(at: date(2633.5), uptime: 0.5, idle: 0, restThreshold: 120)
        let hiddenOngoing = screenshot.day(base, now: date(2633.5), calendar: calendar)
        expect(hiddenOngoing.displayIntervals.count == 6 && hiddenOngoing.detailGroups.last!.duration == 300.5 &&
               hiddenOngoing.detailGroups.last!.intervals.last!.start == hiddenOngoing.ongoingStart &&
               hiddenOngoing.detailGroups.last!.contains(hiddenOngoing.detailGroups.last!.intervals.last!),
               "An ongoing subsecond member remains in its visible detail group while hidden from the timeline")
        screenshot.sample(at: date(2638), uptime: 5, idle: 0, restThreshold: 120)
        let screenshotURL = directory.appendingPathComponent("detail-screenshot.json")
        let screenshotArchiveBefore = tryData(screenshotURL)
        let screenshotRange = calendar.dateInterval(of: .day, for: base)!
        let screenshotCSVBefore = screenshot.csv(in: screenshotRange, now: date(2638), calendar: calendar)
        let screenshotDay = screenshot.day(base, now: date(2638), calendar: calendar)
        expect(screenshotDay.detailGroups.map { $0.intervals.count } == [3, 2, 2] &&
               screenshotDay.detailGroups.map { $0.kind } == [.work, .rest, .work],
               "Update gaps of 29, 64 and 97 seconds collapse realistic neighboring work/rest detail rows")
        expect(screenshotDay.detailGroups.map { $0.duration } == [900, 1200, 305] &&
               screenshotDay.detailGroups.map { $0.gapDuration } == [93, 97, 29],
               "Merged row durations sum recorded pieces and expose each omitted update gap")
        expect(screenshotDay.detailGroups[0].reason == "work A；work B" &&
               screenshotDay.detailGroups[1].reason == "idle；sleep", "Different reasons do not prevent merging")
        expect(screenshotDay.ongoingStart == date(2633) &&
               screenshotDay.detailGroups.last!.contains(screenshotDay.displayIntervals.last!) &&
               screenshotDay.detailGroups.last!.start != screenshotDay.ongoingStart,
               "An ongoing original member remains identifiable even when its group's start is older")
        expect(screenshotDay.intervals.count == 7 && screenshotDay.displayIntervals.count == 7 &&
               screenshotDay.workSeconds == 1205 && screenshotDay.restSeconds == 1200 && screenshotDay.awaySeconds == 0 &&
               screenshotDay.longestWorkSeconds == 300 && screenshotDay.completedRestCount == 2,
               "Detail grouping preserves raw counts, totals, maximum single work and individual rest completions")
        let screenshotWeek = screenshot.week(base, now: date(2638), calendar: calendar)
        expect(screenshotWeek.workSeconds == 1205 && screenshotWeek.restSeconds == 1200 && screenshotWeek.awaySeconds == 0,
               "Weekly totals remain sums of the original recorded time")
        let screenshotCSV = String(data: screenshotCSVBefore, encoding: .utf8)!
        expect(screenshotCSV.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count == 8 &&
               screenshotCSV.contains("\"600\",\"rest\"") && !screenshotCSV.contains("\"1200\",\"rest\"") &&
               screenshot.csv(in: screenshotRange, now: date(2638), calendar: calendar) == screenshotCSVBefore &&
               tryData(screenshotURL) == screenshotArchiveBefore,
               "Viewing grouped details neither groups CSV source rows nor rewrites the archive")
        screenshot.finish(at: date(2638))
        let screenshotSaved = try JSONSerialization.jsonObject(with: tryData(screenshotURL)) as! [String: Any]
        let screenshotSavedRecords = screenshotSaved["records"] as! [[String: Any]]
        expect(screenshotSaved["version"] as? Int == 1 && screenshotSavedRecords.count == 7 &&
               screenshotSavedRecords.prefix(6).map { $0["reason"] as! String } == screenshotRecords.map { $0.reason } &&
               screenshotSavedRecords.allSatisfy { ["work", "rest"].contains($0["kind"] as? String ?? "") },
               "A later save retains every raw archive record and the original v1 classification")

        let hiddenDetails = try fixture("detail-hidden", [record(0, 10, .work), record(10, 10.5, .rest),
            record(10.5, 20.5, .work), record(30, 30.5, .work), record(31, 31.5, .work)])
        let hiddenDetailDay = hiddenDetails.day(base, now: date(32), calendar: calendar)
        expect(hiddenDetailDay.displayIntervals.count == 2 && hiddenDetailDay.detailGroups.count == 2 &&
               hiddenDetailDay.detailGroups.map { $0.duration } == [10, 11] &&
               hiddenDetailDay.detailGroups.map { $0.intervals.count } == [1, 3],
               "A hidden half-second rest blocks work merging while hidden same-kind fractions stay in the next group")
        expect(hiddenDetailDay.workSeconds == 21 && hiddenDetailDay.restSeconds == 0.5 &&
               hiddenDetailDay.longestWorkSeconds == 10 && hiddenDetailDay.intervals.count == 5,
               "Including hidden detail fragments leaves all raw statistics untouched")
        let combinedFractions = try fixture("detail-fractions", [record(0, 0.5, .work), record(120.5, 121, .work)])
            .day(base, now: date(122), calendar: calendar)
        expect(combinedFractions.displayIntervals.isEmpty && combinedFractions.detailGroups.count == 1 &&
               combinedFractions.detailGroups[0].duration == 1 && combinedFractions.detailGroups[0].gapDuration == 120,
               "Same-kind fractions can form a one-recorded-second detail group without changing the timeline")
        let filteredFractions = try fixture("detail-fraction-barrier", [record(0, 0.5, .work), record(0.5, 1, .rest),
            record(1, 1.5, .work)]).day(base, now: date(2), calendar: calendar)
        expect(filteredFractions.detailGroups.isEmpty, "The one-second filter runs after hidden opposite-kind barriers split groups")
        let summedRests = try fixture("detail-summed-rest", [record(0, 2000, .rest), record(2097, 4097, .rest)])
        let summedRestDay = summedRests.day(base, now: date(4100), calendar: calendar)
        expect(summedRestDay.detailGroups.count == 1 && summedRestDay.detailGroups[0].kind == .rest &&
               summedRestDay.detailGroups[0].duration == 4000 && summedRestDay.restSeconds == 4000 &&
               summedRestDay.awaySeconds == 0 && summedRestDay.completedRestCount == 2,
               "Joining original short rests beyond one hour never reclassifies their sum as away")

        let boundary = try fixture("away-boundary", [record(0, 3599.75, .rest),
            record(3600, 7200, .rest), record(7201, 10801.25, .rest), record(10802, 10862, .work)])
        let boundaryDay = boundary.day(base, now: date(11000), calendar: calendar, restThreshold: 120)
        expect(boundaryDay.restSeconds == 3599.75 && boundaryDay.awaySeconds == 7200.25,
               "Below one hour is rest; exactly one hour and above are wholly away")
        expect(boundaryDay.workSeconds == 60 && boundaryDay.completedRestCount == 1,
               "Away never contributes to rest completion count")
        expect(boundaryDay.displayIntervals.map { $0.kind } == [.rest, .away, .away, .work],
               "Presentation uses the same classification as totals")
        expect(boundaryDay.detailGroups.map { $0.kind } == [.rest, .away, .work] &&
               boundaryDay.detailGroups[1].duration == 7200.25 && boundaryDay.detailGroups[1].gapDuration == 1,
               "Only the original away members merge, preserving their classification and excluding their gap")
        expect(boundaryDay.intervals.map { $0.kind } == [.rest, .rest, .rest, .work],
               "Raw v1 intervals keep their original kinds")
        expect(boundaryDay.workSeconds + boundaryDay.restSeconds == 3659.75,
               "Work/rest comparison denominator excludes away")
        let boundaryURL = directory.appendingPathComponent("away-boundary.json")
        let beforeViewing = try Data(contentsOf: boundaryURL)
        _ = boundary.day(base, now: date(11000), calendar: calendar, restThreshold: 60)
        let afterViewing = try Data(contentsOf: boundaryURL)
        expect(beforeViewing == afterViewing, "Reclassification never rewrites old archives")
        boundary.finish(at: date(11000))
        let savedArchive = try JSONSerialization.jsonObject(with: Data(contentsOf: boundaryURL)) as! [String: Any]
        let savedRecords = savedArchive["records"] as! [[String: Any]]
        expect(savedArchive["version"] as? Int == 1 && savedRecords.count == 4,
               "Saving loaded history preserves the v1 archive and all records")
        expect(savedRecords.allSatisfy { ["work", "rest"].contains($0["kind"] as? String ?? "") },
               "Display-only away kind never enters persisted data")

        let growing = ActivityHistory(storageURL: nil)
        growing.suspend(at: date(0))
        growing.sample(at: date(3599.75), uptime: 3599.75, idle: 3599.75, restThreshold: 120)
        let beforeHour = growing.day(base, now: date(3599.75), calendar: calendar, restThreshold: 120)
        expect(beforeHour.restSeconds == 3599.75 && beforeHour.awaySeconds == 0 && beforeHour.completedRestCount == 0,
               "Ongoing short rest contributes time but no completion")
        growing.sample(at: date(3600), uptime: 3600, idle: 3600, restThreshold: 120)
        let atHour = growing.day(base, now: date(3600), calendar: calendar, restThreshold: 120)
        expect(atHour.restSeconds == 0 && atHour.awaySeconds == 3600 && atHour.completedRestCount == 0,
               "Ongoing rest switches its entire duration to away at exactly one hour")
        expect(atHour.displayIntervals.first?.kind == .away && atHour.ongoingStart == date(0),
               "Current away remains visibly ongoing")

        let shortRests = try fixture("rest-count", [record(0, 119.75, .rest), record(120, 240, .rest),
            record(241, 362, .rest), record(363, 3963, .rest)])
        expect(shortRests.day(base, now: date(4000), calendar: calendar, restThreshold: 120).completedRestCount == 2,
               "Completed count includes exact threshold, excludes shorter and away")
        expect(shortRests.day(base, now: date(4000), calendar: calendar, restThreshold: 121).completedRestCount == 1,
               "Past rest counts use the current configured threshold")
        expect(shortRests.day(base, now: date(4000), calendar: calendar, restThreshold: .infinity).completedRestCount == 0,
               "Invalid threshold does not qualify completions")
        let currentRest = ActivityHistory(storageURL: nil)
        currentRest.suspend(at: date(0))
        currentRest.resume(at: date(120))
        expect(currentRest.day(base, now: date(120), calendar: calendar, restThreshold: 120).completedRestCount == 0,
               "Resume alone leaves rest ongoing until activity or finish closes it")
        currentRest.sample(at: date(120), uptime: 120, idle: 0, restThreshold: 120)
        expect(currentRest.day(base, now: date(120), calendar: calendar, restThreshold: 120).completedRestCount == 1,
               "Rest counts after return closes the record")

        let overnight = try fixture("overnight", [ActivityRecord(start: midnight.addingTimeInterval(-120),
            end: midnight.addingTimeInterval(3480), kind: .rest, reason: "overnight")])
        let yesterday = overnight.day(base, now: midnight.addingTimeInterval(4000), calendar: calendar)
        let today = overnight.day(midnight, now: midnight.addingTimeInterval(4000), calendar: calendar)
        expect(yesterday.awaySeconds == 120 && today.awaySeconds == 3480 && yesterday.restSeconds == 0 && today.restSeconds == 0,
               "Whole raw span determines away on both sides of midnight")
        expect(yesterday.displayIntervals.first?.kind == .away && today.displayIntervals.first?.kind == .away,
               "Clipped rows do not reclassify away as short rest")
        expect(yesterday.detailGroups.first?.kind == .away && today.detailGroups.first?.kind == .away &&
               yesterday.detailGroups.first?.duration == 120 && today.detailGroups.first?.duration == 3480,
               "Detail groups retain whole-raw away classification after local-day clipping")
        let early = overnight.day(base, now: midnight.addingTimeInterval(-60), calendar: calendar)
        expect(early.awaySeconds == 60 && early.restSeconds == 0,
               "Clipping at now also retains the full archived record classification")
        let midnightRest = try fixture("midnight-rest", [ActivityRecord(start: midnight.addingTimeInterval(-60),
            end: midnight.addingTimeInterval(60), kind: .rest, reason: "short cross-day rest")])
        expect(midnightRest.day(base, now: midnight.addingTimeInterval(100), calendar: calendar).completedRestCount == 0,
               "Cross-midnight rest is not counted on its start day")
        expect(midnightRest.day(midnight, now: midnight.addingTimeInterval(100), calendar: calendar).completedRestCount == 1,
               "Cross-midnight rest counts once on its completion date using full duration")
        let exactMidnight = try fixture("midnight-completion", [ActivityRecord(start: midnight.addingTimeInterval(-120),
            end: midnight, kind: .rest, reason: "ends at midnight")])
        expect(exactMidnight.day(base, now: midnight, calendar: calendar).completedRestCount == 0 &&
               exactMidnight.day(midnight, now: midnight, calendar: calendar).completedRestCount == 1,
               "Completion dates use a half-open day boundary, including exact midnight in the new day")
        let overnightWork = try fixture("midnight-work", [ActivityRecord(start: midnight.addingTimeInterval(-600),
            end: midnight.addingTimeInterval(1200), kind: .work, reason: "cross-day work")])
        expect(overnightWork.day(base, now: midnight.addingTimeInterval(1300), calendar: calendar).longestWorkSeconds == 600 &&
               overnightWork.day(midnight, now: midnight.addingTimeInterval(1300), calendar: calendar).longestWorkSeconds == 1200,
               "Longest work is clipped per selected day")
        let timezoneRest = try fixture("timezone-completion", [ActivityRecord(start: midnight.addingTimeInterval(-60),
            end: midnight.addingTimeInterval(60), kind: .rest, reason: "local date")])
        var westernCalendar = calendar
        westernCalendar.timeZone = TimeZone(secondsFromGMT: -8 * 3600)!
        expect(timezoneRest.day(base, now: midnight.addingTimeInterval(100), calendar: westernCalendar).completedRestCount == 1,
               "Completion count follows the supplied calendar timezone")

        let fractions = ActivityHistory(storageURL: nil)
        fractions.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        fractions.sample(at: date(0.25), uptime: 0.25, idle: 0, restThreshold: 10)
        fractions.suspend(at: date(0.25))
        fractions.resume(at: date(0.5))
        fractions.sample(at: date(0.5), uptime: 0.5, idle: 0, restThreshold: 10)
        fractions.sample(at: date(0.75), uptime: 0.75, idle: 0, restThreshold: 10)
        fractions.finish(at: date(0.75))
        let fractionalDay = fractions.day(base, now: date(1), calendar: calendar)
        expect(fractionalDay.intervals.count == 3 && fractionalDay.displayIntervals.isEmpty,
               "Positive fractional-second intervals stay raw but hide zero-second display rows")
        expect(fractionalDay.workSeconds == 0.5 && fractionalDay.restSeconds == 0.25 && fractionalDay.longestWorkSeconds == 0.25,
               "Hidden fractions retain totals and never join work across a real rest")
        let separated = try fixture("separated-work", [record(0, 2, .work), record(2, 2.25, .rest),
            record(2.25, 5.25, .work), record(7, 11, .work), record(11, 12, .rest)])
        let separatedDay = separated.day(base, now: date(12), calendar: calendar)
        expect(separatedDay.intervals.count == 5 && separatedDay.displayIntervals.count == 4,
               "Exactly one second remains visible; only subsecond fragments are hidden")
        expect(separatedDay.workSeconds == 9 && separatedDay.restSeconds == 1.25 && separatedDay.longestWorkSeconds == 4,
               "Work intervals remain separate across both hidden rests and unrecorded gaps")
        let clippedFraction = separated.day(base, now: date(0.5), calendar: calendar)
        expect(clippedFraction.workSeconds == 0.5 && clippedFraction.intervals.count == 1 && clippedFraction.displayIntervals.isEmpty,
               "A positive day/now-clipped fractional fragment is hidden only at display layer")
        let fractionalAway = try fixture("fractional-away", [ActivityRecord(start: midnight.addingTimeInterval(-0.5),
            end: midnight.addingTimeInterval(3600), kind: .rest, reason: "fractional away fragment")])
        let fractionalAwayDay = fractionalAway.day(base, now: midnight.addingTimeInterval(4000), calendar: calendar)
        expect(fractionalAwayDay.awaySeconds == 0.5 && fractionalAwayDay.restSeconds == 0 && fractionalAwayDay.displayIntervals.isEmpty,
               "Hidden fractional away time keeps away totals and full-span classification")
        // Week ranges always use Monday, even in a calendar whose locale starts weeks on Sunday.
        calendar.firstWeekday = 1
        let monday = calendar.date(from: DateComponents(year: 2026, month: 11, day: 2))!
        let week = overnightWork.week(base, now: base, calendar: calendar)
        expect(week.range.start == monday && week.days.count == 7, "Monday–Sunday seven-day week")
        expect(week.days.map { $0.status } == [.past, .past, .past, .partial, .future, .future, .future],
               "Current day is partial; future days are explicit")
        expect(week.days[4].summary.workSeconds == 0 && week.days[4].summary.ongoingStart == nil,
               "Future dates cannot expose future archived time")
        let sundayWeek = history.week(monday.addingTimeInterval(6 * 86400), now: date(100), calendar: calendar)
        expect(sundayWeek.range == week.range, "Sunday belongs to preceding Monday")
        let yearBoundary = calendar.date(from: DateComponents(year: 2027, month: 1, day: 1))!
        expect(calendar.component(.year, from: history.week(yearBoundary, calendar: calendar).range.start) == 2026,
               "Week navigation crosses year boundary")
        let springWeek = dst.week(dstDate, now: dstRange.end, calendar: dstCalendar)
        let autumnWeek = fall.week(fallDate, now: fallRange.end, calendar: dstCalendar)
        expect(springWeek.range.duration == 167 * 3600 && springWeek.days.last?.range.duration == 23 * 3600,
               "Spring week has real 167 hours")
        expect(autumnWeek.range.duration == 169 * 3600 && autumnWeek.days.last?.range.duration == 25 * 3600,
               "Fall week has real 169 hours")
        let growingWeek = growing.week(base, now: date(3600), calendar: calendar)
        expect(growingWeek.awaySeconds == 3600 && growingWeek.days[3].summary.ongoingStart == base,
               "Ongoing source appears once in week totals")

        let csvReason = "  =HYPERLINK(\"恶意\",\"你好\")\n第二行,逗号"
        let exportable = try fixture("csv", [ActivityRecord(start: date(-10.25), end: date(20.5), kind: .rest, reason: csvReason),
            ActivityRecord(start: date(21), end: date(21.25), kind: .work, reason: "Unicode ☀️")])
        let exportRange = DateInterval(start: date(0), end: date(22))
        let csv = String(data: exportable.csv(in: exportRange, now: date(30), calendar: calendar), encoding: .utf8)!
        expect(csv.contains("2026-11-05T12:00:00.000000+00:00") && csv.contains("\"20.5\",\"rest\""),
               "CSV clips selected range and emits precise timezone timestamps and numeric seconds")
        expect(csv.contains("\"'  =HYPERLINK(\"\"恶意\"\",\"\"你好\"\")\n第二行,逗号\""),
               "CSV quotes embedded quotes/newlines/Unicode and protects formula after leading spaces")
        expect(csv.contains("\"0.25\",\"work\",\"Unicode ☀️\",\"false\""), "CSV includes hidden fractional spans")
        for prefix in ["=", "+", "-", "@", "\t", "\r", "\n", "  @"] {
            expect(ActivityHistory.csvField(prefix + "payload").hasPrefix("\"'"), "Protect Excel prefix: \(prefix)")
        }
        expect(ActivityHistory.csvField("a,b\"c\nd") == "\"a,b\"\"c\nd\"", "Ordinary multiline fields preserve their text")
        let bom = exportable.csv(in: exportRange, now: date(30), calendar: calendar, includeBOM: true)
        expect(Array(bom.prefix(3)) == [0xEF, 0xBB, 0xBF] && !Array(Data(csv.utf8).prefix(3)).elementsEqual([0xEF, 0xBB, 0xBF]),
               "UTF-8 BOM is opt-in")
        let currentCSV = String(data: growing.csv(in: calendar.dateInterval(of: .day, for: base)!, now: date(3600), calendar: calendar), encoding: .utf8)!
        expect(currentCSV.contains("\"away\"") && currentCSV.contains("\"true\""), "CSV retains whole-source category and ongoing flag")
        let fallCSV = String(data: fall.csv(in: fallRange, now: fallRange.end, calendar: dstCalendar), encoding: .utf8)!
        expect(fallCSV.contains("-07:00") && fallCSV.contains("-08:00") && fallCSV.contains("\"90000\""),
               "CSV includes distinct offsets across the fall transition and actual seconds")
        expect(exportable.csv(in: DateInterval(start: date(50), end: date(60)), now: date(30)).split(separator: 10).count == 1,
               "Future export is header-only")

        let split = try fixture("split-delete", [record(0, 100, .work), record(110, 150, .rest)])
        let splitURL = directory.appendingPathComponent("split-delete.json")
        let originalSplit = try Data(contentsOf: splitURL)
        let preview = try split.previewDeletion(in: DateInterval(start: date(30), end: date(60)), at: date(200))
        expect(preview.affectedIntervalCount == 1 && preview.removedSeconds == 30 && preview.retainedFragmentCount == 2,
               "Preview counts a split source once, overlapping seconds only, and both surviving fragments")
        expect(preview.affectedRange == DateInterval(start: date(30), end: date(60)), "Preview reports actual removed envelope")
        expect(tryData(splitURL) == originalSplit && split.day(base, now: date(200), calendar: calendar).workSeconds == 100,
               "A preview alone never changes memory or disk; cancellation can just return")
        try split.delete(preview)
        let splitDay = split.day(base, now: date(200), calendar: calendar)
        expect(splitDay.intervals.map { $0.start } == [date(0), date(60), date(110)] && splitDay.workSeconds == 70,
               "Selected-range deletion preserves both outside fragments and separate gaps")
        let splitReloaded = ActivityHistory(storageURL: splitURL)
        expect(splitReloaded.day(base, now: date(200), calendar: calendar).intervals == splitDay.intervals,
               "Committed split snapshot survives restart")
        do { try split.delete(preview); fatalError("Reused deletion preview should fail") }
        catch ActivityHistoryError.stalePreview { }
        let gapPreview = try split.previewDeletion(in: DateInterval(start: date(90), end: date(120)), at: date(200))
        expect(gapPreview.affectedIntervalCount == 2 && gapPreview.removedSeconds == 20,
               "Preview does not count an unrecorded gap as time")
        let allPreview = try split.previewDeletion(at: date(200))
        try split.delete(allPreview)
        expect(split.day(base, now: date(200), calendar: calendar).intervals.isEmpty,
               "Clear-all removes every historical span without a hidden backup")

        let activeDelete = ActivityHistory(storageURL: nil)
        activeDelete.suspend(at: date(0))
        activeDelete.sample(at: date(100), uptime: 100, idle: 100, restThreshold: 10)
        let activePreview = try activeDelete.previewDeletion(in: DateInterval(start: date(30), end: date(60)), at: date(100))
        try activeDelete.delete(activePreview)
        activeDelete.sample(at: date(105), uptime: 105, idle: 105, restThreshold: 10)
        let activeDay = activeDelete.day(base, now: date(105), calendar: calendar)
        expect(activeDay.intervals.map { $0.start } == [date(0), date(60)] && activeDay.restSeconds == 75 && activeDay.ongoingStart == date(60),
               "Deletion while current spans selected range preserves prefix and continuing suffix")
        let clearActive = try activeDelete.previewDeletion(at: date(105))
        activeDelete.sample(at: date(110), uptime: 110, idle: 110, restThreshold: 10)
        try activeDelete.delete(clearActive)
        activeDelete.resume(at: date(110))
        activeDelete.sample(at: date(115), uptime: 115, idle: 115, restThreshold: 10)
        expect(activeDelete.day(base, now: date(115), calendar: calendar).intervals.first?.start == date(105),
               "Recording during confirmation survives, and old idle backdating cannot resurrect cleared time")
        activeDelete.finish(at: date(115))
        expect(activeDelete.day(base, now: date(115), calendar: calendar).restSeconds == 10,
               "Finish cannot restore deleted current spans")

        _ = try fixture("failure", [record(0, 100, .work)])
        let failureURL = directory.appendingPathComponent("failure.json")
        let failureBefore = try Data(contentsOf: failureURL)
        let memoryPrefs = MemoryHistoryPreferences()
        let failing = ActivityHistory(storageURL: failureURL, preferences: memoryPrefs,
            archiveWriter: { _, _ in throw CocoaError(.fileWriteNoPermission) })
        let failedPreview = try failing.previewDeletion(in: DateInterval(start: date(20), end: date(80)), at: date(100))
        do { try failing.delete(failedPreview); fatalError("Injected persistence failure should throw") } catch { }
        expect(failing.day(base, now: date(100), calendar: calendar).workSeconds == 100 && tryData(failureURL) == failureBefore && failing.persistenceError != nil,
               "Failed destructive write preserves original memory/disk and reports failure")
        let failedRetention = try failing.previewRetention(days: 30, at: date(40 * 86400), calendar: calendar)
        do { try failing.applyRetention(failedRetention); fatalError("Failed retention write should throw") } catch { }
        expect(failing.retentionDays == 0 && memoryPrefs.historyRetentionDays == 0 && tryData(failureURL) == failureBefore,
               "Retention setting remains old when cleanup save fails")

        _ = try fixture("live-failure", [])
        let liveFailureURL = directory.appendingPathComponent("live-failure.json")
        var rejectWrite = false
        let liveFailure = ActivityHistory(storageURL: liveFailureURL, archiveWriter: { data, url in
            if rejectWrite { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url, options: .atomic)
        })
        liveFailure.suspend(at: date(0))
        liveFailure.sample(at: date(100), uptime: 100, idle: 100, restThreshold: 10)
        let liveBefore = liveFailure.csv(in: calendar.dateInterval(of: .day, for: base)!, now: date(100), calendar: calendar)
        let liveDiskBefore = try Data(contentsOf: liveFailureURL)
        rejectWrite = true
        let liveFailedPreview = try liveFailure.previewDeletion(at: date(100))
        do { try liveFailure.delete(liveFailedPreview); fatalError("Current deletion must fail with writer") } catch { }
        expect(liveFailure.csv(in: calendar.dateInterval(of: .day, for: base)!, now: date(100), calendar: calendar) == liveBefore &&
               tryData(liveFailureURL) == liveDiskBefore, "Failed live deletion retains current source, boundary and disk")
        liveFailure.sample(at: date(105), uptime: 105, idle: 105, restThreshold: 10)
        expect(liveFailure.day(base, now: date(105), calendar: calendar).ongoingStart == base,
               "Failed live deletion cannot advance the recording floor")
        let stale = ActivityHistory(storageURL: nil)
        stale.sample(at: date(0), uptime: 0, idle: 0, restThreshold: 10)
        stale.sample(at: date(5), uptime: 5, idle: 0, restThreshold: 10)
        let stalePreview = try stale.previewDeletion(at: date(5))
        stale.sample(at: date(10), uptime: 10, idle: 10, restThreshold: 10)
        do { try stale.delete(stalePreview); fatalError("Backdated reclassification must invalidate preview") }
        catch ActivityHistoryError.stalePreview { }
        expect(stale.day(base, now: date(10), calendar: calendar).restSeconds == 10,
               "A stale preview leaves newly classified history untouched")

        let retentionSource = try fixture("retention", [record(-100, 100, .work), record(110, 120, .rest)])
        let retentionURL = directory.appendingPathComponent("retention.json")
        let retentionBefore = try Data(contentsOf: retentionURL)
        let prefs = MemoryHistoryPreferences()
        let retained = ActivityHistory(storageURL: retentionURL, preferences: prefs)
        expect(retained.retentionDays == 0, "Retention defaults to permanently disabled")
        try retained.prune(at: date(1000 * 86400), calendar: calendar)
        expect(tryData(retentionURL) == retentionBefore, "Default disabled retention never removes old records")
        let retentionNow = calendar.date(byAdding: .day, value: 30, to: base)!
        let retentionPreview = try retained.previewRetention(days: 30, at: retentionNow, calendar: calendar)
        expect(retentionPreview.cutoff == base && retentionPreview.deletion?.removedSeconds == 100,
               "Retention preview clips crossing source to the exact local-day cutoff")
        expect(retained.retentionDays == 0 && prefs.historyRetentionDays == 0 && tryData(retentionURL) == retentionBefore,
               "Canceling finite-retention preview preserves previous choice and all data")
        try retained.applyRetention(retentionPreview)
        expect(retained.retentionDays == 30 && prefs.historyRetentionDays == 30 &&
               retained.day(base, now: date(200), calendar: calendar).intervals.first?.start == base,
               "Explicit retention confirmation clips crossing record and persists choice")
        let beforeReload = try Data(contentsOf: retentionURL)
        var startupWrites = 0
        let reloadedRetention = ActivityHistory(storageURL: retentionURL, preferences: prefs, archiveWriter: { data, url in
            startupWrites += 1
            try data.write(to: url, options: .atomic)
        })
        expect(reloadedRetention.retentionDays == 30 && reloadedRetention.persistenceError == nil,
               "Startup loads injected choice and original v1 schema")
        expect(startupWrites == 0 && beforeReload == tryData(retentionURL), "Startup itself does not prune or rewrite")
        try reloadedRetention.prune(at: calendar.date(byAdding: .day, value: 30, to: date(110))!, calendar: calendar)
        expect(reloadedRetention.day(base, now: date(200), calendar: calendar).workSeconds == 0 &&
               reloadedRetention.day(base, now: date(200), calendar: calendar).restSeconds == 10,
               "Subsequent pruning honors the earlier choice and exact crossing boundary")
        _ = retentionSource
        let disabled = try reloadedRetention.previewRetention(days: 0)
        try reloadedRetention.applyRetention(disabled)
        expect(prefs.historyRetentionDays == 0, "Permanent retention disables future pruning")
        do { _ = try retained.previewRetention(days: 7); fatalError("Unsupported finite choices must fail") }
        catch ActivityHistoryError.invalidRetention { }
        let explicitChoice = ActivityHistory(storageURL: nil, retentionDays: 90, preferences: MemoryHistoryPreferences(365))
        expect(explicitChoice.retentionDays == 90, "Explicit init choice overrides injected preferences")
        let springRetentionNow = dstCalendar.date(byAdding: .day, value: 30, to: dstDate)!
        let localCutoff = try explicitChoice.previewRetention(days: 30, at: springRetentionNow, calendar: dstCalendar)
        expect(localCutoff.cutoff == dstDate, "Retention cutoff follows calendar days across DST")
        let livePrune = ActivityHistory(storageURL: nil, retentionDays: 30)
        livePrune.suspend(at: date(-100))
        livePrune.sample(at: retentionNow, uptime: 1, idle: 1, restThreshold: 10)
        expect(livePrune.day(base, now: retentionNow, calendar: calendar).intervals.first?.start == base,
               "Automatic pruning clips current recording rather than dropping it")
        let nextLocalDay = calendar.date(byAdding: .day, value: 1, to: base)!
        expect(livePrune.day(nextLocalDay, now: retentionNow, calendar: calendar).awaySeconds == 86400,
               "Pruning does not add unobserved gaps to a continuous suspended interval")
        do { _ = try corrupt.previewDeletion(at: date(5)); fatalError("Corrupt original must block deletion") }
        catch ActivityHistoryError.protectedArchive { }
        let corruptRetention = ActivityHistory(storageURL: corruptFile, retentionDays: 30)
        do { try corruptRetention.prune(at: retentionNow, calendar: calendar); fatalError("Corrupt original must block pruning") }
        catch ActivityHistoryError.protectedArchive { }
        expect(tryData(corruptFile) == corruptData, "Corrupt file remains byte-for-byte intact after attempted cleanup")
        print("PASS: existing history regressions; detail grouping/update gaps/boundaries/barriers/fractions/reasons/ongoing/calendar with raw statistics/CSV/archives unchanged; Monday weeks/DST/partial/future; CSV clipping/Unicode/quotes/newlines/formula protection/BOM/timezones; frozen previews/splits/clear-all/live continuation; transactional save rollback; opt-in retention/preferences/calendar cutoff/v1/corrupt protection")
    }
}
