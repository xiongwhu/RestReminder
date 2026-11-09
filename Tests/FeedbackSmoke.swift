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

@main
struct FeedbackSmoke {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let restPhoto = URL(fileURLWithPath: "Resources/fresh-green.jpg")
        guard NSImage(contentsOf: restPhoto) != nil else { fatalError("Missing green photograph") }
        let feedback = ReturnCelebration(photographURL: URL(fileURLWithPath: "Resources/morning-sun-candidate.jpg"),
                                         restPhotographURL: restPhoto)
        DispatchQueue.main.async {
            feedback.show(welcome: true)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                capture(to: "build/welcome-preview.png")
                feedback.show(welcome: false, restMinutes: "5")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    capture(to: "build/exercise-preview.png")
                    print("PASS: welcome and exercise panels rendered")
                    app.terminate(nil)
                }
            }
        }
        app.run()
    }

    static func capture(to path: String) {
        guard let view = NSApplication.shared.windows.first(where: { $0.isVisible })?.contentView,
              let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            fatalError("Feedback window is missing")
        }
        view.cacheDisplay(in: view.bounds, to: image)
        guard let png = image.representation(using: .png, properties: [:]) else {
            fatalError("Panel rendering failed")
        }
        do { try png.write(to: URL(fileURLWithPath: path)) }
        catch { fatalError("Cannot save panel snapshot: \(error)") }
    }
}
