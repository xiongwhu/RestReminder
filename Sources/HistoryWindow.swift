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
import UniformTypeIdentifiers

private extension ActivityDisplayKind {
    var title: String {
        switch self {
        case .work: return "工作"
        case .rest: return "休息"
        case .away: return "离开"
        }
    }

    var color: NSColor {
        switch self {
        case .work: return .systemOrange
        case .rest: return .systemGreen
        case .away: return NSColor(calibratedRed: 0.55, green: 0.66, blue: 0.59, alpha: 1)
        }
    }

    var textColor: NSColor {
        guard self == .away else { return color }
        return NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua {
                return NSColor(calibratedRed: 0.67, green: 0.78, blue: 0.70, alpha: 1)
            }
            return NSColor(calibratedRed: 0.30, green: 0.41, blue: 0.34, alpha: 1)
        }
    }
}

/// Menu-bar apps have no standard main menu to supply the usual close shortcut.
private final class HistoryRecordWindow: NSWindow {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A local history browser. Destructive actions always pass through a frozen preview and confirmation.
final class HistoryWindow: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private let history: ActivityHistory
    private let restThreshold: () -> TimeInterval
    private let workInterval: () -> TimeInterval
    private var workDurationScale: TimeInterval = 1
    private var restDurationScale: TimeInterval = 1
    private var selectedDate = Date()
    private var followsToday = true
    private var refreshTimer: Timer?
    private var records: [ActivityDetailGroup] = []
    private var ongoingStart: Date?
    private var showsWeek = false
    private var selectedIntervalStart: Date?
    private var operationError: String?
    private let confirmMutation: ((String, String) -> Bool)?
    private let mode = NSSegmentedControl(labels: ["日", "周"], trackingMode: .selectOne, target: nil, action: nil)
    private let previousButton = NSButton(title: "← 前一天", target: nil, action: nil)
    private let weekView = HistoryWeekView()
    private let timelineHeading = NSStackView()
    private let listTitle = NSTextField(labelWithString: "时段明细")
    private let listContainer = NSView()
    private let management = NSPopUpButton(frame: .zero, pullsDown: true)
    private let excelBOM = NSButton(checkboxWithTitle: "兼容 Excel", target: nil, action: nil)

    private let datePicker = NSDatePicker()
    private let nextButton = NSButton(title: "下一天 →", target: nil, action: nil)
    private let dateTitle = NSTextField(labelWithString: "")
    private let workTotal = NSTextField(labelWithString: "")
    private let restTotal = NSTextField(labelWithString: "")
    private let awayTotal = NSTextField(labelWithString: "")
    private let comparison = NSTextField(labelWithString: "")
    private let summaryDetails = NSTextField(labelWithString: "")
    private let timeline = HistoryTimelineView()
    private let table = NSTableView()
    private let emptyState = NSTextField(wrappingLabelWithString: "这一天还没有记录\n应用运行后，工作与休息时段会显示在这里。")
    private let footnote = NSTextField(wrappingLabelWithString: "")
    private let errorLabel = NSTextField(wrappingLabelWithString: "")
    private let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    init(history: ActivityHistory, workInterval: @escaping () -> TimeInterval = { 1800 },
         restThreshold: @escaping () -> TimeInterval,
         confirmMutation: ((String, String) -> Bool)? = nil,
         autosaveName: String? = "ActivityHistoryWindow") {
        self.history = history
        self.workInterval = workInterval
        self.restThreshold = restThreshold
        self.confirmMutation = confirmMutation
        let window = HistoryRecordWindow(contentRect: NSRect(x: 0, y: 0, width: 880, height: 790),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.contentView = HistoryBackgroundView(frame: NSRect(x: 0, y: 0, width: 880, height: 790))
        window.title = "工作与休息记录"
        window.contentMinSize = NSSize(width: 820, height: 770)
        window.isReleasedWhenClosed = false
        if let autosaveName { window.setFrameAutosaveName(autosaveName) }
        super.init(window: window)
        window.delegate = self
        buildContent()
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    deinit { refreshTimer?.invalidate() }

    func show() {
        refresh()
        showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        startRefreshing()
    }

    func windowWillClose(_ notification: Notification) { stopRefreshing() }
    func windowDidMiniaturize(_ notification: Notification) { stopRefreshing() }
    func windowDidDeminiaturize(_ notification: Notification) {
        refresh()
        startRefreshing()
    }

    private func startRefreshing() {
        stopRefreshing()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.window?.isVisible == true, self.window?.isMiniaturized == false else {
                self.stopRefreshing()
                return
            }
            self.refresh()
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopRefreshing() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    private func buildContent() {
        guard let content = window?.contentView else { return }
        let root = NSStackView()
        root.orientation = .vertical
        root.distribution = .fill
        root.alignment = .leading
        root.spacing = 10
        root.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            root.topAnchor.constraint(equalTo: content.topAnchor, constant: 22),
            root.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -20)
        ])

        dateTitle.font = .systemFont(ofSize: 24, weight: .semibold)
        root.addArrangedSubview(dateTitle)

        previousButton.target = self
        previousButton.action = #selector(previousDay)
        mode.selectedSegment = 0
        mode.target = self
        mode.action = #selector(modeChanged)
        mode.setAccessibilityLabel("日视图或周视图")
        nextButton.target = self
        nextButton.action = #selector(nextDay)
        let today = NSButton(title: "今天", target: self, action: #selector(goToToday))
        datePicker.datePickerStyle = .textFieldAndStepper
        datePicker.datePickerElements = [.yearMonthDay]
        datePicker.target = self
        datePicker.action = #selector(dateChanged)
        datePicker.setAccessibilityLabel("查看日期")
        let navigation = NSStackView(views: [mode, previousButton, datePicker, nextButton, today])
        navigation.spacing = 10
        root.addArrangedSubview(navigation)

        let totals = NSStackView(views: [totalCard(title: "工作", value: workTotal, color: .systemOrange),
                                        totalCard(title: "休息", value: restTotal, color: .systemGreen),
                                        totalCard(title: "离开", value: awayTotal, color: ActivityDisplayKind.away.textColor)])
        totals.distribution = .fillEqually
        totals.spacing = 16
        root.addArrangedSubview(totals)
        totals.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        comparison.font = .systemFont(ofSize: 12)
        comparison.textColor = .secondaryLabelColor
        summaryDetails.font = .systemFont(ofSize: 12)
        summaryDetails.textColor = .secondaryLabelColor
        let summary = NSStackView(views: [comparison, summaryDetails])
        summary.orientation = .vertical
        summary.alignment = .leading
        summary.spacing = 4
        summary.identifier = NSUserInterfaceItemIdentifier("historySummary")
        summary.setHuggingPriority(.required, for: .vertical)
        root.addArrangedSubview(summary)

        let timelineTitle = NSTextField(labelWithString: "一天的节奏")
        timelineTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        let legend = NSStackView(views: [legendItem("工作", color: .systemOrange),
                                        legendItem("休息", color: .systemGreen),
                                        legendItem("离开", color: ActivityDisplayKind.away.color),
                                        legendItem("未记录", color: .quaternaryLabelColor)])
        legend.spacing = 16
        [timelineTitle, NSView(), legend].forEach { timelineHeading.addArrangedSubview($0) }
        timelineHeading.distribution = .fill
        root.addArrangedSubview(timelineHeading)
        timelineHeading.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        root.addArrangedSubview(timeline)
        NSLayoutConstraint.activate([
            timeline.widthAnchor.constraint(equalTo: root.widthAnchor),
            timeline.heightAnchor.constraint(equalToConstant: 66)
        ])

        timeline.identifier = NSUserInterfaceItemIdentifier("historyTimeline")
        timeline.onSelect = { [weak self] interval in self?.selectInterval(interval) }
        weekView.onSelectDay = { [weak self] date in
            guard let self else { return }
            self.selectedDate = date
            self.followsToday = Calendar.current.isDateInToday(date)
            self.showsWeek = false
            self.mode.selectedSegment = 0
            self.selectedIntervalStart = nil
            self.refresh()
        }
        root.addArrangedSubview(weekView)
        weekView.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        weekView.identifier = NSUserInterfaceItemIdentifier("historyWeek")
        weekView.heightAnchor.constraint(greaterThanOrEqualToConstant: 252).isActive = true
        weekView.setContentHuggingPriority(.defaultLow, for: .vertical)
        weekView.isHidden = true
        listTitle.font = .systemFont(ofSize: 14, weight: .semibold)
        root.addArrangedSubview(listTitle)
        root.addArrangedSubview(listContainer)
        listContainer.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        listContainer.heightAnchor.constraint(greaterThanOrEqualToConstant: 130).isActive = true
        listContainer.setContentHuggingPriority(.defaultLow, for: .vertical)

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: listContainer.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor)
        ])
        table.dataSource = self
        table.delegate = self
        table.rowHeight = 34
        table.usesAlternatingRowBackgroundColors = true
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = false
        table.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        for (identifier, title, width) in [("start", "开始", 95.0), ("end", "结束", 95.0),
                                            ("duration", "时长", 140.0), ("kind", "类型", 120.0),
                                            ("reason", "原因", 260.0)] {
            let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
            column.title = title
            column.width = width
            column.minWidth = identifier == "reason" ? 120 : width
            table.addTableColumn(column)
        }
        scroll.documentView = table
        emptyState.alignment = .center
        emptyState.textColor = .secondaryLabelColor
        emptyState.font = .systemFont(ofSize: 14)
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        listContainer.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.centerXAnchor.constraint(equalTo: listContainer.centerXAnchor),
            emptyState.centerYAnchor.constraint(equalTo: listContainer.centerYAnchor, constant: 10),
            emptyState.widthAnchor.constraint(lessThanOrEqualTo: listContainer.widthAnchor, constant: -40)
        ])

        let export = NSButton(title: "导出 CSV…", target: self, action: #selector(exportCSV))
        excelBOM.toolTip = "在 UTF-8 CSV 开头添加 BOM，帮助 Excel 识别中文"
        management.addItem(withTitle: "记录管理")
        management.addItem(withTitle: "删除所选日 / 周…")
        management.lastItem?.action = #selector(deleteSelected)
        management.lastItem?.target = self
        management.addItem(withTitle: "清空全部历史…")
        management.lastItem?.action = #selector(deleteAll)
        management.lastItem?.target = self
        management.menu?.addItem(.separator())
        let heading = NSMenuItem(title: "自动保留（按本地日）", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        management.menu?.addItem(heading)
        for days in ActivityHistory.retentionChoices {
            let item = NSMenuItem(title: days == 0 ? "永久保留" : "保留 \(days) 天…", action: #selector(retentionChanged(_:)), keyEquivalent: "")
            item.tag = days
            item.target = self
            management.menu?.addItem(item)
        }
        let actions = NSStackView(views: [export, excelBOM, NSView(), management])
        actions.spacing = 10
        root.addArrangedSubview(actions)
        actions.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true

        errorLabel.font = .systemFont(ofSize: 11)
        errorLabel.textColor = .systemRed
        errorLabel.isHidden = true
        root.addArrangedSubview(errorLabel)
        errorLabel.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        footnote.font = .systemFont(ofSize: 11)
        footnote.textColor = .secondaryLabelColor
        root.addArrangedSubview(footnote)
        footnote.widthAnchor.constraint(equalTo: root.widthAnchor).isActive = true
        // The chart or daily table absorbs extra height; controls and summary keep their natural height.
        for view in root.arrangedSubviews where view !== weekView && view !== listContainer {
            view.setContentHuggingPriority(.required, for: .vertical)
            (view as? NSStackView)?.setHuggingPriority(.required, for: .vertical)
        }
    }

    private func totalCard(title: String, value: NSTextField, color: NSColor) -> NSView {
        let box = NSBox()
        box.boxType = .custom
        box.borderWidth = 1
        box.borderColor = .separatorColor
        box.fillColor = .controlBackgroundColor
        box.cornerRadius = 10
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = color
        value.font = .monospacedDigitSystemFont(ofSize: 27, weight: .medium)
        let stack = NSStackView(views: [label, value])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        let interior = box.contentView!
        interior.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: interior.leadingAnchor, constant: 14),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: interior.trailingAnchor, constant: -14),
            stack.topAnchor.constraint(equalTo: interior.topAnchor, constant: 10),
            stack.bottomAnchor.constraint(equalTo: interior.bottomAnchor, constant: -10),
            box.heightAnchor.constraint(equalToConstant: 92)
        ])
        return box
    }

    private func legendItem(_ title: String, color: NSColor) -> NSView {
        let dot = NSTextField(labelWithString: "●")
        dot.textColor = color
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [dot, label])
        stack.spacing = 4
        return stack
    }

    @objc private func previousDay() { moveDay(-1) }
    @objc private func nextDay() { moveDay(1) }
    private func moveDay(_ offset: Int) {
        guard let date = Calendar.current.date(byAdding: .day, value: offset * (showsWeek ? 7 : 1), to: selectedDate) else { return }
        selectedDate = min(date, Date())
        followsToday = Calendar.current.isDateInToday(selectedDate)
        selectedIntervalStart = nil
        refresh()
    }
    @objc private func modeChanged() {
        showsWeek = mode.selectedSegment == 1
        selectedIntervalStart = nil
        refresh()
    }
    @objc private func goToToday() {
        followsToday = true
        selectedIntervalStart = nil
        refresh()
    }
    @objc private func dateChanged() {
        selectedDate = min(datePicker.dateValue, Date())
        followsToday = Calendar.current.isDateInToday(selectedDate)
        selectedIntervalStart = nil
        refresh()
    }

    private func selectInterval(_ interval: ActivityDisplayInterval) {
        guard let row = records.firstIndex(where: { $0.contains(interval) }) else { return }
        selectedIntervalStart = interval.start
        table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        table.scrollRowToVisible(row)
        window?.makeFirstResponder(table)
    }

    private func selectedRange() -> DateInterval {
        showsWeek ? history.week(selectedDate).range : Calendar.current.dateInterval(of: .day, for: selectedDate)!
    }

    @objc private func exportCSV() {
        let range = selectedRange()
        let data = history.csv(in: range, includeBOM: excelBOM.state == .on)
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "RestReminder-\(formatter.string(from: range.start))\(showsWeek ? "-week" : "").csv"
        panel.title = showsWeek ? "导出所选周" : "导出所选日"
        panel.message = "UTF-8 CSV；精确时间含时区，时长以秒计。只导出已记录的时间，包含不足 1 秒的片段。"
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do { try data.write(to: url, options: .atomic); self.operationError = nil }
            catch { self.operationError = "导出失败：\(error.localizedDescription)" }
            self.refresh()
        }
    }

    @objc private func deleteSelected() { requestDeletion(in: selectedRange()) }
    @objc private func deleteAll() { requestDeletion(in: nil) }

    private func requestDeletion(in range: DateInterval?) {
        do {
            let preview = try history.previewDeletion(in: range)
            let title = range == nil ? "清空全部历史记录？" : (showsWeek ? "删除所选周的记录？" : "删除所选日的记录？")
            guard confirm(title, details: previewDetails(preview) + "\n\n删除无法撤销，可先取消并导出 CSV。确认后继续记录，已清除的时间不会补回。") else { return }
            try history.delete(preview)
            selectedIntervalStart = nil
            operationError = nil
        } catch { operationError = error.localizedDescription }
        refresh()
    }

    @objc private func retentionChanged(_ sender: NSMenuItem) {
        guard sender.tag != history.retentionDays else { return }
        do {
            let preview = try history.previewRetention(days: sender.tag)
            if let deletion = preview.deletion, let cutoff = preview.cutoff {
                let formatter = DateFormatter()
                formatter.dateFormat = "yyyy-MM-dd HH:mm:ss ZZZZZ"
                let details = "将保留最近 \(preview.days) 个本地日（从当前时间向前推算）。\n清理界限：\(formatter.string(from: cutoff))\n" + previewDetails(deletion)
                    + "\n\n确认后立即清理以上数据，并在之后保存时自动清理。删除无法撤销，可先取消并导出。"
                guard confirm("启用 \(preview.days) 天自动保留？", details: details) else { return }
            }
            try history.applyRetention(preview)
            operationError = nil
        } catch { operationError = error.localizedDescription }
        refresh()
    }

    private func previewDetails(_ preview: ActivityDeletionPreview) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS ZZZZZ"
        let range = preview.affectedRange.map { "\(formatter.string(from: $0.start)) 至 \(formatter.string(from: $0.end))" } ?? "没有受影响的已记录时间"
        return "预览：影响 \(preview.affectedIntervalCount) 个原始时段，删除 \(Self.duration(preview.removedSeconds))（\(String(format: "%.6f", preview.removedSeconds)) 秒）。\n时间范围：\(range)\n保留受影响时段的 \(preview.retainedFragmentCount) 个范围外片段。每个原始时段只计一次；中间空白不计时长。切分后按保留片段重新判断休息 / 离开。\n记录截点：\(formatter.string(from: preview.cutPoint))（最近一次观察）；此后的记录保留。"
    }

    private func confirm(_ title: String, details: String) -> Bool {
        if let confirmMutation { return confirmMutation(title, details) }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = details
        alert.addButton(withTitle: "取消")
        alert.addButton(withTitle: "确认")
        return alert.runModal() == .alertSecondButtonReturn
    }

    private func refresh() {
        let now = Date()
        let calendar = Calendar.current
        if followsToday { selectedDate = now }
        datePicker.maxDate = now
        datePicker.dateValue = selectedDate
        let week = showsWeek ? history.week(selectedDate, now: now, calendar: calendar, restThreshold: restThreshold()) : nil
        nextButton.isEnabled = week.map { $0.range.end <= calendar.startOfDay(for: now) } ?? !calendar.isDateInToday(selectedDate)
        previousButton.title = showsWeek ? "← 前一周" : "← 前一天"
        nextButton.title = showsWeek ? "后一周 →" : "下一天 →"
        timelineHeading.isHidden = showsWeek
        timeline.isHidden = showsWeek
        listTitle.isHidden = showsWeek
        listContainer.isHidden = showsWeek
        weekView.isHidden = !showsWeek
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        dateTitle.stringValue = formatter.string(from: selectedDate)
        let threshold = restThreshold()
        let day = history.day(selectedDate, now: now, calendar: calendar, restThreshold: threshold)
        records = day.detailGroups.sorted { $0.start > $1.start }
        workDurationScale = max(1, workInterval())
        restDurationScale = max(1, threshold)
        for record in records {
            if record.kind == .work { workDurationScale = max(workDurationScale, record.duration) }
            else if record.kind == .rest { restDurationScale = max(restDurationScale, record.duration) }
        }
        ongoingStart = day.ongoingStart
        workTotal.stringValue = Self.duration(day.workSeconds)
        restTotal.stringValue = Self.duration(day.restSeconds)
        awayTotal.stringValue = Self.duration(day.awaySeconds)
        let recorded = day.workSeconds + day.restSeconds
        if recorded > 0 {
            let workPercent = Int((day.workSeconds / recorded * 100).rounded())
            comparison.stringValue = "工作与休息 \(Self.duration(recorded))  ·  工作 \(workPercent)%  /  休息 \(100 - workPercent)%（不含离开及未记录时间）"
        } else {
            comparison.stringValue = "暂无工作与休息占比；离开及未记录时间不参与计算。"
        }
        summaryDetails.stringValue = "已完成休息 \(day.completedRestCount) 次  ·  最长连续工作 \(Self.duration(day.longestWorkSeconds))"
        summaryDetails.toolTip = "休息须达到当前设定，结束后计入结束所在日期；进行中和离开不计次数。最长连续工作只计算当天片段。"
        // Draw original observed fragments so a grouped row never paints over a gap.
        timeline.update(intervals: day.displayIntervals, date: selectedDate, calendar: calendar)
        emptyState.isHidden = !records.isEmpty
        emptyState.stringValue = day.intervals.isEmpty
            ? "这一天还没有记录\n应用运行后，工作与休息时段会显示在这里。"
            : "暂时没有可显示的时段\n不足 1 秒的片段已隐藏，时长仍保留在汇总中。"
        table.reloadData()
        if let start = selectedIntervalStart, let row = records.firstIndex(where: { $0.intervals.contains { $0.start == start } }) {
            table.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        if let week {
            formatter.dateFormat = "yyyy年M月d日"
            let sunday = calendar.date(byAdding: .day, value: -1, to: week.range.end)!
            dateTitle.stringValue = "\(formatter.string(from: week.range.start)) — \(formatter.string(from: sunday))"
            workTotal.stringValue = Self.duration(week.workSeconds)
            restTotal.stringValue = Self.duration(week.restSeconds)
            awayTotal.stringValue = Self.duration(week.awaySeconds)
            let prior = history.week(calendar.date(byAdding: .day, value: -7, to: week.range.start)!, now: now, calendar: calendar)
            let partial = now < week.range.end
            comparison.stringValue = "\(partial ? "本周截至目前" : "所选周合计")：工作与休息 \(Self.duration(week.workSeconds + week.restSeconds))；上周完整工作 \(Self.duration(prior.workSeconds))（不含离开）。"
            summaryDetails.stringValue = "周一至周日 · 点选日期查看当天明细 · 今天只计已观察的时间，未来日期尚未到来。"
            summaryDetails.toolTip = "每条柱按对应本地日的实际长度缩放；夏令时日可能为 23 或 25 小时。柱形依次表示工作、短休息、离开；空白不计入总时长。"
            weekView.update(week: week, now: now)
        }
        for item in management.itemArray where item.action == #selector(retentionChanged(_:)) {
            item.state = item.tag == history.retentionDays ? .on : .off
        }
        management.itemArray.first(where: { $0.action == #selector(deleteSelected) })?.title = showsWeek ? "删除所选周…" : "删除所选日…"
        for item in management.itemArray where item.action == #selector(deleteSelected) || item.action == #selector(deleteAll) {
            item.isEnabled = history.allowsDestructiveChanges
        }
        errorLabel.stringValue = operationError ?? history.persistenceError.map { "本地记录保存异常：\($0)" } ?? ""
        errorLabel.isHidden = errorLabel.stringValue.isEmpty
        footnote.stringValue = "无键鼠操作达 \(Self.duration(threshold)) 计休息；单个原始休息段满 1 小时归离开，不计休息占比。看视频无操作也会计入。\n同类相邻间隔不超 2 分钟合并显示，时长只累计已记录片段；悬停查看子时段和缺口，分类、次数、最长连续工作不变。\n点击时间轴可定位明细；不足 1 秒的独立合并行隐藏，汇总保留。灰绿为离开，灰色为未记录；仅本机保存，仅供回顾。"
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(max(0, seconds).rounded(.down))
        if total < 60 { return "\(total)秒" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes)分" }
        return "\(minutes / 60)小时 \(minutes % 60)分"
    }

    func numberOfRows(in tableView: NSTableView) -> Int { records.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard records.indices.contains(row), let column = tableColumn else { return nil }
        let record = records[row]
        let ongoing = Calendar.current.isDateInToday(selectedDate) && (ongoingStart.map {
            let start = max($0, Calendar.current.startOfDay(for: selectedDate))
            return record.intervals.contains { $0.start <= start && $0.end > start }
        } ?? false)
        let text: String
        switch column.identifier.rawValue {
        case "start": text = timeFormatter.string(from: record.start)
        case "end":
            let nextDay = !Calendar.current.isDate(record.start, inSameDayAs: record.end)
            text = ongoing ? "至今" : (nextDay ? "24:00:00" : timeFormatter.string(from: record.end))
        case "duration": text = Self.duration(record.duration) + (record.intervals.count > 1 ? "（\(record.intervals.count)段）" : "")
        case "kind": text = record.kind.title + (ongoing ? " · 进行中" : "")
        default: text = record.reason.isEmpty ? "—" : record.reason
        }
        let identifier = column.identifier
        if identifier.rawValue == "duration" {
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? HistoryDurationCell
                ?? HistoryDurationCell()
            cell.identifier = identifier
            let threshold = record.kind == .work ? workInterval() : restThreshold()
            let scale = record.kind == .work ? workDurationScale : restDurationScale
            let exceeded = record.kind != .away && threshold.isFinite && threshold > 0 && record.duration > threshold
            cell.configure(text: text, color: record.kind.color,
                           fraction: exceeded ? CGFloat(min(1, record.duration / max(1, scale))) : nil)
            cell.toolTip = record.kind == .away
                ? "\(text)；整段离开达到 1 小时，不计入休息占比或完成次数。"
                : exceeded
                    ? "\(text)；超过当前\(record.kind.title)设定 \(Self.duration(threshold))。柱长按当天同类型最长时段缩放。"
                    : "\(text)；未超过当前设定 \(Self.duration(threshold))。"
            if record.intervals.count > 1 {
                cell.toolTip = detailTooltip(record) + "\n" + (cell.toolTip ?? "")
            }
            return cell
        }
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTableCellView ?? NSTableCellView()
        if cell.textField == nil {
            cell.identifier = identifier
            let label = NSTextField(labelWithString: "")
            label.translatesAutoresizingMaskIntoConstraints = false
            label.lineBreakMode = .byTruncatingTail
            cell.addSubview(label)
            cell.textField = label
            NSLayoutConstraint.activate([
                label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 6),
                label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6),
                label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
            ])
        }
        cell.textField?.stringValue = text
        cell.textField?.font = column.identifier.rawValue == "start" || column.identifier.rawValue == "end"
            ? .monospacedDigitSystemFont(ofSize: 12, weight: .regular) : .systemFont(ofSize: 12)
        cell.textField?.textColor = column.identifier.rawValue == "kind" ? record.kind.textColor : .labelColor
        cell.toolTip = record.intervals.count > 1 ? detailTooltip(record) : text
        return cell
    }

    private func detailTooltip(_ group: ActivityDetailGroup) -> String {
        var lines = ["合并 \(group.intervals.count) 段\(group.kind.title)，实际记录 \(Self.duration(group.duration))（\(String(format: "%.3f", group.duration)) 秒）。"]
        lines.append("起止范围包含 \(String(format: "%.3f", group.gapDuration)) 秒未记录间隔；这些间隔不计入时长，合并不表示连续工作或连续休息。")
        for interval in group.intervals {
            let reason = interval.reason.isEmpty ? "未注明原因" : interval.reason
            lines.append("\(timeFormatter.string(from: interval.start)) – \(timeFormatter.string(from: interval.end)) · \(String(format: "%.3f", interval.duration)) 秒 · \(reason)")
        }
        return lines.joined(separator: "\n")
    }
}

private final class HistoryDurationCell: NSTableCellView {
    private var fraction: CGFloat?
    private var barColor = NSColor.systemOrange

    init() {
        super.init(frame: .zero)
        let label = NSTextField(labelWithString: "")
        label.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        textField = label
    }

    required init?(coder: NSCoder) { nil }

    func configure(text: String, color: NSColor, fraction: CGFloat?) {
        textField?.stringValue = text
        textField?.setAccessibilityLabel(text + (fraction == nil ? "" : "，已超过设定时长"))
        self.fraction = fraction
        barColor = color
        needsLayout = true
        needsDisplay = true
    }

    override func layout() {
        super.layout()
        textField?.frame = NSRect(x: 6, y: fraction == nil ? (bounds.height - 17) / 2 : 15,
                                  width: max(0, bounds.width - 12), height: 17)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let fraction else { return }
        let track = NSRect(x: 6, y: 6, width: max(0, bounds.width - 12), height: 5)
        guard track.width > 0 else { return }
        barColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: track, xRadius: 2.5, yRadius: 2.5).fill()
        var fill = track
        fill.size.width = min(track.width, max(2, track.width * fraction))
        barColor.setFill()
        NSBezierPath(roundedRect: fill, xRadius: 2.5, yRadius: 2.5).fill()
    }
}

private final class HistoryBackgroundView: NSView {
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

/// Seven native day buttons keep the weekly graphic keyboard accessible.
private final class HistoryWeekView: NSView {
    var onSelectDay: ((Date) -> Void)?
    private let stack = NSStackView()
    private var days: [ActivityWeekDay] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        stack.orientation = .vertical
        stack.distribution = .fillEqually
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }
    required init?(coder: NSCoder) { nil }

    func update(week: ActivityWeek, now: Date) {
        days = week.days
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let clock = DateFormatter()
        clock.dateFormat = "HH:mm"
        let weekdays = ["周一", "周二", "周三", "周四", "周五", "周六", "周日"]
        for (index, day) in week.days.enumerated() {
            let button = NSButton(title: "\(weekdays[index]) \(formatter.string(from: day.range.start))", target: self, action: #selector(selectDay(_:)))
            button.tag = index
            button.isEnabled = day.status != .future
            button.setAccessibilityLabel("查看 \(button.title) 的日明细")
            button.widthAnchor.constraint(equalToConstant: 110).isActive = true
            let bar = HistoryWeekBar()
            bar.day = day
            bar.setAccessibilityElement(true)
            bar.setAccessibilityRole(.image)
            let summary = day.summary
            func hours(_ seconds: TimeInterval) -> String { String(format: "%.2f", seconds / 3600) }
            let status = day.status == .future ? "尚未到来" : (day.status == .partial ? "今天截至 \(clock.string(from: now))" : "已结束")
            let detail = "工作 \(hours(summary.workSeconds)) 小时，短休息 \(hours(summary.restSeconds)) 小时，离开 \(hours(summary.awaySeconds)) 小时；\(status)；本地日长 \(hours(day.range.duration)) 小时。"
            bar.setAccessibilityLabel(detail)
            bar.toolTip = detail
            let label = NSTextField(labelWithString: day.status == .future ? status : "工 \(hours(summary.workSeconds)) · 休 \(hours(summary.restSeconds)) · 离 \(hours(summary.awaySeconds)) 小时" + (day.status == .partial ? " · 截至目前" : ""))
            label.font = .monospacedDigitSystemFont(ofSize: 10, weight: .regular)
            label.textColor = .secondaryLabelColor
            label.widthAnchor.constraint(equalToConstant: 302).isActive = true
            let row = NSStackView(views: [button, bar, label])
            row.spacing = 8
            bar.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
            bar.heightAnchor.constraint(equalToConstant: 18).isActive = true
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    @objc private func selectDay(_ sender: NSButton) {
        guard days.indices.contains(sender.tag), days[sender.tag].status != .future else { return }
        onSelectDay?(days[sender.tag].range.start)
    }
}

private final class HistoryWeekBar: NSView {
    var day: ActivityWeekDay?
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let day, day.status != .future else { return }
        let path = NSBezierPath(roundedRect: bounds, xRadius: 4, yRadius: 4)
        NSColor.quaternaryLabelColor.setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        var left: CGFloat = 0
        for (seconds, color) in [(day.summary.workSeconds, NSColor.systemOrange),
                                  (day.summary.restSeconds, NSColor.systemGreen),
                                  (day.summary.awaySeconds, ActivityDisplayKind.away.color)] {
            let width = CGFloat(seconds / day.range.duration) * bounds.width
            color.setFill()
            NSRect(x: left, y: 0, width: width, height: bounds.height).fill()
            left += width
        }
        NSGraphicsContext.restoreGraphicsState()
    }
}

private final class HistoryTimelineView: NSView {
    var onSelect: ((ActivityDisplayInterval) -> Void)?
    private var intervals: [ActivityDisplayInterval] = []
    private var day = DateInterval(start: Date(), duration: 86400)
    private var calendar = Calendar.current

    func update(intervals: [ActivityDisplayInterval], date: Date, calendar: Calendar) {
        self.intervals = intervals
        self.calendar = calendar
        if let day = calendar.dateInterval(of: .day, for: date) { self.day = day }
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel("全天时间轴；橙色为工作，绿色为休息，灰绿色为离开，灰色为未记录。离开不计入休息占比。点击时段可选中并滚动至下方明细；也可直接使用列表。")
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard bounds.width > 0, point.y >= 27, point.y <= 55, point.x >= 0, point.x < bounds.width else { return }
        let date = day.start.addingTimeInterval(Double(point.x / bounds.width) * day.duration)
        if let interval = intervals.first(where: { date >= $0.start && date < $0.end }) { onSelect?(interval) }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let bar = NSRect(x: 0, y: 27, width: bounds.width, height: 28)
        let path = NSBezierPath(roundedRect: bar, xRadius: 6, yRadius: 6)
        NSColor.quaternaryLabelColor.setFill()
        path.fill()
        NSGraphicsContext.saveGraphicsState()
        path.addClip()
        for record in intervals {
            let start = max(day.start, record.start)
            let end = min(day.end, record.end)
            guard end > start else { continue }
            let left = CGFloat(start.timeIntervalSince(day.start) / day.duration) * bar.width
            let width = CGFloat(end.timeIntervalSince(start) / day.duration) * bar.width
            record.kind.color.setFill()
            NSRect(x: left, y: bar.minY, width: width, height: bar.height).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular),
            .foregroundColor: NSColor.secondaryLabelColor
        ]
        for hour in [0, 6, 12, 18, 24] {
            let date = hour == 24 ? day.end
                : calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.start) ?? day.start
            let x = CGFloat(date.timeIntervalSince(day.start) / day.duration) * bar.width
            let label = String(format: "%02d:00", hour) as NSString
            let size = label.size(withAttributes: attributes)
            label.draw(at: NSPoint(x: min(max(0, x - size.width / 2), bounds.width - size.width), y: 5),
                       withAttributes: attributes)
        }
    }
}
