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

struct RestAdvice: Equatable {
    let id: String
    let category: String
    let title: String
    let message: String

    static let all: [RestAdvice] = [
        RestAdvice(id: "eyes", category: "护眼休息", title: "让眼睛看看远处",
                   message: "把视线移向远处约 20 秒，慢慢眨眼，再继续离屏休息。"),
        RestAdvice(id: "water", category: "补充水分", title: "起身喝几口水",
                   message: "离开座位倒一杯水，按需要小口喝几口。"),
        RestAdvice(id: "shoulders", category: "舒展肩背", title: "让肩膀轻松一点",
                   message: "放松肩膀，轻轻伸展手臂和肩背，以舒适为准。"),
        RestAdvice(id: "walk", category: "起来走走", title: "给双腿一点活动时间",
                   message: "暂时离开屏幕，慢慢走一小圈，换个姿势。"),
        RestAdvice(id: "breathing", category: "放松呼吸", title: "慢下来，换一口气",
                   message: "放下手里的事，做几次自然、缓慢的呼吸。"),
        RestAdvice(id: "hands", category: "放松双手", title: "让手腕也歇一会儿",
                   message: "松开鼠标，放松手掌，轻轻活动手指和手腕。")
    ]
}

/// A deterministic cycle avoids immediate repeats and needs no network or personal data.
struct RestAdviceCycle {
    private(set) var nextIndex: Int

    init(nextIndex: Int = 0) {
        self.nextIndex = max(0, nextIndex) % RestAdvice.all.count
    }

    mutating func next() -> RestAdvice {
        let advice = RestAdvice.all[nextIndex]
        nextIndex = (nextIndex + 1) % RestAdvice.all.count
        return advice
    }
}
