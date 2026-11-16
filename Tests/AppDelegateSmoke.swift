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

/// main.swift calls this entry only with REMINDER_UI_SMOKE; production startup is excluded.
/// Uses the real settings controller, in-memory history and an owned preference suite.
@MainActor
struct AppDelegateSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let suite = "RestReminder.AppDelegateSmoke.\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        preferences.set(45.5, forKey: "intervalMinutes")
        preferences.set(3.0, forKey: "restMinutes")
        let delegate = AppDelegate(history: ActivityHistory(storageURL: nil), preferences: preferences)
        // Do not set NSApp.delegate or invoke applicationDidFinishLaunching:
        // no production writer lock, capture, activity sampling or login registration.
        DispatchQueue.main.async {
            _ = delegate.perform(NSSelectorFromString("showSettings"))
            guard let window = app.windows.first(where: { $0.title == "歇一会儿 · 设置" }),
                  let content = window.contentView,
                  let scroll = descendants(content).compactMap({ $0 as? SettingsScrollContainer }).first else {
                fatalError("Missing real settings window or scroll container")
            }
            let labels = descendants(content).compactMap { ($0 as? NSTextField)?.stringValue }
            precondition(labels.contains(where: { $0.contains("菜单栏") }) &&
                         labels.contains(where: { ($0.contains("3 次") || $0.contains("三次")) && $0.contains("全屏") }) &&
                         labels.contains(where: { $0.contains("应急") || $0.contains("有急事") }),
                         "Settings must explain the menu-bar entry, escalation and emergency exit")
            let fields = descendants(content).compactMap { $0 as? NSTextField }.filter { $0.isEditable }
            precondition(fields.count == 2 && fields[0].doubleValue == 45.5 && fields[1].doubleValue == 3,
                         "Settings must preserve the injected valid timing preferences")
            guard let maintenance = descendants(content).compactMap({ $0 as? NSButton })
                .first(where: { $0.title.contains("预览与维护") }) else { fatalError("Missing maintenance control") }
            for expanded in [false, true, false] {
                if maintenance.title.hasPrefix("▾") != expanded { maintenance.performClick(nil) }
                for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                    window.appearance = NSAppearance(named: appearance)
                    window.setContentSize(NSSize(width: 460, height: 480))
                    settle(window)
                    verifyScrollableControls(scroll)
                }
            }
            window.setContentSize(NSSize(width: 460, height: 480))
            scroll.scrollToTop()
            fields[0].stringValue = "0"
            delegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: fields[0]))
            settle(window)
            guard let error = descendants(content).compactMap({ $0 as? NSTextField })
                .first(where: { $0.stringValue.contains("无效输入未保存") }), let document = scroll.documentView else {
                fatalError("Invalid duration must show an unsaved-value explanation")
            }
            precondition(scroll.documentVisibleRect.contains(error.convert(error.bounds, to: document)),
                         "Timing validation must be visible beside the fields in a small top-scrolled window")
            precondition(preferences.double(forKey: "intervalMinutes") == 45.5,
                         "Invalid input must retain the saved timing preference")
            fields[0].doubleValue = 45.5
            delegate.controlTextDidEndEditing(Notification(name: NSControl.textDidEndEditingNotification, object: fields[0]))
            for (appearance, name) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(NSSize(width: 460, height: ceil(scroll.preferredContentHeight)))
                settle(window)
                scroll.scrollToTop()
                capture(content, to: "build/settings-\(name).png")
            }
            precondition(preferences.double(forKey: "intervalMinutes") == 45.5 &&
                         preferences.double(forKey: "restMinutes") == 3,
                         "Showing and resizing settings cannot change valid preferences")
            // Teardown must not turn late editing/close notifications into saves
            // after the owned preference domain has already been removed.
            fields.forEach { $0.delegate = nil }
            window.delegate = nil
            window.makeFirstResponder(nil)
            window.orderOut(nil)
            preferences.removePersistentDomain(forName: suite)
            print("PASS: real AppDelegate settings, onboarding rules, valid preferences, 460×480 light/dark scrolling and maintenance expansion; isolated data and no audio capture/login registration")
            app.terminate(nil)
        }
        app.run()
        withExtendedLifetime(delegate) { }
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }

    static func settle(_ window: NSWindow) {
        window.contentView?.layoutSubtreeIfNeeded()
        window.contentView?.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
    }

    static func verifyScrollableControls(_ scroll: SettingsScrollContainer) {
        guard let document = scroll.documentView else { fatalError("Missing settings document") }
        precondition(document.frame.height > scroll.contentView.bounds.height,
                     "Small settings window must scroll to all content")
        for view in descendants(document) where !view.isHiddenOrHasHiddenAncestor && (view is NSTextField || view is NSButton) {
            let rect = view.convert(view.bounds, to: document)
            precondition(rect.width > 0 && rect.height > 0 && document.bounds.insetBy(dx: -1, dy: -1).contains(rect),
                         "A visible control must fit in the document: \(view)")
            _ = document.scrollToVisible(rect)
            scroll.reflectScrolledClipView(scroll.contentView)
            precondition(scroll.documentVisibleRect.insetBy(dx: -1, dy: -1).contains(rect),
                         "A settings control must be fully reachable by scrolling: \(view)")
        }
        scroll.scrollToTop()
    }

    static func capture(_ view: NSView, to path: String) {
        guard let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot allocate native preview") }
        view.cacheDisplay(in: view.bounds, to: image)
        let composite = NSImage(size: view.bounds.size)
        composite.lockFocus()
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            NSColor.windowBackgroundColor.setFill()
            view.bounds.fill()
            image.draw(in: view.bounds)
        }
        composite.unlockFocus()
        guard let tiff = composite.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode native preview") }
        do { try png.write(to: URL(fileURLWithPath: path), options: .atomic) }
        catch { fatalError("Cannot save native preview: \(error)") }
    }
}
