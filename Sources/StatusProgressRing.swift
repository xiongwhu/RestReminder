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

struct StatusRingPresentation: Equatable {
    enum Mode { case work, rest, paused, protected }
    let progress: Double
    let mode: Mode

    static func make(startedAt: TimeInterval?, now: TimeInterval, interval: TimeInterval,
                     idle: TimeInterval, restThreshold: TimeInterval,
                     paused: Bool, suppressed: Bool, strongRest: Bool) -> StatusRingPresentation {
        func fraction(_ amount: Double, _ total: Double) -> Double {
            guard amount.isFinite, total.isFinite, total > 0 else { return 0 }
            return min(1, max(0, amount / total))
        }
        let work = startedAt.map { fraction(now - $0, interval) } ?? 0
        if paused { return StatusRingPresentation(progress: work, mode: .paused) }
        if suppressed { return StatusRingPresentation(progress: work, mode: .protected) }
        if strongRest || startedAt == nil {
            return StatusRingPresentation(progress: fraction(idle, restThreshold), mode: .rest)
        }
        return StatusRingPresentation(progress: work, mode: .work)
    }

    var symbol: String {
        switch mode {
        case .work: return "sun.max.fill"
        case .rest: return "leaf.fill"
        case .paused: return "pause.fill"
        case .protected: return "shield.fill"
        }
    }

    var accessibilityDescription: String {
        let label: String
        switch mode {
        case .work: label = "工作进度"
        case .rest: label = "休息进度"
        case .paused: label = "提醒已暂停"
        case .protected: label = "免打扰保护中"
        }
        return "歇一会儿，\(label)，\(Int((progress * 100).rounded()))%"
    }
}

/// A template image follows the system menu-bar appearance and selected-item contrast.
enum StatusProgressRing {
    static func image(for presentation: StatusRingPresentation) -> NSImage {
        let image = NSImage(size: NSSize(width: 22, height: 22), flipped: false) { _ in
            let center = NSPoint(x: 11, y: 11)
            let track = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 18, height: 18))
            track.lineWidth = 2
            NSColor.black.withAlphaComponent(0.20).setStroke()
            track.stroke()
            if presentation.progress > 0 {
                let arc = NSBezierPath()
                arc.lineWidth = 2
                arc.lineCapStyle = .round
                arc.appendArc(withCenter: center, radius: 9, startAngle: 90,
                              endAngle: 90 - 360 * presentation.progress, clockwise: true)
                NSColor.black.setStroke()
                arc.stroke()
            }
            if let symbol = NSImage(systemSymbolName: presentation.symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(paletteColors: [.black])) {
                symbol.draw(in: NSRect(x: 6, y: 6, width: 10, height: 10))
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = presentation.accessibilityDescription
        return image
    }
}
