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

/// An explicit rest session, independent of keyboard idle and automatic reminder strikes.
/// The owner supplies a sleep-inclusive monotonic clock; no stopped-app time is restored.
struct VoluntaryRestSession {
    private(set) var startedAt: TimeInterval?
    var isActive: Bool { startedAt != nil }

    @discardableResult
    mutating func start(at now: TimeInterval) -> Bool {
        guard !isActive, now.isFinite, now >= 0 else { return false }
        startedAt = now
        return true
    }

    func elapsed(at now: TimeInterval) -> TimeInterval {
        guard let startedAt, now.isFinite, now >= 0 else { return 0 }
        return max(0, now - startedAt)
    }

    @discardableResult
    mutating func finish(at now: TimeInterval) -> TimeInterval? {
        guard isActive else { return nil }
        let duration = elapsed(at: now)
        startedAt = nil
        return duration
    }
}
