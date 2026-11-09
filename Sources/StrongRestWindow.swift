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

enum RestScreenMode {
    case countdown, voluntary
}

/// Presentation only. Call all methods on the main thread; the owner supplies idle
/// or elapsed time, decides when rest is complete, and handles the selected action.
final class StrongRestWindow {
    var onEmergency: (() -> Void)?
    var onEndVoluntary: (() -> Void)?
    var isVisible: Bool { windows.contains { $0.isVisible } }

    private let photograph: NSImage?
    private var windows: [StrongRestScreenWindow] = []
    private var screenFrames: [NSRect] = []
    private var screenObserver: NSObjectProtocol?
    private var presented = false
    private var previousApplication: NSRunningApplication?
    private var remaining: TimeInterval = 300
    private var total: TimeInterval = 300
    private var workSeconds: TimeInterval = 0
    private var mode: RestScreenMode = .countdown
    private var elapsed: TimeInterval = 0
    private var advice = RestAdvice.all[0]

    init(photoURL: URL? = nil) {
        let url = photoURL
            ?? Bundle.main.url(forResource: "fresh-green", withExtension: "jpg")
            ?? Bundle.main.url(forResource: "fresh-green", withExtension: "jpg", subdirectory: "Resources")
        photograph = url.flatMap { NSImage(contentsOf: $0) }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self, self.presented else { return }
            self.rebuildIfNeeded()
        }
    }

    deinit {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        windows.forEach { $0.orderOut(nil) }
    }

    func show(returningTo application: NSRunningApplication? = nil) {
        guard !presented else { rebuildIfNeeded(); return }
        let front = application ?? NSWorkspace.shared.frontmostApplication
        previousApplication = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
        presented = true
        rebuildIfNeeded()
        revealWindows()
    }

    func update(remaining: TimeInterval, total: TimeInterval, workSeconds: TimeInterval,
                advice: RestAdvice? = nil, mode: RestScreenMode = .countdown,
                elapsed: TimeInterval = 0) {
        if let advice { self.advice = advice }
        self.total = total.isFinite ? max(1, total) : 300
        self.remaining = remaining.isFinite ? min(max(0, remaining), self.total) : self.total
        self.workSeconds = workSeconds.isFinite ? max(0, workSeconds) : 0
        self.mode = mode
        // The largest finite Double can exceed Int's range; keep clock conversion safe.
        self.elapsed = elapsed.isFinite ? min(max(0, elapsed), Double(Int.max).nextDown) : 0
        if presented { rebuildIfNeeded() }
        refreshContent()
    }

    func hide() {
        let wasPresented = presented
        presented = false
        windows.forEach { $0.orderOut(nil) }
        if wasPresented, NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            previousApplication?.activate(options: [])
        }
        previousApplication = nil
    }

    private func rebuildIfNeeded() {
        let screens = NSScreen.screens
        let frames = screens.map { $0.frame }
        guard frames != screenFrames || windows.isEmpty else { return }
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        screenFrames = frames
        for screen in screens {
            let window = StrongRestScreenWindow(
                contentRect: screen.frame, styleMask: .borderless,
                backing: .buffered, defer: false, screen: screen
            )
            window.setFrame(screen.frame, display: false)
            window.isReleasedWhenClosed = false
            window.level = .statusBar
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.isOpaque = true
            window.backgroundColor = NSColor(calibratedRed: 0.88, green: 0.96, blue: 0.87, alpha: 1)
            window.hasShadow = false
            window.hidesOnDeactivate = false
            window.isMovable = false
            window.isExcludedFromWindowsMenu = true
            let view = StrongRestPageView(frame: NSRect(origin: .zero, size: screen.frame.size), photograph: photograph)
            view.onEmergency = { [weak self] in
                guard let self else { return }
                switch self.mode {
                case .countdown: self.onEmergency?()
                case .voluntary: self.onEndVoluntary?()
                }
            }
            view.autoresizingMask = [.width, .height]
            window.contentView = view
            window.initialFirstResponder = view.emergencyButton
            windows.append(window)
        }
        refreshContent()
        if presented { revealWindows() }
    }

    private func refreshContent() {
        for window in windows {
            switch mode {
            case .countdown:
                window.title = "认真休息一下"
                window.setAccessibilityLabel("休息提醒，连续离开键鼠后完成休息")
            case .voluntary:
                window.title = "正在休息"
                window.setAccessibilityLabel("正在休息，已休息时间持续计时，直到你结束休息")
            }
            (window.contentView as? StrongRestPageView)?.update(
                remaining: remaining, total: total, workSeconds: workSeconds, advice: advice,
                mode: mode, elapsed: elapsed
            )
        }
    }

    private func revealWindows() {
        // No presentation options, event taps, or global keyboard interception.
        // Users retain ordinary system shortcuts and can switch applications.
        windows.forEach { $0.orderFrontRegardless() }
        let pointer = NSEvent.mouseLocation
        let focusWindow = windows.first { $0.frame.contains(pointer) } ?? windows.first
        NSApp.activate(ignoringOtherApps: true)
        focusWindow?.makeKeyAndOrderFront(nil)
        if let view = focusWindow?.contentView as? StrongRestPageView {
            focusWindow?.makeFirstResponder(view.emergencyButton)
        }
    }
}

/// Borderless windows need to opt into key status for native button keyboard use.
private final class StrongRestScreenWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { /* Escape does not dismiss rest. */ }
    override func performClose(_ sender: Any?) { /* Only the owner dismisses rest. */ }
}

/// Everything, including the photograph and wash, is drawn in the view hierarchy
/// so cacheDisplay(to:) works without screen recording or compositor effects.
private final class StrongRestPageView: NSView {
    var onEmergency: (() -> Void)?
    let emergencyButton = NSButton(title: "有急事，再给我 5 分钟", target: nil, action: nil)

    private let photograph: NSImage?
    private let ink = NSColor(calibratedRed: 0.10, green: 0.25, blue: 0.15, alpha: 1)
    private let eyebrow = NSTextField(labelWithString: "暂时放下工作 · 好好照顾自己")
    private let titleLabel = NSTextField(wrappingLabelWithString: "已经努力很久了，这次认真休息一下。")
    private let subtitle = NSTextField(wrappingLabelWithString: "放下键鼠，起身走走、看看远处。")
    private let countdown = NSTextField(labelWithString: "05:00")
    private let status = NSTextField(wrappingLabelWithString: "")
    private let workLabel = NSTextField(labelWithString: "")
    private let progress = NSProgressIndicator()

    init(frame: NSRect, photograph: NSImage?) {
        self.photograph = photograph
        super.init(frame: frame)
        // Deliberately no animated backgrounds or transitions: also respects Reduce Motion.
        for label in [eyebrow, titleLabel, subtitle, countdown, status, workLabel] {
            label.textColor = ink
            label.alignment = .center
            label.isSelectable = false
            label.lineBreakMode = .byWordWrapping
            addSubview(label)
        }
        eyebrow.font = .systemFont(ofSize: 14, weight: .medium)
        titleLabel.font = .systemFont(ofSize: 32, weight: .semibold)
        subtitle.font = .systemFont(ofSize: 19, weight: .regular)
        countdown.font = .monospacedDigitSystemFont(ofSize: 88, weight: .medium)
        countdown.setAccessibilityLabel("连续休息剩余时间")
        status.font = .systemFont(ofSize: 15, weight: .medium)
        workLabel.font = .systemFont(ofSize: 13)
        workLabel.textColor = ink.withAlphaComponent(0.8)
        progress.isIndeterminate = false
        progress.style = .bar
        progress.minValue = 0
        progress.maxValue = 1
        progress.isDisplayedWhenStopped = true
        progress.setAccessibilityLabel("连续休息完成进度")
        addSubview(progress)
        emergencyButton.target = self
        emergencyButton.action = #selector(emergencyPressed(_:))
        emergencyButton.bezelStyle = .rounded
        emergencyButton.controlSize = .large
        emergencyButton.font = .systemFont(ofSize: 16, weight: .medium)
        emergencyButton.keyEquivalent = "\r"
        emergencyButton.setAccessibilityLabel("有急事，再给我 5 分钟")
        emergencyButton.setAccessibilityHelp("推迟本次休息，继续工作五分钟。")
        emergencyButton.nextKeyView = emergencyButton
        addSubview(emergencyButton)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override var isOpaque: Bool { true }

    @objc private func emergencyPressed(_ sender: NSButton) {
        onEmergency?()
    }

    func update(remaining: TimeInterval, total: TimeInterval, workSeconds: TimeInterval,
                advice: RestAdvice, mode: RestScreenMode, elapsed: TimeInterval) {
        subtitle.stringValue = "\(advice.category)：\(advice.message)"
        switch mode {
        case .countdown:
            eyebrow.stringValue = "暂时放下工作 · 好好照顾自己"
            titleLabel.stringValue = "已经努力很久了，这次认真休息一下。"
            let seconds = Int(ceil(min(remaining, 359_999)))
            countdown.stringValue = String(format: "%02d:%02d", seconds / 60, seconds % 60)
            countdown.setAccessibilityLabel("连续休息剩余时间")
            countdown.setAccessibilityValue("\(seconds / 60) 分 \(seconds % 60) 秒")
            progress.isHidden = false
            progress.setAccessibilityElement(true)
            progress.setAccessibilityLabel("连续休息完成进度")
            progress.doubleValue = max(0, min(1, 1 - remaining / total))
            let minutes = total / 60
            let duration = total.truncatingRemainder(dividingBy: 60) == 0
                ? "\(Int(min(minutes, 5_999))) 分钟" : "\(Int(ceil(min(total, 359_999)))) 秒"
            status.stringValue = "连续离开键鼠 \(duration)，休息才算完成。\n使用键盘或鼠标会重新计时。"
            workLabel.stringValue = workSeconds >= 60
                ? "你已经投入了 \(Int(min(workSeconds / 60, 999_999))) 分钟，现在把时间留给自己。"
                : "已经提醒过 3 次，这次让身体真正休息。"
            emergencyButton.title = "有急事，再给我 5 分钟"
            emergencyButton.setAccessibilityLabel("有急事，再给我 5 分钟")
            emergencyButton.setAccessibilityHelp("推迟本次休息，继续工作五分钟。")
        case .voluntary:
            eyebrow.stringValue = "暂时放下工作 · 按自己的节奏休息"
            titleLabel.stringValue = "休息一下，慢慢放松。"
            let seconds = Int(floor(elapsed))
            let minutes = seconds / 60
            if seconds >= 3_600 {
                countdown.stringValue = String(format: "%02lld:%02lld:%02lld", seconds / 3_600, minutes % 60, seconds % 60)
                countdown.setAccessibilityValue("\(seconds / 3_600) 小时 \(minutes % 60) 分 \(seconds % 60) 秒")
            } else {
                countdown.stringValue = String(format: "%02d:%02d", minutes, seconds % 60)
                countdown.setAccessibilityValue("\(minutes) 分 \(seconds % 60) 秒")
            }
            countdown.setAccessibilityLabel("已休息时间")
            progress.isHidden = true
            progress.setAccessibilityElement(false)
            progress.setAccessibilityLabel(nil)
            progress.doubleValue = 0
            status.stringValue = "已休息，慢慢放松。\n计时持续到你结束休息，键鼠操作不会重置。"
            workLabel.stringValue = "准备好时，点击「结束休息」再回来。"
            emergencyButton.title = "结束休息"
            emergencyButton.setAccessibilityLabel("结束休息")
            emergencyButton.setAccessibilityHelp("结束本次自主休息，返回之前的工作。")
        }
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let width = min(780, max(0, bounds.width - 48))
        let x = (bounds.width - width) / 2
        // Fit compact displays while keeping the emergency control inside the frame.
        let compact = bounds.height < 660
        let top = min(bounds.height - 32, bounds.midY + (compact ? 218 : 260))
        eyebrow.frame = NSRect(x: x, y: top - 22, width: width, height: 22)
        titleLabel.font = .systemFont(ofSize: bounds.width < 700 ? 26 : 32, weight: .semibold)
        titleLabel.frame = NSRect(x: x, y: top - 110, width: width, height: 72)
        subtitle.frame = NSRect(x: x, y: top - 163, width: width, height: 48)
        var clockFont = NSFont.monospacedDigitSystemFont(ofSize: compact ? 72 : 88, weight: .medium)
        let availableClockWidth = max(1, width - 8)
        // System-font metrics vary with optical size; measure again after fitting.
        for _ in 0..<3 {
            let clockWidth = (countdown.stringValue as NSString).size(withAttributes: [.font: clockFont]).width
            guard clockWidth > availableClockWidth else { break }
            clockFont = .monospacedDigitSystemFont(
                ofSize: clockFont.pointSize * availableClockWidth / clockWidth, weight: .medium
            )
        }
        countdown.font = clockFont
        countdown.frame = NSRect(x: x, y: top - 272, width: width, height: 105)
        let barWidth = min(400, width)
        progress.frame = NSRect(x: bounds.midX - barWidth / 2, y: top - 292, width: barWidth, height: 12)
        status.frame = NSRect(x: x, y: top - 359, width: width, height: 50)
        workLabel.frame = NSRect(x: x, y: top - 390, width: width, height: 24)
        let buttonWidth = min(300, width)
        emergencyButton.frame = NSRect(x: bounds.midX - buttonWidth / 2,
                                       y: max(20, top - 462), width: buttonWidth, height: 44)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.87, green: 0.95, blue: 0.85, alpha: 1).setFill()
        bounds.fill()
        if let photograph, photograph.size.width > 0, photograph.size.height > 0 {
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(rect: bounds).addClip()
            let scale = max(bounds.width / photograph.size.width, bounds.height / photograph.size.height)
            let size = NSSize(width: photograph.size.width * scale, height: photograph.size.height * scale)
            let rect = NSRect(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2,
                              width: size.width, height: size.height)
            photograph.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        NSColor(calibratedRed: 0.89, green: 0.98, blue: 0.88, alpha: 0.76).setFill()
        bounds.fill()
        // A bright quiet area protects text contrast while retaining foliage at the edges.
        let quiet = NSRect(x: bounds.midX - min(500, bounds.width / 2), y: bounds.midY - 300,
                           width: min(1_000, bounds.width), height: 600)
        NSColor(calibratedRed: 0.97, green: 0.99, blue: 0.92, alpha: 0.65).setFill()
        NSBezierPath(roundedRect: quiet, xRadius: 60, yRadius: 60).fill()
    }
}
