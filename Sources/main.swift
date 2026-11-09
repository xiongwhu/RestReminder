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
import CoreGraphics
import ServiceManagement

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSTextFieldDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "正在等待键鼠活动", action: nil, keyEquivalent: "")
    private let audioStatusLine = NSMenuItem(title: "正在初始化音量检测", action: nil, keyEquivalent: "")
    private let pauseItem = NSMenuItem(title: "暂停提醒", action: #selector(togglePause), keyEquivalent: "")
    private var timer: Timer?
    private var session = ActivitySession()
    private var voluntaryRest = VoluntaryRestSession()
    private let voluntaryClockOrigin = RestContinuousClock().now
    private var voluntaryAdvice: RestAdvice?
    private var voluntaryWorkSeconds: TimeInterval = 0
    private lazy var restNowItem = NSMenuItem(title: "现在就休息", action: #selector(toggleVoluntaryRest), keyEquivalent: "")
    private var escalation = RestEscalation()
    private let strongRestWindow = StrongRestWindow()
    private var alertVisible = false
    private let celebration = ReturnCelebration()
    private var adviceCycle = RestAdviceCycle()
    private var previewAdviceCycle = RestAdviceCycle()
    private var activeStrongAdvice: RestAdvice?
    private let audioMonitor = AudioPlaybackMonitor()
    private var audioQuietPeriod = AudioQuietPeriod()
    private let presentationMonitor = PresentationProtectionMonitor()
    private let protectionStatusLine = NSMenuItem(title: "正在检查会议与演示状态", action: nil, keyEquivalent: "")
    private let meetingProtectionItem = NSMenuItem(title: "开启会议/演示免打扰", action: #selector(toggleMeetingProtection), keyEquivalent: "")
    private var presentationQuietUntil: TimeInterval = 0
    private var reminderSuppressionActive = false
    private var suppressionTitle = ""
    private var lastRingPresentation: StatusRingPresentation?
    private lazy var automaticProtection = NSButton(checkboxWithTitle: "会议/演示自动避让", target: self,
                                                    action: #selector(toggleAutomaticProtection))
    private var automaticProtectionEnabled: Bool { UserDefaults.standard.bool(forKey: "automaticPresentationProtection") }
    private var manualProtectionEnabled: Bool { UserDefaults.standard.bool(forKey: "manualPresentationProtection") }
    private var automaticAlert: NSAlert?
    private let history = ActivityHistory()
    private var historyWindow: HistoryWindow?
    private var systemRest = SystemRestState()
    private var lockObservers: [NSObjectProtocol] = []
    private let screenLocked = Notification.Name("com.apple.screenIsLocked")
    private let screenUnlocked = Notification.Name("com.apple.screenIsUnlocked")
    private var settingsWindow: NSWindow?
    private var settingsScrollContainer: SettingsScrollContainer?
    private let intervalField = NSTextField()
    private let restField = NSTextField()
    private let validationLabel = NSTextField(wrappingLabelWithString: "")
    private var settingsSaveWork: DispatchWorkItem?
    private lazy var launchAtLogin = NSButton(checkboxWithTitle: "登录后自动启动", target: self,
                                              action: #selector(toggleLaunchAtLogin))
    private let loginStatus = NSTextField(wrappingLabelWithString: "")
    private let maintenanceBody = NSStackView()
    private lazy var maintenanceToggle = NSButton(title: "▸ 预览与维护", target: self,
                                                  action: #selector(toggleMaintenance))
    private var workspaceObservers: [NSObjectProtocol] = []
    private var instanceObserver: NSObjectProtocol?
    private var interval: Double { UserDefaults.standard.double(forKey: "intervalMinutes") * 60 }
    private var restThreshold: Double { UserDefaults.standard.double(forKey: "restMinutes") * 60 }
    private var now: Double { ProcessInfo.processInfo.systemUptime }
    private var voluntaryNow: TimeInterval { voluntaryClockOrigin.duration(to: RestContinuousClock().now) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["intervalMinutes": 30.0, "restMinutes": 2.0,
                                                  "automaticPresentationProtection": true,
                                                  "manualPresentationProtection": false])
        instanceObserver = DistributedNotificationCenter.default().addObserver(
            forName: SingleInstanceGuard.notificationName, object: SingleInstanceGuard.notificationObject,
            queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleInstanceIntent(notification) }
            }
        adviceCycle = RestAdviceCycle(nextIndex: UserDefaults.standard.integer(forKey: "restAdviceNextIndex"))
        escalation = RestEscalation(reminderCount: UserDefaults.standard.integer(forKey: "unrestedReminderCount"),
                                    emergencyDueAt: UserDefaults.standard.object(forKey: "strongRestDueAt") as? Date)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = StatusProgressRing.image(for: StatusRingPresentation(progress: 0, mode: .work))
        statusItem.button?.image?.isTemplate = true
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "歇一会儿 · 休息提醒", action: nil, keyEquivalent: ""))
        menu.addItem(statusLine)
        menu.addItem(audioStatusLine)
        menu.addItem(protectionStatusLine)
        menu.addItem(.separator())
        restNowItem.target = self
        menu.addItem(restNowItem)
        meetingProtectionItem.target = self
        meetingProtectionItem.toolTip = "保持开启直到手动结束；记录继续。共享屏幕或系统专注状态无法完整自动识别时，可用此项保护。"
        menu.addItem(meetingProtectionItem)
        let settingsItem = NSMenuItem(title: "设置…", action: #selector(showSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        pauseItem.target = self
        menu.addItem(pauseItem)
        let resetItem = NSMenuItem(title: "重新计时", action: #selector(resetSession), keyEquivalent: "")
        resetItem.target = self
        menu.addItem(resetItem)
        menu.addItem(.separator())
        let historyItem = NSMenuItem(title: "工作与休息记录…", action: #selector(showHistory), keyEquivalent: "")
        historyItem.target = self
        menu.addItem(historyItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出歇一会儿", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
        statusItem.menu = menu
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.didWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            workspaceObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleWorkspaceEvent(notification.name) }
            })
        }
        // Screen lock is distinct from user switching; workspace events alone can miss it.
        let lockCenter = DistributedNotificationCenter.default()
        for name in [screenLocked, screenUnlocked] {
            lockObservers.append(lockCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeIsolated { self?.handleWorkspaceEvent(notification.name) }
            })
        }
        strongRestWindow.onEmergency = { [weak self] in self?.deferStrongRest() }
        strongRestWindow.onEndVoluntary = { [weak self] in self?.finishVoluntaryRest() }
        audioMonitor.start()
        timer = Timer(timeInterval: 1, target: self, selector: #selector(tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer!, forMode: .common)
        tick()
        if CommandLine.arguments.contains("--show-settings") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            showSettings()
            UserDefaults.standard.set(true, forKey: "hasLaunched")
        }
        if CommandLine.arguments.contains("--show-history") { showHistory() }
    }

    @objc private func tick() {
        defer { updateStatusRing() }
        let audioState = audioMonitor.state()
        switch audioState {
        case .playing: audioStatusLine.title = "检测到实际音频信号"
        case .silent: audioStatusLine.title = "当前无明显声音信号"
        case .unavailable:
            if #available(macOS 14.2, *) {
                audioStatusLine.title = "音频检测未启用或中断 · 请检查权限"
            } else {
                audioStatusLine.title = "音频免打扰需 macOS 14.2+ · 可手动开启保护"
            }
        }
        audioStatusLine.toolTip = audioMonitor.errorDescription
        let wasSuppressed = reminderSuppressionActive
        let audioSuppress = audioQuietPeriod.update(state: audioState, now: now)
        let protection = automaticProtectionEnabled ? presentationMonitor.sample()
            : PresentationProtectionState(reasons: [], unavailable: [])
        if protection.suppressesReminders { presentationQuietUntil = now + 10 }
        let presentationSuppress = automaticProtectionEnabled && now < presentationQuietUntil
        let suppress = audioSuppress || manualProtectionEnabled || presentationSuppress
        reminderSuppressionActive = suppress
        meetingProtectionItem.state = manualProtectionEnabled ? .on : .off
        meetingProtectionItem.title = manualProtectionEnabled ? "结束会议/演示免打扰" : "开启会议/演示免打扰"
        if manualProtectionEnabled {
            protectionStatusLine.title = "会议/演示免打扰 · 手动开启"
            suppressionTitle = "会议/演示免打扰"
        } else if protection.suppressesReminders {
            protectionStatusLine.title = "自动避让：" + protection.reasons.joined(separator: "、")
            suppressionTitle = "会议/演示自动保护"
        } else if presentationSuppress {
            protectionStatusLine.title = "会议/演示结束缓冲中"
            suppressionTitle = "会议/演示结束缓冲"
        } else {
            protectionStatusLine.title = automaticProtectionEnabled
                ? "自动避让待命 · 专注/共享请手动保护" : "会议/演示自动避让已关闭"
            suppressionTitle = audioState == .playing ? "检测到声音 · 免打扰" : "声音结束缓冲中 · 免打扰"
        }
        protectionStatusLine.toolTip = (["自动范围：摄像头/麦克风占用、镜像投屏、Keynote/PowerPoint 全屏窗口。", "系统专注和共享屏幕请从菜单手动开启保护。"] + protection.unavailable).joined(separator: "\n")
        if suppress && !wasSuppressed { celebration.dismiss() }
        if suppress, let alert = automaticAlert {
            NSApp.abortModal()
            alert.window.orderOut(nil)
        }
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        history.sample(idle: idle, restThreshold: restThreshold)
        if voluntaryRest.isActive {
            // Explicit rest runs until the user ends it. Automatic protection/pause
            // stays enabled, but does not hide a screen the user just requested.
            let elapsed = voluntaryRest.elapsed(at: voluntaryNow)
            if escalation.observeIdle(idle.isFinite ? min(idle, elapsed) : -1, restThreshold: restThreshold) {
                activeStrongAdvice = nil
                saveEscalation()
            }
            if systemRest.isInactive {
                strongRestWindow.hide()
                statusLine.title = "主动休息中 · 已休息 \(restClockText(elapsed)) · 锁屏/休眠中"
            } else {
                showVoluntaryRest()
            }
            return
        }
        if escalation.observeIdle(idle, restThreshold: restThreshold) {
            activeStrongAdvice = nil
            saveEscalation()
            session.acknowledgeCompletedRest(now: now, idle: idle)
            strongRestWindow.hide()
            if let alert = automaticAlert {
                NSApp.abortModal()
                alert.window.orderOut(nil)
            }
        }
        if systemRest.isInactive {
            strongRestWindow.hide()
            statusLine.title = "锁屏或休眠中 · 暂停提示"
            return
        }
        guard !alertVisible else { return }
        let ordinaryDue = session.sample(now: now, idle: idle, interval: interval,
                                          restThreshold: restThreshold, suppressReminders: suppress)
        let emergencyRemaining = escalation.emergencyRemaining(at: Date())
        let shouldRemind = emergencyRemaining != nil
            ? escalation.shouldResumeStrongRest(at: Date(), idle: idle, paused: session.paused, suppressReminders: suppress)
            : ordinaryDue
        if escalation.isStrongRestActive {
            if suppress || session.paused {
                strongRestWindow.hide()
                statusLine.title = session.paused ? "提醒已暂停" : "\(suppressionTitle) · 全屏休息暂缓"
            } else {
                showStrongRest(idle: idle)
            }
            statusItem.button?.toolTip = "歇一会儿：\(statusLine.title)"
            return
        }
        if let feedback = session.feedback {
            celebration.show(welcome: feedback == .welcomeBack, restMinutes: formatMinutes(restThreshold / 60),
                             advice: feedback == .needsMoreRest ? nextRestAdvice(preview: false) : nil)
        }
        if session.paused {
            statusLine.title = "提醒已暂停"
        } else if suppress {
            statusLine.title = suppressionTitle
        } else if let emergencyRemaining {
            let seconds = Int(ceil(emergencyRemaining))
            statusLine.title = String(format: "应急延后 %02d:%02d · 随后继续休息", seconds / 60, seconds % 60)
        } else if session.startedAt == nil {
            statusLine.title = "已休息，等待键鼠活动"
        } else {
            let seconds = Int(ceil(session.remaining(now: now, interval: interval)))
            statusLine.title = seconds == 0 ? "休息时间到了，等待操作后提醒" : String(format: "距离休息 %02d:%02d", seconds / 60, seconds % 60)
        }
        statusItem.button?.toolTip = "歇一会儿：\(statusLine.title)"
        if shouldRemind {
            if escalation.nextAction == .strongRest {
                beginFullScreenRest()
            } else {
                showReminder(preview: false)
            }
        }
    }

    @objc private func toggleVoluntaryRest() {
        if voluntaryRest.isActive { finishVoluntaryRest(); return }
        guard !systemRest.isInactive else { return }
        let previousApplication = NSWorkspace.shared.frontmostApplication
        let date = Date()
        guard voluntaryRest.start(at: voluntaryNow) else { return }
        voluntaryWorkSeconds = session.startedAt.map { max(0, now - $0) } ?? 0
        voluntaryAdvice = nextRestAdvice(preview: false)
        // The explicit menu click is fresh input. Close any preceding idle span,
        // then use the history's explicit rest interval rather than idle inference.
        history.sample(at: date, uptime: now, idle: 0, restThreshold: restThreshold)
        history.suspend(at: date, reason: "主动休息")
        session.reset()
        restNowItem.title = "结束休息"
        restNowItem.state = .on
        celebration.dismiss()
        settingsWindow?.orderOut(nil)
        if let alert = automaticAlert {
            NSApp.abortModal()
            alert.window.orderOut(nil)
        }
        showVoluntaryRest(returningTo: previousApplication)
        updateStatusRing()
    }

    private func showVoluntaryRest(returningTo application: NSRunningApplication? = nil) {
        let elapsed = voluntaryRest.elapsed(at: voluntaryNow)
        strongRestWindow.update(remaining: 0, total: restThreshold, workSeconds: voluntaryWorkSeconds,
                                advice: voluntaryAdvice, mode: .voluntary, elapsed: elapsed)
        strongRestWindow.show(returningTo: application)
        statusLine.title = "主动休息中 · 已休息 \(restClockText(elapsed))"
    }

    private func finishVoluntaryRest() {
        guard voluntaryRest.finish(at: voluntaryNow) != nil else { return }
        let date = Date()
        if !systemRest.isInactive {
            history.resume(at: date)
            history.sample(at: date, uptime: now, idle: 0, restThreshold: restThreshold)
        }
        voluntaryAdvice = nil
        restNowItem.title = "现在就休息"
        restNowItem.state = .off
        strongRestWindow.hide()
        session.reset()
        tick()
    }

    private func restClockText(_ elapsed: TimeInterval) -> String {
        let seconds = Int(min(Double(Int.max).nextDown, max(0, elapsed.isFinite ? elapsed : 0)))
        func padded(_ value: Int) -> String { value < 10 ? "0\(value)" : String(value) }
        let tail = "\(padded(seconds / 60 % 60)):\(padded(seconds % 60))"
        return seconds >= 3600 ? "\(padded(seconds / 3600)):\(tail)" : tail
    }

    private func beginFullScreenRest(advice: RestAdvice? = nil, returningTo application: NSRunningApplication? = nil) {
        let work = session.startedAt.map { max(0, now - $0) } ?? interval
        escalation.beginStrongRest(at: Date(), workSeconds: work)
        activeStrongAdvice = advice ?? nextRestAdvice(preview: false)
        saveEscalation()
        celebration.dismiss()
        settingsWindow?.orderOut(nil)
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        showStrongRest(idle: idle, returningTo: application)
    }

    private func showStrongRest(idle: TimeInterval, returningTo application: NSRunningApplication? = nil) {
        let remaining = escalation.remaining(at: Date(), idle: idle, restThreshold: restThreshold)
        strongRestWindow.update(remaining: remaining, total: restThreshold,
                                workSeconds: escalation.workSecondsAtStart,
                                advice: activeStrongAdvice)
        strongRestWindow.show(returningTo: application)
        statusLine.title = "\(escalation.reminderCount >= 3 ? "加强休息中" : "休息中") · 请离开键鼠 \(formatMinutes(restThreshold / 60)) 分钟"
    }

    private func saveEscalation() {
        UserDefaults.standard.set(escalation.reminderCount, forKey: "unrestedReminderCount")
        let due = escalation.isStrongRestActive ? Date() : escalation.emergencyDueAt
        UserDefaults.standard.set(due, forKey: "strongRestDueAt")
    }

    private func deferStrongRest() {
        escalation.emergencyDefer(at: Date())
        saveEscalation()
        strongRestWindow.hide()
        session.deferReminder(now: now, seconds: 300)
        tick()
    }

    private func updateStatusRing() {
        let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
        let presentation = voluntaryRest.isActive ? StatusRingPresentation(progress: 0, mode: .rest)
            : StatusRingPresentation.make(startedAt: session.startedAt, now: now, interval: interval,
                idle: idle, restThreshold: restThreshold, paused: session.paused,
                suppressed: reminderSuppressionActive, strongRest: escalation.isStrongRestActive)
        statusItem.button?.toolTip = "歇一会儿：\(statusLine.title)"
        statusItem.button?.setAccessibilityLabel(voluntaryRest.isActive
            ? "歇一会儿，" + statusLine.title : presentation.accessibilityDescription + "，" + statusLine.title)
        guard presentation != lastRingPresentation else { return }
        statusItem.button?.image = StatusProgressRing.image(for: presentation)
        lastRingPresentation = presentation
    }

    @objc private func toggleMeetingProtection() {
        UserDefaults.standard.set(!manualProtectionEnabled, forKey: "manualPresentationProtection")
        tick()
    }

    @objc private func toggleAutomaticProtection() {
        UserDefaults.standard.set(automaticProtection.state == .on, forKey: "automaticPresentationProtection")
        if !automaticProtectionEnabled { presentationQuietUntil = 0 }
        tick()
    }

    @objc private func togglePause() {
        session.paused.toggle()
        session.reset()
        pauseItem.title = session.paused ? "恢复提醒" : "暂停提醒"
        tick()
    }

    private func handleWorkspaceEvent(_ name: Notification.Name) {
        let reason: SystemRestState.Reason
        let inactive: Bool
        switch name {
        case screenLocked: (reason, inactive) = (.screenLock, true)
        case screenUnlocked: (reason, inactive) = (.screenLock, false)
        case NSWorkspace.willSleepNotification: (reason, inactive) = (.sleep, true)
        case NSWorkspace.didWakeNotification: (reason, inactive) = (.sleep, false)
        case NSWorkspace.sessionDidResignActiveNotification: (reason, inactive) = (.inactiveSession, true)
        case NSWorkspace.sessionDidBecomeActiveNotification: (reason, inactive) = (.inactiveSession, false)
        default: return
        }
        guard let transition = systemRest.update(reason, inactive: inactive) else { return }
        let date = Date()
        switch transition {
        case .left:
            history.suspend(at: date, reason: reason == .screenLock ? "屏幕锁定" : "系统休眠 / 会话离开")
            session.suspend(at: date)
            let idle = CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: UInt32.max)!)
            escalation.suspend(at: date, idle: idle)
            strongRestWindow.hide()
            celebration.dismiss()
            if let alert = automaticAlert {
                NSApp.abortModal()
                alert.window.orderOut(nil)
            }
        case .returned:
            escalation.resume(at: date, restThreshold: restThreshold)
            saveEscalation()
            // A voluntary rest spans lock/sleep and remains a rest until its End action.
            if !voluntaryRest.isActive { history.resume(at: date) }
            // Re-evaluate current sound; a grace period from before sleep is no longer relevant.
            audioQuietPeriod = AudioQuietPeriod()
            presentationQuietUntil = 0
            session.resume(at: date, now: now, restThreshold: restThreshold)
        }
        tick()
    }

    private func handleInstanceIntent(_ notification: Notification) {
        guard let intent = SingleInstanceGuard.intent(from: notification) else { return }
        switch intent {
        case .openHistory: showHistory()
        case .openSettings: showSettings()
        case .activate:
            NSApp.activate(ignoringOtherApps: true)
            if !alertVisible && !escalation.isStrongRestActive && !voluntaryRest.isActive && !NSApp.windows.contains(where: { $0.isVisible }) { showSettings() }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        guard !alertVisible && !escalation.isStrongRestActive && !voluntaryRest.isActive else { return false }
        if !hasVisibleWindows { showSettings() }
        return true
    }

    @objc private func showHistory() {
        if historyWindow == nil {
            historyWindow = HistoryWindow(history: history,
                                          workInterval: { [weak self] in self?.interval ?? 1800 },
                                          restThreshold: { [weak self] in self?.restThreshold ?? 120 })
        }
        historyWindow?.show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let instanceObserver { DistributedNotificationCenter.default().removeObserver(instanceObserver) }
        timer?.invalidate()
        saveEscalation()
        strongRestWindow.hide()
        if settingsWindow != nil { autoSaveSettings(restartCountdown: false) }
        history.finish()
        audioMonitor.stop()
    }

    @objc private func reconnectAudio() { audioMonitor.start(); tick() }
    @objc private func resetSession() { session.reset(); tick() }
    @objc private func previewReminder() { showReminder(preview: true) }
    @objc private func previewWelcome() { celebration.show(welcome: true) }
    @objc private func previewExercise() {
        celebration.show(welcome: false, restMinutes: formatMinutes(restThreshold / 60),
                         advice: nextRestAdvice(preview: true))
    }

    private func nextRestAdvice(preview: Bool) -> RestAdvice {
        if preview { return previewAdviceCycle.next() }
        let advice = adviceCycle.next()
        UserDefaults.standard.set(adviceCycle.nextIndex, forKey: "restAdviceNextIndex")
        return advice
    }

    private func showReminder(preview: Bool) {
        guard !alertVisible else { return }
        let previousApplication = NSWorkspace.shared.frontmostApplication
        alertVisible = true
        if !preview {
            escalation.didPresentGentleReminder()
            saveEscalation()
        }
        let alert = NSAlert()
        alert.messageText = "辛苦啦，给自己一点休息的时间 🌿"
        let advice = nextRestAdvice(preview: preview)
        alert.informativeText = "\(preview ? "这是你的休息提醒预览。" : "你已经连续使用电脑一段时间了。")\n\n\(advice.title)\n\(advice.message)\n事情可以慢一点，你的身体值得被好好照顾。\n\n\(preview ? "正式提醒中选择" : "选择")“好，休息一下”将进入绿色全屏休息。\n连续离开键鼠 \(formatMinutes(restThreshold / 60)) 分钟后，开始新一轮计时。"
        if !preview {
            alert.informativeText += "\n\n第 \(escalation.reminderCount) / 3 次提醒。"
            if escalation.reminderCount >= 3 {
                alert.informativeText += " 如果仍未完成休息，下次到期将进入全屏休息；页面提供应急延后 5 分钟。"
            }
        }
        alert.alertStyle = .informational
        alert.icon = NSImage(named: NSImage.applicationIconName)
            ?? NSImage(systemSymbolName: "leaf.circle.fill", accessibilityDescription: "休息一下")
        alert.addButton(withTitle: "好，休息一下")
        alert.addButton(withTitle: "5 分钟后提醒")
        // Activation raises the app's other visible windows as well. Keep the
        // settings controller and field values, but present only the reminder.
        settingsWindow?.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        if !preview { automaticAlert = alert }
        let result = alert.runModal()
        automaticAlert = nil
        alertVisible = false
        alert.window.orderOut(nil)
        guard !preview else { return }
        switch result {
        case .alertFirstButtonReturn:
            session.beginRest(now: now, seconds: restThreshold)
            beginFullScreenRest(advice: advice, returningTo: previousApplication)
        case .alertSecondButtonReturn:
            session.deferReminder(now: now, seconds: 300)
        default:
            break
        }
    }

    private func formatMinutes(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(format: "%.1f", value)
    }

    @objc private func showSettings() {
        if settingsWindow == nil { buildSettingsWindow() }
        intervalField.doubleValue = interval / 60
        restField.doubleValue = restThreshold / 60
        automaticProtection.state = automaticProtectionEnabled ? .on : .off
        refreshLoginStatus()
        validationLabel.textColor = .secondaryLabelColor
        validationLabel.stringValue = "修改后自动保存，无需额外操作。"
        resizeSettingsToFitContent()
        settingsScrollContainer?.scrollToTop()
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func buildSettingsWindow() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 460, height: 570),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "歇一会儿 · 设置"
        window.isReleasedWhenClosed = false
        window.delegate = self
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let title = NSTextField(labelWithString: "给专注留一点呼吸的空间 🌿")
        title.font = .systemFont(ofSize: 21, weight: .semibold)
        stack.addArrangedSubview(title)
        let subtitle = NSTextField(wrappingLabelWithString: "在菜单栏安静陪伴你，到时间轻轻提醒。")
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(subtitle)
        for (label, field) in [("连续使用多久后提醒", intervalField), ("无操作多久算已休息", restField)] {
            field.widthAnchor.constraint(equalToConstant: 70).isActive = true
            field.alignment = .right
            field.placeholderString = "分钟"
            field.delegate = self
            let row = NSStackView(views: [NSTextField(labelWithString: label), field, NSTextField(labelWithString: "分钟")])
            row.spacing = 12
            stack.addArrangedSubview(row)
        }
        automaticProtection.toolTip = "自动避让摄像头/麦克风占用、镜像投屏和 Keynote/PowerPoint 全屏窗口。系统专注、共享屏幕或浏览器演示请从菜单手动开启会议/演示免打扰。"
        stack.addArrangedSubview(automaticProtection)
        let loginSettings = NSButton(title: "系统登录项…", target: self, action: #selector(openLoginItems))
        let loginRow = NSStackView(views: [launchAtLogin, loginSettings])
        loginRow.spacing = 18
        stack.addArrangedSubview(loginRow)
        loginStatus.font = .systemFont(ofSize: 12)
        loginStatus.textColor = .secondaryLabelColor
        stack.addArrangedSubview(loginStatus)
        loginStatus.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let detail = NSTextField(wrappingLabelWithString: "鼠标或键盘有活动就算在使用，短暂停顿继续计时。达到休息时长、睡眠或切换用户后重新计时。\n\n不记录按键或鼠标位置。音频免打扰需系统音频录制权限；仅在内存计算音量，不保存、上传声音。")
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        stack.addArrangedSubview(detail)
        detail.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        validationLabel.textColor = .systemRed
        validationLabel.font = .systemFont(ofSize: 12)
        stack.addArrangedSubview(validationLabel)
        validationLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

        let divider = NSBox()
        divider.boxType = .separator
        stack.addArrangedSubview(divider)
        divider.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        maintenanceToggle.isBordered = false
        maintenanceToggle.alignment = .left
        maintenanceToggle.font = .systemFont(ofSize: 13, weight: .medium)
        maintenanceToggle.toolTip = "展开提醒预览与音频维护工具"
        stack.addArrangedSubview(maintenanceToggle)
        maintenanceBody.orientation = .vertical
        maintenanceBody.alignment = .leading
        maintenanceBody.spacing = 10
        maintenanceBody.isHidden = true
        let previewLabel = NSTextField(labelWithString: "试一试提醒效果")
        previewLabel.font = .systemFont(ofSize: 12)
        previewLabel.textColor = .secondaryLabelColor
        maintenanceBody.addArrangedSubview(previewLabel)
        let previews = NSStackView(views: [
            NSButton(title: "休息提醒…", target: self, action: #selector(previewReminder)),
            NSButton(title: "元气太阳 ☀️", target: self, action: #selector(previewWelcome)),
            NSButton(title: "休息建议 🌱", target: self, action: #selector(previewExercise))
        ])
        previews.spacing = 8
        maintenanceBody.addArrangedSubview(previews)
        let reconnect = NSButton(title: "重新连接音频检测", target: self, action: #selector(reconnectAudio))
        maintenanceBody.addArrangedSubview(reconnect)
        let hint = NSTextField(wrappingLabelWithString: "仅在音频检测异常时尝试重新连接，不会改变系统音量。")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        maintenanceBody.addArrangedSubview(hint)
        stack.addArrangedSubview(maintenanceBody)
        maintenanceBody.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        hint.widthAnchor.constraint(equalTo: maintenanceBody.widthAnchor).isActive = true
        let about = AboutBrandView()
        stack.addArrangedSubview(about)
        about.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let scroll = SettingsScrollContainer(stack: stack)
        scroll.translatesAutoresizingMaskIntoConstraints = false
        window.contentView!.addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: window.contentView!.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: window.contentView!.bottomAnchor)
        ])
        settingsWindow = window
        settingsScrollContainer = scroll
    }

    @objc private func toggleMaintenance() {
        maintenanceBody.isHidden.toggle()
        let expanded = !maintenanceBody.isHidden
        maintenanceToggle.title = expanded ? "▾ 预览与维护" : "▸ 预览与维护"
        resizeSettingsToFitContent(animate: true)
    }

    private func resizeSettingsToFitContent(animate: Bool = false) {
        guard let window = settingsWindow, let scroll = settingsScrollContainer else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let frame = window.frame
        let chrome = frame.height - window.contentLayoutRect.height
        let visible = (window.screen ?? NSScreen.main)?.visibleFrame
        let maximum = max(240, (visible?.height ?? 1000) - chrome - 40)
        let height = min(maximum, max(300, ceil(scroll.preferredContentHeight)))
        let content = NSRect(x: 0, y: 0, width: 460, height: height)
        let targetHeight = window.frameRect(forContentRect: content).height
        let top = visible.map {
            min(max(frame.maxY, $0.minY + 20 + targetHeight), $0.maxY - 20)
        } ?? frame.maxY
        window.setFrame(NSRect(x: frame.minX, y: top - targetHeight,
                               width: frame.width, height: targetHeight), display: true, animate: animate)
    }

    private func refreshLoginStatus(error: String? = nil) {
        guard #available(macOS 13.0, *) else {
            launchAtLogin.isEnabled = false
            launchAtLogin.state = .off
            loginStatus.textColor = .secondaryLabelColor
            loginStatus.stringValue = "macOS 12 请在“用户与群组 → 登录项”手动添加本应用。"
            return
        }
        launchAtLogin.isEnabled = true
        let status = SMAppService.mainApp.status
        launchAtLogin.state = (status == .enabled || status == .requiresApproval) ? .on : .off
        loginStatus.textColor = error == nil ? .secondaryLabelColor : .systemRed
        if let error { loginStatus.stringValue = "设置失败：\(error)"; return }
        switch status {
        case .enabled:
            loginStatus.stringValue = "已开启。重启并登录当前账户后自动启动，修改立即生效。"
        case .requiresApproval:
            loginStatus.stringValue = "等待系统允许。请打开“系统登录项”，允许歇一会儿运行。"
        case .notRegistered:
            loginStatus.stringValue = "未开启。勾选后立即生效。"
        case .notFound:
            loginStatus.stringValue = "系统未找到登录项，请尝试重新开启或在系统登录项中添加。"
        @unknown default:
            loginStatus.stringValue = "无法确认登录项状态，请查看系统登录项。"
        }
    }

    @objc private func toggleLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { refreshLoginStatus(); return }
        do {
            let service = SMAppService.mainApp
            if launchAtLogin.state == .on {
                if service.status != .enabled && service.status != .requiresApproval { try service.register() }
            } else if service.status == .enabled || service.status == .requiresApproval {
                try service.unregister()
            }
            refreshLoginStatus()
        } catch {
            refreshLoginStatus(error: error.localizedDescription)
        }
    }

    @objc private func openLoginItems() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
        else { NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Accounts.prefPane")) }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        if settingsWindow?.isVisible == true { refreshLoginStatus() }
    }

    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === intervalField || field === restField else { return }
        settingsSaveWork?.cancel()
        validationLabel.textColor = .secondaryLabelColor
        validationLabel.stringValue = "正在编辑…"
        let task = DispatchWorkItem { [weak self] in self?.autoSaveSettings() }
        settingsSaveWork = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: task)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField,
              field === intervalField || field === restField else { return }
        autoSaveSettings()
    }

    func windowWillClose(_ notification: Notification) {
        if let window = notification.object as? NSWindow, window === settingsWindow { autoSaveSettings() }
    }

    private func autoSaveSettings(restartCountdown: Bool = true) {
        settingsSaveWork?.cancel()
        settingsSaveWork = nil
        var changed = false
        var errors: [String] = []
        for (field, key, range, name) in [
            (intervalField, "intervalMinutes", 0.1...240.0, "提醒间隔"),
            (restField, "restMinutes", 0.1...60.0, "休息时长")
        ] {
            let text = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Double(text), value.isFinite, range.contains(value) else {
                errors.append("\(name)需为 0.1–\(Int(range.upperBound)) 分钟")
                continue
            }
            if value != UserDefaults.standard.double(forKey: key) {
                UserDefaults.standard.set(value, forKey: key)
                changed = true
            }
        }
        if changed && restartCountdown { resetSession() }
        validationLabel.textColor = errors.isEmpty ? .secondaryLabelColor : .systemRed
        validationLabel.stringValue = errors.isEmpty ? "已自动保存" : errors.joined(separator: "；") + "，无效输入未保存。"
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

MainActor.assumeIsolated {
    // Own the per-user writer lock before AppDelegate can load or modify history.
    switch SingleInstanceGuard.acquire() {
    case .acquired(let instance):
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime((delegate, instance)) { app.run() }
    case .alreadyRunning:
        let intent: SingleInstanceGuard.Intent = CommandLine.arguments.contains("--show-history") ? .openHistory
            : (CommandLine.arguments.contains("--show-settings") ? .openSettings : .activate)
        SingleInstanceGuard.forward(intent)
        let bundleID = Bundle.main.bundleIdentifier ?? "local.restreminder.mac"
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }?
            .activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
    case .failed(let failure):
        let message = "无法安全打开本地记录：\(failure.localizedDescription)"
        FileHandle.standardError.write(Data((message + "\n").utf8))
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let alert = NSAlert()
        alert.messageText = "歇一会儿暂时无法启动"
        alert.informativeText = message + "\n为避免多个实例同时写入，应用没有继续启动。"
        alert.runModal()
        exit(EXIT_FAILURE)
    }
}
