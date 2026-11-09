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

import AppKit

@main struct HistoryWindowSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // Synthetic data only in an in-memory test instance; never added to user history.
        let history = ActivityHistory(storageURL: nil)
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        let start = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: yesterday)!
        func date(_ second: Double) -> Date { start.addingTimeInterval(second) }
        func work(_ from: Int, _ through: Int) {
            for second in stride(from: from, through: through, by: 5) {
                history.sample(at: date(Double(second)), uptime: Double(second), idle: 0, restThreshold: 300)
            }
        }
        work(0, 2100) // Work longer than the configured 30-minute interval.
        history.suspend(at: date(2100))
        history.resume(at: date(2700)) // A completed 10-minute rest.
        work(2700, 3900)
        history.suspend(at: date(3900))
        history.resume(at: date(11100)) // A two-hour absence, wholly away.
        work(11100, 11700)
        history.suspend(at: date(11700))
        history.resume(at: date(11700.25))
        history.sample(at: date(11700.25), uptime: 11700.25, idle: 0, restThreshold: 300)
        history.sample(at: date(11700.5), uptime: 11700.5, idle: 0, restThreshold: 300)
        history.finish(at: date(11700.5))
        let day = history.day(start, now: Date(), calendar: calendar, restThreshold: 300)
        precondition(day.intervals.count == 7 && day.displayIntervals.count == 5, "Fractional rows should be hidden")
        precondition(day.completedRestCount == 1 && day.longestWorkSeconds == 2100, "Fixture summary")
        var canceledConfirmations = 0
        let populated = HistoryWindow(history: history, workInterval: { 1800 }, restThreshold: { 300 },
            confirmMutation: { _, _ in canceledConfirmations += 1; return false }, autosaveName: nil)
        let empty = HistoryWindow(history: ActivityHistory(storageURL: nil), restThreshold: { 300 }, autosaveName: nil)
        let mergeFixture = fragmentedHistory(start: start)
        let merged = HistoryWindow(history: mergeFixture, workInterval: { 1800 }, restThreshold: { 300 }, autosaveName: nil)
        DispatchQueue.main.async {
            populated.show()
            guard let content = populated.window?.contentView,
                  let picker = descendants(of: content).compactMap({ $0 as? NSDatePicker }).first,
                  let action = picker.action else { fatalError("Missing date picker") }
            picker.dateValue = start
            app.sendAction(action, to: picker.target, from: picker)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                verifyPopulated(populated)
                capture(populated, to: "build/history-preview.png")
                verifyInteractions(populated, history: history, start: start)
                precondition(canceledConfirmations == 3, "Day deletion, clear-all and finite retention must all confirm")
                guard let window = populated.window,
                      let shortcut = NSEvent.keyEvent(with: .keyDown, location: .zero,
                          modifierFlags: .command, timestamp: ProcessInfo.processInfo.systemUptime,
                          windowNumber: window.windowNumber, context: nil, characters: "w",
                          charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13) else {
                    fatalError("Cannot create Command-W event")
                }
                app.sendEvent(shortcut)
                guard !window.isVisible else { fatalError("Command-W did not close history") }
                populated.show()
                guard window.isVisible else { fatalError("History cannot reopen after Command-W") }
                populated.close()
                merged.show()
                guard let mergedContent = merged.window?.contentView,
                      let mergedPicker = descendants(of: mergedContent).compactMap({ $0 as? NSDatePicker }).first else {
                    fatalError("Missing merged history date picker")
                }
                mergedPicker.dateValue = start
                app.sendAction(mergedPicker.action!, to: mergedPicker.target, from: mergedPicker)
                mergedContent.layoutSubtreeIfNeeded()
                verifyMerged(merged, history: mergeFixture, start: start)
                capture(merged, to: "build/history-merged-preview.png")
                merged.close()
                verifyLiveMerged()
                empty.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    capture(empty, to: "build/history-empty-preview.png")
                    empty.close()
                    print("PASS: daily totals/palette/summary/descending rows/duration bars; timeline selects and scrolls row; seven-day weekly view/day drill-down; canceled delete/clear-all/retention leave data/settings unchanged; Command-W dispatch/reopening")
                    app.terminate(nil)
                }
            }
        }
        app.run()
    }

    static func fragmentedHistory(start: Date) -> ActivityHistory {
        struct Fixture: Encodable { let version = 1; let records: [ActivityRecord] }
        let spans: [(Double, Double, ActivityKind)] = [
            (0, 1982, .rest), (2079, 4222, .rest),
            (4222, 6324, .work), (6353, 6445, .work),
            (6476, 7025, .work), (7056, 7416, .work)
        ]
        let records = spans.map { from, to, kind in
            ActivityRecord(start: start.addingTimeInterval(from), end: start.addingTimeInterval(to), kind: kind,
                           reason: kind == .work ? "键鼠活动（含短暂停顿）" : "无键鼠操作")
        }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let url = URL(fileURLWithPath: "build/history-merged-smoke.json")
        do { try encoder.encode(Fixture(records: records)).write(to: url, options: .atomic) }
        catch { fatalError("Cannot write isolated merge fixture: \(error)") }
        return ActivityHistory(storageURL: url, retentionDays: 0)
    }

    static func verifyMerged(_ controller: HistoryWindow, history: ActivityHistory, start: Date) {
        guard let content = controller.window?.contentView,
              let table = descendants(of: content).compactMap({ $0 as? NSTableView }).first,
              let timeline = descendants(of: content).first(where: { $0.identifier?.rawValue == "historyTimeline" }) else {
            fatalError("Missing merged history controls")
        }
        precondition(controller.numberOfRows(in: table) == 2, "Six source fragments should display as two same-kind groups")
        func cell(_ column: String, _ row: Int) -> NSTableCellView {
            let item = table.tableColumns.first { $0.identifier.rawValue == column }
            return controller.tableView(table, viewFor: item, row: row) as! NSTableCellView
        }
        precondition(cell("duration", 0).textField?.stringValue == "51分（4段）", "Work duration sums observations, excluding91 seconds of gaps")
        precondition(cell("duration", 1).textField?.stringValue == "1小时 8分（2段）" && cell("kind", 1).textField?.stringValue == "休息",
                     "Grouped short rests exceeding an hour keep their raw rest classification")
        precondition(cell("duration", 0).toolTip?.contains("91.000 秒未记录") == true &&
                     cell("duration", 1).toolTip?.contains("97.000 秒未记录") == true,
                     "Gaps and original fragments must stay inspectable")
        let day = history.day(start, now: Date(), restThreshold: 300)
        precondition(day.intervals.count == 6 && day.longestWorkSeconds == 2102 && day.completedRestCount == 2,
                     "Grouping cannot change raw records, longest continuous work or completed rests")
        let range = Calendar.current.dateInterval(of: .day, for: start)!
        let before = history.csv(in: range)
        func click(_ offset: Double) {
            let fraction = start.addingTimeInterval(offset).timeIntervalSince(range.start) / range.duration
            let point = timeline.convert(NSPoint(x: timeline.bounds.width * fraction, y: 40), to: nil)
            let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window!.windowNumber,
                context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            timeline.mouseDown(with: event)
        }
        for offset in [100.0, 3000.0] { click(offset); precondition(table.selectedRow == 1, "Either rest member locates the same merged row") }
        for offset in [4500.0, 7200.0] { click(offset); precondition(table.selectedRow == 0, "First and last work members locate the merged row") }
        click(2030) // Between the two rest members; must not select that group's envelope.
        precondition(table.selectedRow == 0, "Unrecorded timeline gaps remain unselectable")
        controller.show()
        precondition(table.selectedRow == 0, "Selection survives refresh using the member start rather than only group start")
        precondition(history.csv(in: range) == before, "Browsing merged rows cannot rewrite raw CSV")
        verifyGeometry(controller, weekly: false)
        // Keep preview colors neutral: native selected-row background effects
        // are compositor-backed and do not survive the view-only snapshot.
        table.deselectAll(nil)
        controller.window?.displayIfNeeded()
    }

    static func verifyLiveMerged() {
        let now = Date()
        guard now.timeIntervalSince(Calendar.current.startOfDay(for: now)) > 120 else { return }
        struct Fixture: Encodable { let version = 1; let records: [ActivityRecord] }
        let record = ActivityRecord(start: now.addingTimeInterval(-70), end: now.addingTimeInterval(-10),
                                    kind: .work, reason: "键鼠活动（含短暂停顿）")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let url = URL(fileURLWithPath: "build/history-merged-live.json")
        do { try encoder.encode(Fixture(records: [record])).write(to: url, options: .atomic) }
        catch { fatalError("Cannot write isolated ongoing fixture: \(error)") }
        let history = ActivityHistory(storageURL: url, retentionDays: 0)
        history.sample(at: now.addingTimeInterval(-0.5), uptime: 1, idle: 0, restThreshold: 300)
        history.sample(at: now, uptime: 1.5, idle: 0, restThreshold: 300)
        let day = history.day(now, now: now, restThreshold: 300)
        precondition(day.displayIntervals.count == 1 && day.detailGroups.first?.intervals.count == 2,
                     "The ongoing fractional member is hidden alone but belongs to the visible group")
        let controller = HistoryWindow(history: history, restThreshold: { 300 }, autosaveName: nil)
        controller.show()
        guard let content = controller.window?.contentView,
              let table = descendants(of: content).compactMap({ $0 as? NSTableView }).first else { fatalError("Missing ongoing table") }
        let kind = controller.tableView(table, viewFor: table.tableColumns.first { $0.identifier.rawValue == "kind" }, row: 0) as? NSTableCellView
        let end = controller.tableView(table, viewFor: table.tableColumns.first { $0.identifier.rawValue == "end" }, row: 0) as? NSTableCellView
        precondition(controller.numberOfRows(in: table) == 1 && kind?.textField?.stringValue == "工作 · 进行中" &&
                     end?.textField?.stringValue == "至今", "Ongoing state must follow any group member, including a hidden fractional one")
        controller.close()
    }

    static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    static func verifyPopulated(_ controller: HistoryWindow) {
        guard let content = controller.window?.contentView,
              let table = descendants(of: content).compactMap({ $0 as? NSTableView }).first else {
            fatalError("Missing history table")
        }
        precondition(controller.numberOfRows(in: table) == 5, "Only visible intervals should be listed")
        func cell(_ column: String, _ row: Int) -> NSTableCellView {
            let tableColumn = table.tableColumns.first { $0.identifier.rawValue == column }
            guard let cell = controller.tableView(table, viewFor: tableColumn, row: row) as? NSTableCellView else {
                fatalError("Missing \(column) cell")
            }
            return cell
        }
        precondition((0..<5).map { cell("kind", $0).textField?.stringValue ?? "" } == ["工作", "离开", "工作", "休息", "工作"],
                     "Rows should descend by start with a distinct away category")
        precondition((0..<5).allSatisfy { cell("duration", $0).textField?.stringValue != "0秒" },
                     "Positive subsecond fragments must not produce zero-second rows")
        precondition(cell("duration", 4).toolTip?.contains("超过当前工作设定") == true &&
                     cell("duration", 3).toolTip?.contains("超过当前休息设定") == true,
                     "Work/rest bars retain configured thresholds")
        precondition(cell("duration", 1).toolTip?.contains("不计入休息占比或完成次数") == true,
                     "Away duration stays neutral")
        let labels = descendants(of: content).compactMap { ($0 as? NSTextField)?.stringValue }
        precondition(labels.contains("已完成休息 1 次  ·  最长连续工作 35分"), "Compact secondary summary")
        precondition(labels.contains("离开") && labels.contains("2小时 0分"), "Away total card")
        precondition(labels.contains { $0.contains("工作 87%  /  休息 13%") && $0.contains("不含离开及未记录时间") },
                     "Comparison denominator excludes away")
    }

    static func verifyInteractions(_ controller: HistoryWindow, history: ActivityHistory, start: Date) {
        guard let content = controller.window?.contentView,
              let table = descendants(of: content).compactMap({ $0 as? NSTableView }).first,
              let timeline = descendants(of: content).first(where: { $0.identifier?.rawValue == "historyTimeline" }),
              let mode = descendants(of: content).compactMap({ $0 as? NSSegmentedControl }).first,
              let management = descendants(of: content).compactMap({ $0 as? NSPopUpButton }).first else {
            fatalError("Missing interactive history controls")
        }
        content.layoutSubtreeIfNeeded()
        let dayRange = Calendar.current.dateInterval(of: .day, for: start)!
        let fraction = start.addingTimeInterval(1000).timeIntervalSince(dayRange.start) / dayRange.duration
        let point = timeline.convert(NSPoint(x: timeline.bounds.width * fraction, y: 40), to: nil)
        guard let click = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: controller.window!.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: 1) else { fatalError("Cannot create timeline click") }
        timeline.mouseDown(with: click)
        precondition(table.selectedRow == 4 && table.visibleRect.intersects(table.rect(ofRow: 4)),
                     "Timeline selects matching newest-first row and scrolls it into view")
        let before = history.csv(in: dayRange)
        let actions = ["删除所选日…", "清空全部历史…", "保留 30 天…"]
        for title in actions {
            guard let item = management.itemArray.first(where: { $0.title == title }), let action = item.action else {
                fatalError("Missing record-management action: \(title)")
            }
            NSApp.sendAction(action, to: item.target, from: item)
        }
        precondition(history.csv(in: dayRange) == before && history.retentionDays == 0,
                     "Returning false from the real confirmation path must not mutate data or retention")
        mode.selectedSegment = 1
        NSApp.sendAction(mode.action!, to: mode.target, from: mode)
        content.layoutSubtreeIfNeeded()
        precondition(table.isHiddenOrHasHiddenAncestor, "Week mode exposes daily details through day buttons")
        let weekButtons = descendants(of: content).compactMap { $0 as? NSButton }.filter { $0.title.hasPrefix("周") }
        precondition(weekButtons.count == 7, "Exactly seven Monday–Sunday native day buttons")
        verifyGeometry(controller, weekly: true)
        let originalSize = content.bounds.size
        for size in [NSSize(width: 820, height: 770), NSSize(width: 980, height: 940)] {
            controller.window?.setContentSize(size)
            content.layoutSubtreeIfNeeded()
            verifyGeometry(controller, weekly: true)
        }
        controller.window?.setContentSize(originalSize)
        content.layoutSubtreeIfNeeded()
        capture(controller, to: "build/history-week-preview.png")
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        guard let selectedDay = weekButtons.first(where: { $0.title.hasSuffix(" " + formatter.string(from: start)) }) else {
            fatalError("Missing fixture day in week")
        }
        selectedDay.performClick(nil)
        content.layoutSubtreeIfNeeded()
        precondition(mode.selectedSegment == 0 && !table.isHiddenOrHasHiddenAncestor && controller.numberOfRows(in: table) == 5,
                     "Clicking a weekly day returns to the accessible daily table")
        for size in [NSSize(width: 820, height: 770), NSSize(width: 980, height: 940)] {
            controller.window?.setContentSize(size)
            content.layoutSubtreeIfNeeded()
            verifyGeometry(controller, weekly: false)
        }
        controller.window?.setContentSize(originalSize)
        content.layoutSubtreeIfNeeded()
    }

    static func verifyGeometry(_ controller: HistoryWindow, weekly: Bool) {
        guard let content = controller.window?.contentView,
              let summary = descendants(of: content).first(where: { $0.identifier?.rawValue == "historySummary" }),
              let compatibility = descendants(of: content).compactMap({ $0 as? NSButton }).first(where: { $0.title == "兼容 Excel" }),
              let management = descendants(of: content).compactMap({ $0 as? NSPopUpButton }).first else {
            fatalError("Missing compact layout controls")
        }
        let summaryRect = summary.convert(summary.bounds, to: content)
        precondition(summaryRect.height < 50, "Summary must stay at its intrinsic two-line height")
        precondition(compatibility.toolTip == "在 UTF-8 CSV 开头添加 BOM，帮助 Excel 识别中文", "Excel implementation detail belongs in tooltip")
        for view in [compatibility as NSView, management] {
            let rect = view.convert(view.bounds, to: content)
            precondition(content.bounds.contains(rect), "Record actions must stay on screen at minimum and expanded sizes")
        }
        if weekly {
            guard let chart = descendants(of: content).first(where: { $0.identifier?.rawValue == "historyWeek" }),
                  let monday = descendants(of: chart).compactMap({ $0 as? NSButton }).first(where: { $0.title.hasPrefix("周一") }) else {
                fatalError("Missing weekly geometry")
            }
            let chartRect = chart.convert(chart.bounds, to: content)
            let mondayRect = monday.convert(monday.bounds, to: content)
            let gap = summaryRect.minY - chartRect.maxY
            precondition(chartRect.height >= 252 && gap >= 0 && gap <= 16,
                         "Weekly chart must follow summary with normal spacing and absorb extra height")
            precondition(summaryRect.minY - mondayRect.maxY < 70, "First weekday cannot be separated by a large blank region")
        } else {
            guard let table = descendants(of: content).compactMap({ $0 as? NSTableView }).first,
                  let scroll = table.enclosingScrollView else { fatalError("Missing daily table geometry") }
            precondition(scroll.bounds.height >= 130, "Daily table retains flexible usable height")
        }
    }

    static func capture(_ controller: NSWindowController, to path: String) {
        guard let view = controller.window?.contentView else { fatalError("Missing history window") }
        view.layoutSubtreeIfNeeded()
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render") }
        view.cacheDisplay(in: view.bounds, to: image)
        let composed = NSImage(size: view.bounds.size)
        composed.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        view.bounds.fill()
        image.draw(in: view.bounds)
        composed.unlockFocus()
        guard let tiff = composed.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Missing rendered image") }
        do { try data.write(to: URL(fileURLWithPath: path)) }
        catch { fatalError("Cannot save screenshot: \(error)") }
    }
}
