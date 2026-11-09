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
import QuartzCore

/// Non-activating, click-through feedback leaves typing and pointer focus alone.
final class ReturnCelebration {
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?
    private let photograph: NSImage?
    private let restPhotograph: NSImage?

    init(photographURL: URL? = Bundle.main.url(forResource: "morning-sun", withExtension: "jpg"),
         restPhotographURL: URL? = Bundle.main.url(forResource: "fresh-green", withExtension: "jpg")) {
        photograph = photographURL.flatMap { NSImage(contentsOf: $0) }
        restPhotograph = restPhotographURL.flatMap { NSImage(contentsOf: $0) }
    }

    func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }

    func show(welcome: Bool, restMinutes: String = "2", advice: RestAdvice? = nil) {
        dismiss()
        let size = NSSize(width: 640, height: 460)
        let window = NSPanel(contentRect: NSRect(origin: .zero, size: size),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.level = .floating
        window.ignoresMouseEvents = true
        window.hidesOnDeactivate = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        window.setAccessibilityLabel(welcome ? "休息完成，欢迎回来，元气满满" : "休息还不够，请再起来活动一下")
        let card: NSView
        let announcement: String
        if welcome {
            let morning = MorningWelcomeView(frame: NSRect(origin: .zero, size: size), photograph: photograph)
            card = morning
            announcement = "欢迎回来，元气满满！休息得很好，带着好心情，开启新一轮专注。"
        } else {
            let suggestion = advice ?? RestAdvice.all[0]
            card = exerciseCard(size: size, restMinutes: restMinutes, advice: suggestion)
            announcement = "\(suggestion.title)。\(suggestion.message) 连续离开键鼠 \(restMinutes) 分钟，再满电回来。"
        }
        window.contentView = card
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
        if let visible = screen?.visibleFrame {
            window.setFrameOrigin(NSPoint(x: visible.midX - size.width / 2, y: visible.midY - size.height / 2))
        }
        window.alphaValue = 0
        window.orderFrontRegardless()
        panel = window
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.4
            window.animator().alphaValue = 1
        }
        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let arrival = CAKeyframeAnimation(keyPath: "transform.scale")
            arrival.values = [0.95, 1.008, 1.0]
            arrival.keyTimes = [0, 0.75, 1]
            arrival.duration = 0.75
            arrival.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.layer?.add(arrival, forKey: "arrival")
            if let morning = card as? MorningWelcomeView { morning.animateMorningLight() }
        }
        NSAccessibility.post(element: card, notification: .announcementRequested, userInfo: [
            .announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue
        ])
        let task = DispatchWorkItem { [weak self, weak window] in
            guard let window, self?.panel === window else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = welcome ? 0.2 : 0.45
                window.animator().alphaValue = 0
            }, completionHandler: { [weak self, weak window] in
                window?.orderOut(nil)
                if self?.panel === window { self?.panel = nil }
            })
        }
        dismissal = task
        // Welcome includes its fade-out in the two-second presentation budget.
        DispatchQueue.main.asyncAfter(deadline: .now() + (welcome ? 1.8 : 6), execute: task)
    }

    private func exerciseCard(size: NSSize, restMinutes: String, advice: RestAdvice) -> NSView {
        GreenRestView(frame: NSRect(origin: .zero, size: size), photograph: restPhotograph,
                      restMinutes: restMinutes, advice: advice)
    }
}

/// Fresh fern photography uses the same borderless format as the welcome card.
private final class GreenRestView: NSView {
    private let photograph: NSImage?
    private let ink = NSColor(calibratedRed: 0.11, green: 0.28, blue: 0.16, alpha: 1)

    init(frame: NSRect, photograph: NSImage?, restMinutes: String, advice: RestAdvice) {
        self.photograph = photograph
        super.init(frame: frame)
        wantsLayer = true
        let badge = NSTextField(labelWithString: advice.category)
        badge.font = .systemFont(ofSize: 12, weight: .medium)
        badge.textColor = ink.withAlphaComponent(0.9)
        badge.frame = NSRect(x: 36, y: 405, width: 160, height: 20)
        addSubview(badge)
        let title = NSTextField(labelWithString: advice.title)
        title.font = .systemFont(ofSize: 30, weight: .semibold)
        title.textColor = ink
        title.frame = NSRect(x: 32, y: 150, width: 580, height: 44)
        addSubview(title)
        let message = NSTextField(wrappingLabelWithString: "刚才的休息还短了一点，先别急着开工。\n\(advice.message)\n连续离开键鼠 \(restMinutes) 分钟，再满电回来。")
        message.font = .systemFont(ofSize: 16)
        message.textColor = ink.withAlphaComponent(0.87)
        message.frame = NSRect(x: 34, y: 69, width: 570, height: 72)
        addSubview(message)
        let footnote = NSTextField(labelWithString: "给自己一个真正的休息")
        footnote.font = .systemFont(ofSize: 12, weight: .medium)
        footnote.textColor = ink.withAlphaComponent(0.75)
        footnote.frame = NSRect(x: 34, y: 30, width: 360, height: 20)
        addSubview(footnote)
        let credit = NSTextField(labelWithString: "摄影 · Unsplash")
        credit.font = .systemFont(ofSize: 10)
        credit.textColor = ink.withAlphaComponent(0.55)
        credit.alignment = .right
        credit.frame = NSRect(x: 460, y: 30, width: 145, height: 18)
        addSubview(credit)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        NSBezierPath(roundedRect: bounds, xRadius: 32, yRadius: 32).addClip()
        if let photograph {
            let size = photograph.size
            let scale = max(bounds.width / size.width, bounds.height / size.height)
            let crop = NSRect(x: (size.width - bounds.width / scale) / 2,
                              y: (size.height - bounds.height / scale) / 2,
                              width: bounds.width / scale, height: bounds.height / scale)
            photograph.draw(in: bounds, from: crop, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSColor(calibratedRed: 0.62, green: 0.84, blue: 0.59, alpha: 1).setFill()
            bounds.fill()
        }
        // Soft mint light keeps the natural foliage bright; no black panel or outline.
        NSColor(calibratedRed: 0.90, green: 0.98, blue: 0.82, alpha: 0.20).setFill()
        bounds.fill()
        NSGradient(starting: NSColor(calibratedRed: 0.94, green: 0.99, blue: 0.89, alpha: 0.99),
                   ending: NSColor(calibratedRed: 0.93, green: 0.99, blue: 0.87, alpha: 0.20))?
            .draw(from: NSPoint(x: 0, y: 0), to: NSPoint(x: 0, y: 420),
                  options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        NSColor(calibratedRed: 0.96, green: 1, blue: 0.92, alpha: 0.76).setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 398, width: 150, height: 34), xRadius: 17, yRadius: 17).fill()
        NSGraphicsContext.restoreGraphicsState()
    }
}

/// Edge-to-edge photography with a warm light wash, without a stroke or colored rim.
private final class MorningWelcomeView: NSView {
    private let photograph: NSImage?
    private let gold = NSColor(calibratedRed: 1, green: 0.82, blue: 0.46, alpha: 1)
    private let ink = NSColor(calibratedRed: 0.30, green: 0.18, blue: 0.09, alpha: 1)

    init(frame: NSRect, photograph: NSImage?) {
        self.photograph = photograph
        super.init(frame: frame)
        wantsLayer = true
        let badge = NSTextField(labelWithString: "✦  休息完成")
        badge.font = .systemFont(ofSize: 12, weight: .medium)
        badge.textColor = ink.withAlphaComponent(0.90)
        badge.frame = NSRect(x: 34, y: 405, width: 150, height: 20)
        addSubview(badge)
        let title = NSTextField(labelWithString: "欢迎回来，元气满满！")
        title.font = .systemFont(ofSize: 32, weight: .semibold)
        title.textColor = ink
        title.frame = NSRect(x: 32, y: 138, width: 580, height: 46)
        addSubview(title)
        let message = NSTextField(wrappingLabelWithString: "休息得很好，新的专注旅程开始啦。\n带着好心情，慢慢来，也能做得很棒。")
        message.font = .systemFont(ofSize: 16, weight: .regular)
        message.textColor = ink.withAlphaComponent(0.85)
        message.frame = NSRect(x: 34, y: 77, width: 560, height: 50)
        addSubview(message)
        let footnote = NSTextField(labelWithString: "新一轮专注，刚刚开始")
        footnote.font = .systemFont(ofSize: 12, weight: .medium)
        footnote.textColor = ink.withAlphaComponent(0.75)
        footnote.frame = NSRect(x: 34, y: 30, width: 340, height: 20)
        addSubview(footnote)
        let credit = NSTextField(labelWithString: "摄影 · Unsplash")
        credit.font = .systemFont(ofSize: 10)
        credit.textColor = ink.withAlphaComponent(0.55)
        credit.alignment = .right
        credit.frame = NSRect(x: 460, y: 30, width: 145, height: 18)
        addSubview(credit)
    }

    required init?(coder: NSCoder) { nil }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.saveGraphicsState()
        let inside = bounds
        NSBezierPath(roundedRect: inside, xRadius: 32, yRadius: 32).addClip()
        if let photograph {
            let size = photograph.size
            let scale = max(inside.width / size.width, inside.height / size.height)
            let crop = NSRect(x: (size.width - inside.width / scale) / 2,
                              y: (size.height - inside.height / scale) / 2,
                              width: inside.width / scale, height: inside.height / scale)
            photograph.draw(in: inside, from: crop, operation: .sourceOver, fraction: 1,
                            respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high])
        } else {
            NSGradient(starting: NSColor(calibratedRed: 1, green: 0.90, blue: 0.67, alpha: 1),
                       ending: gold)?.draw(in: inside, angle: 75)
        }
        NSColor(calibratedRed: 1, green: 0.86, blue: 0.57, alpha: 0.12).setFill()
        inside.fill()
        NSGradient(starting: NSColor(calibratedRed: 1, green: 0.91, blue: 0.72, alpha: 0.98),
                   ending: NSColor(calibratedRed: 1, green: 0.95, blue: 0.82, alpha: 0.03))?
            .draw(from: NSPoint(x: 0, y: 0), to: NSPoint(x: 0, y: 410), options: [.drawsBeforeStartingLocation, .drawsAfterEndingLocation])
        NSColor(calibratedRed: 1, green: 0.96, blue: 0.84, alpha: 0.62).setFill()
        NSBezierPath(roundedRect: NSRect(x: 24, y: 398, width: 116, height: 34), xRadius: 17, yRadius: 17).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    func animateMorningLight() {
        guard let layer else { return }
        for index in 0..<18 {
            let mote = CALayer()
            let side = CGFloat(2 + index % 3)
            let x = CGFloat(34 + (index * 97) % 560)
            let y = CGFloat(208 + (index * 37) % 190)
            mote.frame = CGRect(x: x, y: y, width: side, height: side)
            mote.cornerRadius = side / 2
            mote.backgroundColor = gold.withAlphaComponent(0.8).cgColor
            mote.shadowColor = gold.cgColor
            mote.shadowOpacity = 0.7
            mote.shadowRadius = 5
            mote.opacity = 0
            layer.addSublayer(mote)
            let drift = CABasicAnimation(keyPath: "position")
            drift.fromValue = NSValue(point: NSPoint(x: x, y: y))
            drift.toValue = NSValue(point: NSPoint(x: x + 10, y: y + 38))
            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0, 0.8, 0.5, 0]
            fade.keyTimes = [0, 0.25, 0.7, 1]
            let group = CAAnimationGroup()
            group.animations = [drift, fade]
            group.duration = 3.2 + Double(index % 4) * 0.25
            group.beginTime = CACurrentMediaTime() + Double(index % 5) * 0.12
            mote.add(group, forKey: "sunDust")
        }
    }
}
