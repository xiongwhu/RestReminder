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

@main struct RestAdviceTests {
    static func expect(_ value: @autoclosure () -> Bool, _ message: String) {
        guard value() else { fatalError(message) }
    }

    static func main() {
        var cycle = RestAdviceCycle()
        let firstPass = (0..<RestAdvice.all.count).map { _ in cycle.next() }
        expect(Set(firstPass.map(\.id)).count == 6, "All six rest categories appear before repeating")
        expect(firstPass == RestAdvice.all, "Rotation is deterministic")
        expect(cycle.next() == firstPass[0], "Complete cycle wraps to its start")
        var restored = RestAdviceCycle(nextIndex: cycle.nextIndex)
        expect(restored.next() == cycle.next(), "Restored next index continues the previous sequence")
        var preview = RestAdviceCycle()
        let actualIndex = restored.nextIndex
        for _ in 0..<20 { _ = preview.next() }
        expect(restored.nextIndex == actualIndex, "A preview cycle cannot advance automatic suggestions")
        var negative = RestAdviceCycle(nextIndex: -1)
        expect(negative.next() == RestAdvice.all[0], "Invalid stored negative index is recovered")
        var large = RestAdviceCycle(nextIndex: Int.max)
        expect(RestAdvice.all.contains(large.next()), "Large stored indices remain in range")
        expect(RestAdvice.all.allSatisfy { !$0.title.isEmpty && !$0.message.isEmpty && !$0.category.isEmpty },
               "Every suggestion has visible and accessible copy")
        expect(RestAdvice.all.allSatisfy { $0.title.count <= 18 && $0.message.count <= 36 && !$0.message.contains("\n") },
               "Suggestion copy fits the compact card's title and single-line body slot")
        print("PASS: six advice categories, deterministic rotation, index restoration, separate previews, invalid index recovery, compact copy")
    }
}
