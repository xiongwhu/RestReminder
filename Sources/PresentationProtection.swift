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
import AVFoundation
import CoreGraphics

struct PresentationProtectionState: Equatable {
    let reasons: [String]
    let unavailable: [String]
    var suppressesReminders: Bool { !reasons.isEmpty }
}

/// Pure policy: missing observations describe coverage, and never invent an active meeting.
struct PresentationProtectionPolicy {
    enum Observation {
        case inactive
        case active
        case unavailable(String)
    }

    static let screenSharingLimitation = "当前版本无法可靠读取系统专注状态或识别所有共享屏幕；可手动开启会议/演示免打扰。"
    static let fullscreenLimitation = "全屏保护仅覆盖前台 Keynote / PowerPoint 的屏幕大小窗口，不能确认正在放映；浏览器演示或未占用摄像头/麦克风的会议请使用手动会议模式。"

    // Keynote: verified in the installed application's Info.plist.
    // PowerPoint: Apple App Store lookup id=462062816, bundleId=com.microsoft.Powerpoint.
    static let presentationBundleIdentifiers: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint"
    ]

    static func compose(camera: Observation, microphone: Observation,
                        mirroring: Observation, fullscreen: Observation) -> PresentationProtectionState {
        var reasons: [String] = []
        var unavailable = [screenSharingLimitation, fullscreenLimitation]
        let observations: [(Observation, String)] = [
            (camera, "摄像头正在被其他应用使用"),
            (microphone, "麦克风正在被其他应用使用"),
            (mirroring, "显示器镜像已开启"),
            (fullscreen, "前台演示应用窗口覆盖整个屏幕（可能正在演示）")
        ]
        for (observation, reason) in observations {
            switch observation {
            case .active: reasons.append(reason)
            case .inactive: break
            case .unavailable(let message): unavailable.append(message)
            }
        }
        return PresentationProtectionState(reasons: reasons, unavailable: unavailable)
    }

    static func isPresentationApplication(bundleIdentifier: String?, processIdentifier: Int32,
                                          ownProcessIdentifier: Int32,
                                          ownBundleIdentifier: String?) -> Bool {
        guard processIdentifier != ownProcessIdentifier,
              let bundleIdentifier, bundleIdentifier != ownBundleIdentifier else { return false }
        return presentationBundleIdentifiers.contains(bundleIdentifier)
    }

    /// CGWindow and CGDisplayBounds both use global coordinates with a top-left origin.
    /// A screen-sized editor inside these two presentation apps is an intentional false positive.
    static func coversDisplay(window: CGRect, displays: [CGRect]) -> Bool {
        func valid(_ rect: CGRect) -> Bool {
            rect.origin.x.isFinite && rect.origin.y.isFinite && rect.width.isFinite &&
                rect.height.isFinite && rect.width > 0 && rect.height > 0
        }
        guard valid(window) else { return false }
        return displays.contains { display in
            valid(display) && abs(window.minX - display.minX) <= 2 &&
                abs(window.minY - display.minY) <= 2 &&
                abs(window.width - display.width) <= 2 &&
                abs(window.height - display.height) <= 2
        }
    }
}

/// Call on the main actor. This monitor reads OS metadata only; it never creates inputs,
/// capture sessions, screen streams, or requests camera/microphone/screen permissions.
/// Add this source and link AppKit, AVFoundation, and CoreGraphics to integrate.
/// Focus is intentionally unsupported here: Apple's communication-app prerequisites are not
/// satisfied by this utility. No Focus usage key, entitlement, or authorization action is used.
@MainActor
final class PresentationProtectionMonitor {
    private typealias Observation = PresentationProtectionPolicy.Observation
    private let clock = RestContinuousClock()
    private var sampledAt: RestContinuousClock.Instant?
    private var cached: PresentationProtectionState?

    /// Results are cached for three seconds, including across callers. RestContinuousClock includes
    /// sleep, so a pre-sleep snapshot expires after waking. Sampling never prompts for access.
    func sample() -> PresentationProtectionState {
        if let cached, let sampledAt, sampledAt.duration(to: clock.now) < 3 {
            return cached
        }
        let displays = onlineDisplays()
        let state = PresentationProtectionPolicy.compose(
            camera: deviceUse(mediaType: .video), microphone: deviceUse(mediaType: .audio),
            mirroring: mirroring(displays: displays), fullscreen: fullscreen(displays: displays))
        cached = state
        sampledAt = clock.now
        return state
    }

    private func deviceUse(mediaType: AVMediaType) -> Observation {
        let isCamera = mediaType == .video
        let label = isCamera ? "摄像头" : "麦克风"
        let types: [AVCaptureDevice.DeviceType]
        if #available(macOS 14.0, *) {
            types = isCamera ? [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera] : [.microphone]
        } else {
            types = isCamera ? [.builtInWideAngleCamera, .externalUnknown] : [.builtInMicrophone]
        }
        // Discovery and this read-only property do not open a capture device. Do not read
        // localizedName/uniqueID, construct AVCaptureDeviceInput, or request media access.
        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: types, mediaType: mediaType,
                                                       position: .unspecified).devices.filter { $0.isConnected }
        if devices.contains(where: { $0.isInUseByAnotherApplication }) { return .active }
        guard !devices.isEmpty else {
            return .unavailable("\(label)使用状态未知：没有可见的设备元数据；不申请设备权限。")
        }
        // A negative flag is only a negative observation for the visible devices. Drivers,
        // virtual devices, and shared/non-AVFoundation clients can make this incomplete.
        return .unavailable("\(label)未报告被其他应用占用；此设备元数据无法排除所有会议或驱动未报告的使用。")
    }

    private func onlineDisplays() -> [CGDirectDisplayID]? {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return nil }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        var written: UInt32 = 0
        guard CGGetOnlineDisplayList(count, &displays, &written) == .success,
              written > 0, written <= count else { return nil }
        return Array(displays.prefix(Int(written)))
    }

    private func mirroring(displays: [CGDirectDisplayID]?) -> Observation {
        guard let displays else { return .unavailable("显示器镜像状态未知：无法读取在线显示器列表。") }
        return displays.contains { CGDisplayIsInMirrorSet($0) != 0 } ? .active : .inactive
    }

    private func fullscreen(displays: [CGDirectDisplayID]?) -> Observation {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return .unavailable("演示全屏状态未知：无法读取前台应用元数据。")
        }
        guard PresentationProtectionPolicy.isPresentationApplication(
            bundleIdentifier: application.bundleIdentifier, processIdentifier: application.processIdentifier,
            ownProcessIdentifier: ProcessInfo.processInfo.processIdentifier,
            ownBundleIdentifier: Bundle.main.bundleIdentifier) else { return .inactive }
        guard let displays else { return .unavailable("演示全屏状态未知：无法读取显示器尺寸。") }
        // Only inspect windows after identifying a whitelisted frontmost presentation app.
        // Never subscript kCGWindowName/kCGWindowOwnerName or request a screen image.
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else {
            return .unavailable("演示全屏状态未知：窗口尺寸元数据不可用；不申请屏幕录制权限。")
        }
        let displayBounds = displays.map { CGDisplayBounds($0) }
        var foundBounds = false
        for window in windows {
            guard let pid = window[kCGWindowOwnerPID as String] as? NSNumber,
                  pid.int32Value == application.processIdentifier,
                  let layer = window[kCGWindowLayer as String] as? NSNumber, layer.intValue >= 0,
                  let alpha = window[kCGWindowAlpha as String] as? NSNumber, alpha.doubleValue > 0.01,
                  let dictionary = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dictionary) else { continue }
            foundBounds = true
            if PresentationProtectionPolicy.coversDisplay(window: bounds, displays: displayBounds) { return .active }
        }
        return foundBounds ? .inactive : .unavailable("演示全屏状态未知：前台演示应用未提供可用窗口尺寸。")
    }
}
