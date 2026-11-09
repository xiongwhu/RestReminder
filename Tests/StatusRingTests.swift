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

@main struct StatusRingTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }

    static func main() {
        func state(_ time: Double, start: Double? = 100, interval: Double = 1800,
                   idle: Double = 0, paused: Bool = false, protected: Bool = false,
                   strong: Bool = false) -> StatusRingPresentation {
            StatusRingPresentation.make(startedAt: start, now: time, interval: interval,
                idle: idle, restThreshold: 300, paused: paused, suppressed: protected, strongRest: strong)
        }
        expect(state(100).progress == 0, "A fresh work cycle starts empty")
        expect(state(550).progress == 0.25, "Work fills in proportion to configured interval")
        expect(state(1000).progress == 0.5, "Halfway is half a ring")
        expect(state(2200).progress == 1, "Overdue work remains full, including ordinary snoozes")
        expect(state(550, interval: 900).progress == 0.5, "Current settings control the scale")
        expect(state(90).progress == 0, "Rollback cannot create a negative arc")
        expect(state(100, interval: .nan).progress == 0, "Invalid intervals remain drawable")
        expect(state(1000, paused: true).mode == .paused, "Paused mode is visibly distinct")
        expect(state(1000, protected: true).mode == .protected, "Protected mode uses a shield")
        expect(state(1000, protected: true).progress == 0.5, "Protection preserves underlying work progress")
        expect(state(1000, start: nil, idle: 300).mode == .rest, "Completed rest is a leaf")
        expect(state(1000, start: nil, idle: 300).progress == 1, "Completed rest has full rest progress")
        expect(state(1100, start: 1100).progress == 0, "Returning to work begins a new empty cycle")
        expect(state(1000, idle: 150, strong: true).progress == 0.5, "Strong rest shows continuous idle progress")
        expect(state(1000, idle: 0, strong: true).progress == 0, "New input resets rest progress")
        expect(state(1000, idle: 150, protected: true, strong: true).mode == .protected,
               "Protection is visible while a strong-rest page is hidden")
        let samples: [(String, StatusRingPresentation)] = [
            ("0%", state(100)), ("25%", state(550)), ("50%", state(1000)), ("100%", state(1900)),
            ("休息", state(1000, start: nil, idle: 150)), ("暂停", state(1000, paused: true)),
            ("免打扰", state(1000, protected: true)), ("休息完成", state(1000, start: nil, idle: 300))
        ]
        let preview = NSImage(size: NSSize(width: 520, height: 180))
        preview.lockFocus()
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: 520, height: 180).fill()
        for (index, sample) in samples.enumerated() {
            let image = StatusProgressRing.image(for: sample.1)
            expect(image.isTemplate && image.size == NSSize(width: 22, height: 22), "Native-sized template image")
            expect(image.accessibilityDescription?.contains("歇一会儿") == true, "Accessible description")
            let x = CGFloat(index % 4) * 130 + 43
            let y: CGFloat = index < 4 ? 116 : 26
            image.draw(in: NSRect(x: x, y: y, width: 44, height: 44))
            let text = sample.0 as NSString
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.black
            ]
            let size = text.size(withAttributes: attributes)
            text.draw(at: NSPoint(x: x + 22 - size.width / 2, y: y - 18), withAttributes: attributes)
        }
        preview.unlockFocus()
        guard let tiff = preview.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("Render preview") }
        do { try png.write(to: URL(fileURLWithPath: "build/status-ring-preview.png")) }
        catch { fatalError("Save preview: \(error)") }
        print("PASS: ring progress, interval changes, overdue/rest reset, pause/protection modes, invalid values, template rendering")
    }
}
