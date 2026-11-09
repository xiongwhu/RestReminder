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

@main
struct PresentationProtectionTests {
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        guard condition() else { fatalError(message) }
    }

    @MainActor
    static func main() {
        typealias Policy = PresentationProtectionPolicy
        typealias Observation = Policy.Observation
        let expectedReasons = ["摄像头正在被其他应用使用", "麦克风正在被其他应用使用",
                               "显示器镜像已开启", "前台演示应用窗口覆盖整个屏幕（可能正在演示）"]
        // All sixteen signal combinations: exactly observed active signals suppress.
        for mask in 0..<16 {
            func signal(_ bit: Int) -> Observation { mask & (1 << bit) != 0 ? .active : .inactive }
            let state = Policy.compose(camera: signal(0), microphone: signal(1),
                                       mirroring: signal(2), fullscreen: signal(3))
            expect(state.suppressesReminders == (mask != 0), "Only real positive metadata suppresses: \(mask)")
            expect(state.reasons == (0..<4).compactMap { mask & (1 << $0) != 0 ? expectedReasons[$0] : nil },
                   "Reasons identify devices/metadata, never claim a meeting: \(mask)")
            expect(state.unavailable.contains(Policy.screenSharingLimitation), "Always disclose Focus and screen-sharing limits")
            expect(state.unavailable.contains(Policy.fullscreenLimitation), "Always disclose fullscreen heuristic")
        }
        let unknown = Policy.compose(camera: .unavailable("camera unavailable"),
                                     microphone: .unavailable("microphone unavailable"),
                                     mirroring: .unavailable("display unavailable"),
                                     fullscreen: .unavailable("window unavailable"))
        expect(!unknown.suppressesReminders, "Unknown coverage must not create permanent suppression")
        expect(unknown.unavailable.count == 6, "Keep all four unavailable observations and coverage text")
        let mixed = Policy.compose(camera: .active, microphone: .unavailable("microphone unavailable"),
                                   mirroring: .inactive, fullscreen: .inactive)
        expect(mixed.suppressesReminders && mixed.reasons.count == 1, "One known device use protects despite other missing metadata")
        expect(mixed.unavailable.contains("microphone unavailable"), "An active signal does not hide coverage gaps")

        func allowed(_ bundle: String?, pid: Int32 = 2, ownBundle: String? = "local.restreminder.mac") -> Bool {
            Policy.isPresentationApplication(bundleIdentifier: bundle, processIdentifier: pid,
                                             ownProcessIdentifier: 1, ownBundleIdentifier: ownBundle)
        }
        expect(allowed("com.apple.iWork.Keynote"), "Verified Keynote identifier")
        expect(allowed("com.microsoft.Powerpoint"), "Verified PowerPoint identifier with exact case")
        expect(!allowed("com.microsoft.VSCode"), "Fullscreen code editors are not presentation apps")
        expect(!allowed("com.apple.Safari"), "Do not treat all browser fullscreen windows as presentations")
        expect(!allowed("us.zoom.xos"), "Running meeting apps alone do not prove a meeting")
        expect(!allowed(nil), "Missing app identity does not prove presentation")
        expect(!allowed("com.microsoft.powerpoint"), "Do not silently broaden verified identifiers")
        expect(!allowed("com.apple.iWork.Keynote", pid: 1), "Exclude own process and all rest windows")
        expect(!allowed("com.apple.iWork.Keynote", ownBundle: "com.apple.iWork.Keynote"), "Exclude own bundle identity too")
        expect(!allowed("local.restreminder.mac"), "Rest reminder never protects itself through fullscreen")

        let main = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let left = CGRect(x: -1920, y: -100, width: 1920, height: 1080)
        let displays = [main, left]
        expect(Policy.coversDisplay(window: main, displays: displays), "Main display fullscreen")
        expect(Policy.coversDisplay(window: left, displays: displays), "Secondary display with negative coordinates")
        expect(Policy.coversDisplay(window: main.insetBy(dx: 1, dy: 1), displays: displays), "Two-point geometry tolerance")
        expect(!Policy.coversDisplay(window: main.insetBy(dx: 0, dy: 20), displays: displays), "Window leaving menu/dock space is not fullscreen")
        expect(!Policy.coversDisplay(window: main.offsetBy(dx: 100, dy: 0), displays: displays), "Fullscreen dimensions at wrong origin do not count")
        expect(!Policy.coversDisplay(window: CGRect(x: 0, y: 0, width: 3024, height: 1964), displays: displays), "Do not confuse Retina pixels with points")
        expect(!Policy.coversDisplay(window: .zero, displays: displays), "Empty window metadata is not fullscreen")
        expect(!Policy.coversDisplay(window: main, displays: []), "Missing displays do not prove fullscreen")
        expect(!Policy.coversDisplay(window: CGRect(x: CGFloat.nan, y: 0, width: 1512, height: 982), displays: displays), "Invalid window metadata is ignored")
        expect(!Policy.coversDisplay(window: main, displays: [.zero]), "Invalid display metadata is ignored")
        print("PASS: 16 protection combinations, honest unknown coverage, device wording, verified app whitelist, own-window exclusion, and fullscreen geometry")
        // Explicitly opt in to reading live OS metadata. No GUI or capture is started.
        if CommandLine.arguments.contains("--metadata-smoke") {
            let monitor = PresentationProtectionMonitor()
            let first = monitor.sample()
            expect(first == monitor.sample(), "Immediate calls return the cached snapshot")
            expect(first.unavailable.contains(Policy.screenSharingLimitation), "Live sampling retains coverage disclosure")
            print("PASS: metadata-only sample; active reasons: \(first.reasons.count), coverage messages: \(first.unavailable.count)")
        }
    }
}
