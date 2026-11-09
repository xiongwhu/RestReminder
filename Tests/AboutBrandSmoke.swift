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

/// Synthetic settings only: no AppDelegate, preferences, history, timers, or real URL opening.
@main
@MainActor
struct AboutBrandSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var openedURLs: [URL] = []
        let about = AboutBrandView(openWebsite: { openedURLs.append($0) })
        let fixture = SettingsFixture(about: about)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 770),
                              styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = "歇一会儿 · 设置（布局预览）"
        window.isReleasedWhenClosed = false
        window.contentView = SettingsPreviewBackground(frame: NSRect(x: 0, y: 0, width: 460, height: 770))
        let scroll = SettingsScrollContainer(stack: fixture.stack)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!
        content.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: content.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: content.bottomAnchor)
        ])
        precondition(openedURLs.isEmpty, "Constructing Settings must not open the website")

        DispatchQueue.main.async {
            window.center()
            window.makeKeyAndOrderFront(nil)
            var collapsedHeight: CGFloat?
            for (height, expanded) in [(770.0, false), (480.0, false), (770.0, true), (480.0, true), (480.0, false)] {
                fixture.setMaintenanceExpanded(expanded)
                window.setContentSize(NSSize(width: 460, height: height))
                settle(window)
                verifyLabels(about)
                verifyLayout(scroll, stack: fixture.stack, about: about, mustScroll: height == 480)
                if height == 480 && !expanded {
                    if let collapsedHeight {
                        precondition(abs(scroll.preferredContentHeight - collapsedHeight) < 1,
                                     "Collapsing maintenance must restore its natural height")
                    } else { collapsedHeight = scroll.preferredContentHeight }
                }
                if expanded, let collapsedHeight {
                    precondition(scroll.preferredContentHeight > collapsedHeight + 60,
                                 "Natural content height must include expanded maintenance")
                }
                print("PASS: 460×\(Int(height)), maintenance \(expanded ? "expanded" : "collapsed"), document height \(Int(scroll.documentView!.frame.height))")
            }

            // Dark appearance uses the same native controls and dynamic label colors.
            window.appearance = NSAppearance(named: .darkAqua)
            settle(window)
            verifyLayout(scroll, stack: fixture.stack, about: about, mustScroll: true)
            window.appearance = NSAppearance(named: .aqua)
            fixture.setMaintenanceExpanded(false)
            settle(window)
            // Fit the entire synthetic settings document in the preview, including its footer.
            let previewHeight = ceil(scroll.preferredContentHeight)
            window.setContentSize(NSSize(width: 460, height: previewHeight))
            settle(window)
            scroll.scrollToTop()
            capture(content, to: "build/about-settings-preview.png")

            precondition(openedURLs.isEmpty, "Layout, scrolling, and rendering must not open the website")
            let website = descendants(of: about).compactMap { $0 as? NSButton }.first!
            website.performClick(nil)
            precondition(openedURLs == [URL(string: "https://www.racio.chat")!],
                         "One actual button action must invoke exactly one callback with the HTTPS website")
            print("PASS: About labels/accessibility, footer fitting, native light/dark layout, scrolling to every control, live expansion/collapse, and one injected website callback; no real browsing or application data")
            window.orderOut(nil)
            app.terminate(nil)
        }
        app.run()
    }

    static func settle(_ window: NSWindow) {
        // One follow-up layout resolves multiline heights after a width/gutter change.
        window.contentView!.layoutSubtreeIfNeeded()
        window.contentView!.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    static func verifyLabels(_ about: AboutBrandView) {
        let views = descendants(of: about)
        let labels = views.compactMap { ($0 as? NSTextField)?.stringValue.replacingOccurrences(of: "\n", with: "") }
        for required in ["关于歇一会儿", "RestReminder by RaCIO",
                         "Copyright (c) 2026 迈润智人", "CPAL-1.0"] {
            precondition(labels.contains(required), "Missing About text: \(required)")
        }
        precondition(!labels.contains("迈润智人 RaCIO") &&
                     !labels.contains(where: { $0.contains("广州迈润网络科技有限公司") || $0.contains("企业 AI 落地") }),
                     "The removed promotional block and company full name must not remain in About")
        let buttons = views.compactMap { $0 as? NSButton }
        precondition(buttons.count == 1 && buttons[0].title == "访问官网 racio.chat ↗", "One clear website button")
        precondition(buttons[0].toolTip == "https://www.racio.chat", "Website tooltip must expose the exact HTTPS URL")
        precondition(buttons[0].accessibilityLabel() == "访问迈润智人 RaCIO 官网" &&
                     about.accessibilityRole() == .group && about.accessibilityLabel() == "关于歇一会儿",
                     "Native footer group and button must have useful accessible names")
    }

    static func verifyLayout(_ scroll: SettingsScrollContainer, stack: NSStackView,
                             about: AboutBrandView, mustScroll: Bool) {
        guard let document = scroll.documentView else { fatalError("Missing settings document") }
        let clip = scroll.contentView
        precondition(document.isFlipped, "The settings document must start at its top")
        precondition(!scroll.hasHorizontalScroller && scroll.horizontalScrollElasticity == .none,
                     "Settings must never need horizontal scrolling")
        precondition(abs(document.frame.width - clip.bounds.width) < 1, "Document width must follow clip width")
        precondition(abs(document.frame.height - scroll.preferredContentHeight) < 1,
                     "Document height must follow content rather than stretch to the viewport")
        if mustScroll {
            precondition(document.frame.height > clip.bounds.height + 1, "Tall settings must remain scrollable")
        }
        let stackRect = stack.convert(stack.bounds, to: document)
        precondition(abs(stackRect.minX - 26) < 1 && abs(stackRect.minY - 24) < 1 &&
                     abs(document.bounds.width - stackRect.maxX - 26) < 1,
                     "The helper must preserve 24-point top and 26-point side insets")
        precondition(document.bounds.maxY - stackRect.maxY >= 23, "The footer needs a bottom inset")
        precondition(about.frame.height > 50 && about.frame.height < 140 && about.fittingSize.height > 50,
                     "The shortened About footer must fit its remaining heading, link, attribution and copyright")

        // Every leaf control, including the last copyright line, can be brought wholly into view.
        let controls = descendants(of: stack).filter {
            !$0.isHiddenOrHasHiddenAncestor && ($0 is NSTextField || $0 is NSButton)
        }
        for control in controls {
            let rect = control.convert(control.bounds, to: document)
            precondition(rect.width > 0 && rect.height > 0 &&
                         rect.minX >= 18 && rect.maxX <= document.bounds.maxX - 18 &&
                         rect.minY >= 23 && rect.maxY <= document.bounds.maxY - 23,
                         "Control is clipped outside its document: \(control)")
            _ = document.scrollToVisible(rect)
            scroll.reflectScrolledClipView(clip)
            precondition(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(rect),
                         "Cannot scroll an entire settings control into view: \(control)")
        }
        let website = descendants(of: about).compactMap { $0 as? NSButton }.first!
        let websiteRect = website.convert(website.bounds, to: scroll)
        if let scroller = scroll.verticalScroller, !scroller.isHidden {
            precondition(!websiteRect.intersects(scroller.frame), "The scrollbar must not cover the website button")
        }
        scroll.scrollToTop()
        precondition(abs(scroll.documentVisibleRect.minY) < 1, "scrollToTop must restore the initial top position")
        precondition(!about.hasAmbiguousLayout, "The About footer must have a determined layout")
    }

    static func descendants(of view: NSView) -> [NSView] {
        view.subviews.flatMap { [$0] + descendants(of: $0) }
    }

    static func capture(_ view: NSView, to path: String) {
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Cannot allocate settings preview")
        }
        view.cacheDisplay(in: view.bounds, to: image)
        // The standard content view is transparent; include the window's native backdrop.
        let composite = NSImage(size: view.bounds.size)
        composite.lockFocus()
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
            image.draw(in: view.bounds)
        }
        composite.unlockFocus()
        guard let tiff = composite.tiffRepresentation,
              let representation = NSBitmapImageRep(data: tiff),
              let png = representation.representation(using: .png, properties: [:]) else {
            fatalError("Cannot encode settings preview")
        }
        do { try png.write(to: URL(fileURLWithPath: path)) }
        catch { fatalError("Cannot save settings preview: \(error)") }
    }
}

private final class SettingsPreviewBackground: NSView {
    override var isOpaque: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        dirtyRect.fill()
    }
}

@MainActor
private final class SettingsFixture {
    let stack = NSStackView()
    let maintenanceBody = NSStackView()
    let maintenanceToggle = NSButton(title: "▸ 预览与维护", target: nil, action: nil)

    init(about: AboutBrandView) {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        let title = NSTextField(labelWithString: "给专注留一点呼吸的空间 🌿")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        stack.addArrangedSubview(title)
        addText("在菜单栏安静陪伴你，到时间轻轻提醒。", size: 13)
        for (title, value) in [("连续使用多久后提醒", "30"), ("无操作多久算已休息", "2")] {
            let field = NSTextField(string: value)
            field.alignment = .right
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
            let row = NSStackView(views: [NSTextField(labelWithString: title), field, NSTextField(labelWithString: "分钟")])
            row.spacing = 12
            stack.addArrangedSubview(row)
        }
        let protection = NSButton(checkboxWithTitle: "会议/演示自动避让", target: nil, action: nil)
        protection.state = .on
        stack.addArrangedSubview(protection)
        let login = NSButton(checkboxWithTitle: "登录后自动启动", target: nil, action: nil)
        let loginRow = NSStackView(views: [login, NSButton(title: "系统登录项…", target: nil, action: nil)])
        loginRow.spacing = 18
        stack.addArrangedSubview(loginRow)
        addText("尚未开启登录后自动启动。", size: 12)
        addText("鼠标或键盘有活动就算在使用，短暂停顿继续计时。达到休息时长、睡眠或切换用户后重新计时。\n\n不记录按键或鼠标位置。音频免打扰需系统音频录制权限；仅在内存计算音量，不保存、上传声音。", size: 12)
        addText("修改后自动保存，无需额外操作。", size: 12)
        let divider = NSBox()
        divider.boxType = .separator
        stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        maintenanceToggle.isBordered = false
        maintenanceToggle.alignment = .left
        maintenanceToggle.font = .systemFont(ofSize: 13, weight: .medium)
        stack.addArrangedSubview(maintenanceToggle)
        maintenanceBody.orientation = .vertical
        maintenanceBody.alignment = .leading
        maintenanceBody.spacing = 10
        let previewLabel = NSTextField(labelWithString: "试一试提醒效果")
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .secondaryLabelColor
        maintenanceBody.addArrangedSubview(previewLabel)
        let previews = NSStackView(views: ["休息提醒…", "元气太阳 ☀️", "休息建议 🌱"].map {
            NSButton(title: $0, target: nil, action: nil)
        })
        previews.spacing = 8
        maintenanceBody.addArrangedSubview(previews)
        maintenanceBody.addArrangedSubview(NSButton(title: "重新连接音频检测", target: nil, action: nil))
        let hint = NSTextField(wrappingLabelWithString: "仅在音频检测异常时尝试重新连接，不会改变系统音量。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        maintenanceBody.addArrangedSubview(hint)
        stack.addArrangedSubview(maintenanceBody)
        maintenanceBody.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        hint.widthAnchor.constraint(equalTo: maintenanceBody.widthAnchor).isActive = true
        setMaintenanceExpanded(false)
        stack.addArrangedSubview(about)
        about.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }

    func setMaintenanceExpanded(_ expanded: Bool) {
        maintenanceBody.isHidden = !expanded
        maintenanceToggle.title = expanded ? "▾ 预览与维护" : "▸ 预览与维护"
    }

    private func addText(_ text: String, size: CGFloat) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: size)
        label.textColor = .secondaryLabelColor
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
}
