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

@main struct StrongRestSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let page = StrongRestWindow(photoURL: URL(fileURLWithPath: "Resources/fresh-green.jpg"))
        var emergencyCount = 0
        var endCount = 0
        page.onEmergency = { emergencyCount += 1; page.hide() }
        page.onEndVoluntary = { endCount += 1; page.hide() }
        DispatchQueue.main.async {
            page.update(remaining: 221, total: 300, workSeconds: 2700)
            page.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                let windows = app.windows.filter { $0.isVisible && $0.title == "认真休息一下" }
                guard page.isVisible, let window = windows.first, let view = window.contentView else {
                    fatalError("Missing full-screen rest page")
                }
                assertScreenCoverage(windows)
                let originalViews = windows.compactMap { $0.contentView }.map(ObjectIdentifier.init)
                window.cancelOperation(nil)
                window.performClose(nil)
                guard page.isVisible else { fatalError("Escape and ordinary close must not dismiss rest") }
                guard labels(in: view).contains(where: { $0.stringValue == "03:41" }),
                      let button = descendants(view).compactMap({ $0 as? NSButton }).first,
                      let progress = descendants(view).compactMap({ $0 as? NSProgressIndicator }).first,
                      !progress.isHidden else { fatalError("Countdown didn't update") }
                writeSnapshot(view, path: "build/strong-rest-preview.png")

                page.update(remaining: 0, total: 1, workSeconds: 0, advice: RestAdvice.all[1],
                            mode: .voluntary, elapsed: 125)
                assertScreenCoverage(windows)
                guard windows.allSatisfy({ $0.title == "正在休息" && $0.accessibilityLabel()?.contains("已休息时间") == true }),
                      originalViews == windows.compactMap({ $0.contentView }).map(ObjectIdentifier.init) else {
                    fatalError("Mode changes must update all windows without replacing their native views")
                }
                assertVoluntary(view, expectedClock: "02:05")
                writeSnapshot(view, path: "build/voluntary-rest-preview.png")

                page.update(remaining: 0, total: 1, workSeconds: 0, mode: .voluntary, elapsed: 125.99)
                assertVoluntary(view, expectedClock: "02:05")
                page.update(remaining: 0, total: 1, workSeconds: 0, mode: .voluntary, elapsed: 3_599.99)
                assertVoluntary(view, expectedClock: "59:59")
                page.update(remaining: 0, total: 1, workSeconds: 0, mode: .voluntary, elapsed: 3_600)
                assertVoluntary(view, expectedClock: "01:00:00")
                guard elapsedClock(in: view).accessibilityValue() == "01:00:00" else {
                    fatalError("Hour elapsed time must expose its visible value to accessibility")
                }
                assertCompactLayouts(view)

                for elapsed: TimeInterval in [-1, -.infinity, .infinity, .nan] {
                    page.update(remaining: 0, total: 1, workSeconds: 0, mode: .voluntary, elapsed: elapsed)
                    assertVoluntary(view, expectedClock: "00:00")
                }
                page.update(remaining: 0, total: 1, workSeconds: 0, mode: .voluntary,
                            elapsed: TimeInterval.greatestFiniteMagnitude)
                let largeClock = elapsedClock(in: view).stringValue.split(separator: ":")
                guard largeClock.count == 3, let hours = Int64(largeClock[0]), hours > 1_000_000_000,
                      let minutes = Int(largeClock[1]), (0..<60).contains(minutes),
                      let seconds = Int(largeClock[2]), (0..<60).contains(seconds) else {
                    fatalError("Very large finite elapsed values must remain safe positive clocks")
                }
                assertCompactLayouts(view)
                guard page.isVisible, emergencyCount == 0, endCount == 0 else {
                    fatalError("Voluntary rest must stay open regardless of elapsed time or countdown target")
                }

                // Omit the new arguments to exercise source compatibility and default mode restoration.
                page.update(remaining: 90, total: 300, workSeconds: 0, advice: RestAdvice.all[0])
                let restoredLabels = labels(in: view).map { $0.stringValue }
                guard windows.allSatisfy({ $0.title == "认真休息一下" && $0.accessibilityLabel() == "休息提醒，连续离开键鼠后完成休息" }),
                      restoredLabels.contains("01:30"),
                      restoredLabels.contains("暂时放下工作 · 好好照顾自己"),
                      restoredLabels.contains("已经努力很久了，这次认真休息一下。"),
                      restoredLabels.contains("护眼休息：\(RestAdvice.all[0].message)"),
                      restoredLabels.contains("已经提醒过 3 次，这次让身体真正休息。"),
                      restoredLabels.contains(where: { $0.contains("连续离开键鼠 5 分钟") }),
                      !progress.isHidden, progress.isAccessibilityElement(),
                      progress.accessibilityLabel() == "连续休息完成进度",
                      abs(progress.doubleValue - 0.7) < 0.0001,
                      button.title == "有急事，再给我 5 分钟",
                      button.accessibilityLabel() == "有急事，再给我 5 分钟",
                      button.accessibilityHelp() == "推迟本次休息，继续工作五分钟。",
                      labels(in: view).contains(where: { $0.accessibilityLabel() == "连续休息剩余时间" }) else {
                    fatalError("Returning to countdown must restore labels, progress, accessibility and emergency action")
                }
                button.performClick(nil)
                guard emergencyCount == 1, endCount == 0, !page.isVisible else {
                    fatalError("Countdown button must only invoke emergency and dismiss all pages")
                }

                page.update(remaining: 0, total: 1, workSeconds: 0, mode: .voluntary, elapsed: 125)
                page.show()
                assertScreenCoverage(windows)
                for window in windows {
                    guard let content = window.contentView else { fatalError("Missing voluntary screen content") }
                    assertVoluntary(content, expectedClock: "02:05")
                }
                button.performClick(nil)
                guard emergencyCount == 1, endCount == 1, !page.isVisible else {
                    fatalError("Voluntary end must invoke its own callback and dismiss all pages")
                }
                print("PASS: native screen coverage, countdown and voluntary rendering, elapsed flooring and hour formatting, safe elapsed inputs, compact layouts, mode roundtrip, Escape/close retention and distinct callbacks")
                app.terminate(nil)
            }
        }
        app.run()
    }

    static func assertScreenCoverage(_ windows: [NSWindow]) {
        guard windows.count == NSScreen.screens.count, windows.allSatisfy({ $0.isVisible }) else {
            fatalError("Full-screen pages must cover all connected screens")
        }
        for screen in NSScreen.screens {
            guard windows.contains(where: { $0.frame == screen.frame }) else {
                fatalError("A full native display is uncovered")
            }
        }
    }

    static func assertVoluntary(_ view: NSView, expectedClock: String) {
        let visibleLabels = labels(in: view).filter { !$0.isHiddenOrHasHiddenAncestor }.map { $0.stringValue }
        let forbidden = ["倒计时", "剩余", "连续离开键鼠", "才算完成", "已经提醒过", "重新计时", "目标"]
        guard elapsedClock(in: view).stringValue == expectedClock,
              visibleLabels.contains("休息一下，慢慢放松。"),
              visibleLabels.contains(where: { $0.contains("已休息") }),
              visibleLabels.contains(where: { $0.contains("计时持续到你结束休息") && $0.contains("键鼠操作不会重置") }),
              !visibleLabels.contains(where: { text in forbidden.contains(where: { text.contains($0) }) }),
              let progress = descendants(view).compactMap({ $0 as? NSProgressIndicator }).first,
              progress.isHidden, !progress.isAccessibilityElement(), progress.accessibilityLabel() == nil,
              let button = descendants(view).compactMap({ $0 as? NSButton }).first,
              button.title == "结束休息", button.accessibilityLabel() == "结束休息",
              button.accessibilityHelp() == "结束本次自主休息，返回之前的工作。" else {
            fatalError("Voluntary rest must show elapsed time, end action and ongoing timing without target wording or progress")
        }
    }

    static func assertCompactLayouts(_ view: NSView) {
        let originalFrame = view.frame
        defer { view.frame = originalFrame; view.needsLayout = true; view.layoutSubtreeIfNeeded() }
        for size in [NSSize(width: 640, height: 480), NSSize(width: 800, height: 600)] {
            view.setFrameSize(size)
            view.needsLayout = true
            view.layoutSubtreeIfNeeded()
            for control in view.subviews where !control.isHidden {
                guard view.bounds.contains(control.frame) else { fatalError("Compact native layout clips a control") }
            }
            let clock = elapsedClock(in: view)
            let clockWidth = (clock.stringValue as NSString).size(withAttributes: [.font: clock.font!]).width
            guard clockWidth <= clock.bounds.width + 1 else { fatalError("Compact native layout clips elapsed digits") }
        }
    }

    static func writeSnapshot(_ view: NSView, path: String) {
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Cannot render full-screen view")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Missing preview PNG") }
        do { try png.write(to: URL(fileURLWithPath: path)) }
        catch { fatalError("Cannot write full-screen preview: \(error)") }
    }

    static func elapsedClock(in view: NSView) -> NSTextField {
        guard let clock = labels(in: view).first(where: { $0.accessibilityLabel() == "已休息时间" }) else {
            fatalError("Missing accessible elapsed time")
        }
        return clock
    }

    static func labels(in view: NSView) -> [NSTextField] {
        descendants(view).compactMap { $0 as? NSTextField }
    }

    static func descendants(_ view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
