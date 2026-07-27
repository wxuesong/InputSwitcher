import AppKit
import Combine
import Darwin

extension Notification.Name {
    static let inputSwitcherOpenSettingsRequested = Notification.Name(
        "com.hans.InputSwitcher.openSettingsRequested"
    )
}

struct FrontApp: Equatable {
    let bundleID: String
    let name: String
}

@MainActor
final class FrontAppTracker: ObservableObject {
    static let shared = FrontAppTracker()
    @Published var frontApp: FrontApp?
    @Published var recentApps: [FrontApp] = []

    private let maxRecent = 5

    func recordApp(_ app: FrontApp) {
        frontApp = app

        // 移除重复项
        recentApps.removeAll { $0.bundleID == app.bundleID }
        // 插入到最前面
        recentApps.insert(app, at: 0)
        // 保持最多5个
        if recentApps.count > maxRecent {
            recentApps = Array(recentApps.prefix(maxRecent))
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var instanceLockFileDescriptor: Int32 = -1
    private var isPrimaryInstance = false
    private var inputSourceMonitor: Timer?
    private var lastInputSourceID: String?
    private var isInternalSwitch = false  // 标记是否是我们自己切换的
    private var notificationWindow: SwitchNotificationWindow?
    private var autoRuleNotificationWindow: AutoRuleNotificationWindow?
    private var recordedLearningObservationForCurrentActivation = false
    private var pendingSwitchRetry: DispatchWorkItem?
    private var appearanceObservation: NSKeyValueObservation?

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard acquireSingleInstanceLock() else {
            requestSettingsFromExistingInstance()
            DispatchQueue.main.async {
                NSApp.terminate(nil)
            }
            return
        }
        isPrimaryInstance = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard isPrimaryInstance else { return }
        _ = PurchaseManager.shared
        startAppearanceObservation()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(appActivated(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(openSettingsRequested(_:)),
            name: .inputSwitcherOpenSettingsRequested,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )
        // 启动时对当前前台应用生效一次
        if let app = NSWorkspace.shared.frontmostApplication {
            handle(app)
        }

        // 启动输入法监听器（用于锁定功能）
        startInputSourceMonitor()

        // 初始化通知窗口
        notificationWindow = SwitchNotificationWindow()
        autoRuleNotificationWindow = AutoRuleNotificationWindow()

        GlobalHotKeyManager.shared.start(
            toggleEnabled: { RuleStore.shared.enabled.toggle() },
            toggleGlobalLock: {
                if PurchaseManager.shared.isPro {
                    RuleStore.shared.globalLockEnabled.toggle()
                } else {
                    ProWindowController.shared.show()
                }
            }
        )

        OnboardingWindowController.shared.showIfNeeded(
            force: CommandLine.arguments.contains("--show-onboarding")
        )

    }

    func applicationWillTerminate(_ notification: Notification) {
        guard isPrimaryInstance else { return }
        DistributedNotificationCenter.default().removeObserver(
            self,
            name: .inputSwitcherOpenSettingsRequested,
            object: nil
        )
        pendingSwitchRetry?.cancel()
        appearanceObservation?.invalidate()
        appearanceObservation = nil
        inputSourceMonitor?.invalidate()
        GlobalHotKeyManager.shared.stop()
        releaseSingleInstanceLock()
    }

    private func startAppearanceObservation() {
        appearanceObservation = NSApp.observe(
            \.effectiveAppearance,
            options: [.initial, .new]
        ) { application, _ in
            DispatchQueue.main.async {
                application.applicationIconImage = AdaptiveIconAssets.applicationIcon(
                    for: application.effectiveAppearance
                )
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        requestSettingsWindow()
        return true
    }

    private func acquireSingleInstanceLock() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.hans.InputSwitcher"
        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(bundleIdentifier).\(getuid()).lock", isDirectory: false)
        let descriptor = Darwin.open(lockURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)

        guard descriptor >= 0 else {
            NSLog("Unable to create the single-instance lock: %d", errno)
            return !hasAnotherRunningInstance
        }

        guard updateInstanceLock(type: Int16(F_WRLCK), descriptor: descriptor) else {
            Darwin.close(descriptor)
            return false
        }

        instanceLockFileDescriptor = descriptor
        return true
    }

    private func releaseSingleInstanceLock() {
        guard instanceLockFileDescriptor >= 0 else { return }
        _ = updateInstanceLock(type: Int16(F_UNLCK), descriptor: instanceLockFileDescriptor)
        Darwin.close(instanceLockFileDescriptor)
        instanceLockFileDescriptor = -1
    }

    private func updateInstanceLock(type: Int16, descriptor: Int32) -> Bool {
        var lock = Darwin.flock()
        lock.l_type = type
        lock.l_whence = Int16(SEEK_SET)
        lock.l_start = 0
        lock.l_len = 0
        return Darwin.fcntl(descriptor, F_SETLK, &lock) != -1
    }

    private var hasAnotherRunningInstance: Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .contains { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }
    }

    private func requestSettingsFromExistingInstance() {
        DistributedNotificationCenter.default().post(
            name: .inputSwitcherOpenSettingsRequested,
            object: nil,
            userInfo: nil
        )

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .first { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated }?
            .activate(options: [.activateIgnoringOtherApps])
    }

    @objc private func openSettingsRequested(_ notification: Notification) {
        requestSettingsWindow()
    }

    private func requestSettingsWindow() {
        NotificationCenter.default.post(
            name: .inputSwitcherOpenSettingsRequested,
            object: nil
        )
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        handle(app)
    }

    private func handle(_ app: NSRunningApplication) {
        pendingSwitchRetry?.cancel()
        pendingSwitchRetry = nil

        guard let bundleID = app.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return }

        let appName = app.localizedName ?? bundleID
        recordedLearningObservationForCurrentActivation = false
        let frontApp = FrontApp(
            bundleID: bundleID,
            name: appName
        )
        FrontAppTracker.shared.recordApp(frontApp)

        if RuleStore.shared.debugMode {
            logAppSwitch(bundleID: bundleID, name: appName)
        }

        guard RuleStore.shared.enabled else { return }

        // 检查是否有规则
        if let rule = RuleStore.shared.activeRule(for: bundleID) {
            // 有规则：使用规则中的输入法
            isInternalSwitch = true
            let didSelect = InputSourceManager.select(id: rule.inputSourceID)
            lastInputSourceID = didSelect ? rule.inputSourceID : InputSourceManager.currentID()

            // 显示通知
            if didSelect, let inputSourceName = InputSourceManager.name(forID: rule.inputSourceID) {
                notificationWindow?.show(inputSourceName: inputSourceName, appName: appName)
            }

            // 部分中文输入法在应用刚激活时切换会失败,稍后校验并重试一次
            let retry = DispatchWorkItem { [weak self] in
                guard let self else { return }
                defer { self.isInternalSwitch = false }
                guard RuleStore.shared.enabled,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID,
                      RuleStore.shared.activeRule(for: bundleID)?.inputSourceID == rule.inputSourceID
                else { return }
                if InputSourceManager.currentID() != rule.inputSourceID {
                    self.isInternalSwitch = true
                    let didRetry = InputSourceManager.select(id: rule.inputSourceID)
                    self.lastInputSourceID = didRetry ? rule.inputSourceID : InputSourceManager.currentID()
                } else {
                    self.lastInputSourceID = rule.inputSourceID
                }
            }
            pendingSwitchRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: retry)
        } else if !RuleStore.shared.defaultInputSource.isEmpty {
            // 无规则但设置了默认输入法：使用默认输入法
            isInternalSwitch = true
            let targetInputSourceID = RuleStore.shared.defaultInputSource
            let didSelect = InputSourceManager.select(id: targetInputSourceID)
            lastInputSourceID = didSelect ? targetInputSourceID : InputSourceManager.currentID()

            // 显示通知
            if didSelect, let inputSourceName = InputSourceManager.name(forID: targetInputSourceID) {
                notificationWindow?.show(inputSourceName: inputSourceName, appName: appName)
            }

            let retry = DispatchWorkItem { [weak self] in
                guard let self else { return }
                defer { self.isInternalSwitch = false }
                guard RuleStore.shared.enabled,
                      NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleID,
                      RuleStore.shared.activeRule(for: bundleID) == nil,
                      RuleStore.shared.defaultInputSource == targetInputSourceID
                else { return }
                if InputSourceManager.currentID() != targetInputSourceID {
                    self.isInternalSwitch = true
                    let didRetry = InputSourceManager.select(id: targetInputSourceID)
                    self.lastInputSourceID = didRetry ? targetInputSourceID : InputSourceManager.currentID()
                } else {
                    self.lastInputSourceID = targetInputSourceID
                }
            }
            pendingSwitchRetry = retry
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: retry)
        } else {
            // 无规则且无默认输入法：记录当前输入法
            lastInputSourceID = InputSourceManager.currentID()
        }
    }

    // 启动输入法监听器
    private func startInputSourceMonitor() {
        // 每0.5秒检查一次输入法是否被手动切换
        inputSourceMonitor = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkInputSourceChange()
            }
        }
    }

    private func checkInputSourceChange() {
        guard let currentInputSource = InputSourceManager.currentID() else { return }
        guard RuleStore.shared.enabled else {
            lastInputSourceID = currentInputSource
            return
        }
        guard !isInternalSwitch else { return }  // 忽略我们自己切换的

        guard let currentApp = NSWorkspace.shared.frontmostApplication,
              let bundleID = currentApp.bundleIdentifier,
              bundleID != Bundle.main.bundleIdentifier
        else { return }

        guard currentInputSource != lastInputSourceID else { return }
        lastInputSourceID = currentInputSource

        let individualLockActive = RuleStore.shared.isRuleLockActive(bundleID: bundleID)
        let globalLockActive = PurchaseManager.shared.isPro && RuleStore.shared.globalLockEnabled
        if let rule = RuleStore.shared.activeRule(for: bundleID),
           individualLockActive || globalLockActive,
           currentInputSource != rule.inputSourceID {
            isInternalSwitch = true
            let didSelect = InputSourceManager.select(id: rule.inputSourceID)
            lastInputSourceID = didSelect ? rule.inputSourceID : InputSourceManager.currentID()
            isInternalSwitch = false
            return
        }

        guard PurchaseManager.shared.isPro,
              RuleStore.shared.smartLearningEnabled,
              RuleStore.shared.rule(for: bundleID) == nil,
              !recordedLearningObservationForCurrentActivation
        else { return }

        recordedLearningObservationForCurrentActivation = true
        guard RuleStore.shared.recordLearningObservation(
            bundleID: bundleID,
            inputSourceID: currentInputSource
        ) else { return }

        let created = RuleStore.shared.setRule(
            bundleID: bundleID,
            appName: currentApp.localizedName ?? bundleID,
            inputSourceID: currentInputSource,
            isAutoLearned: true
        )
        guard created else { return }

        let appName = currentApp.localizedName ?? bundleID
        let sourceName = InputSourceManager.name(forID: currentInputSource) ?? currentInputSource
        autoRuleNotificationWindow?.show(appName: appName, inputSourceName: sourceName) {
            _ = RuleStore.shared.removeAutoLearnedRule(bundleID: bundleID)
        }
    }

    private func logAppSwitch(bundleID: String, name: String) {
        let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        let hasRule = RuleStore.shared.rule(for: bundleID) != nil
        let currentIM = InputSourceManager.currentID() ?? "unknown"
        let targetIM = RuleStore.shared.rule(for: bundleID)?.inputSourceID ?? "none"
        let enabled = RuleStore.shared.enabled ? "✓" : "✗"
        let ruleStatus = hasRule ? L10n.string("appinfo.yes") : L10n.string("appinfo.no")

        let logEntry = L10n.string(
            "debug.log_entry",
            timestamp,
            name,
            bundleID,
            ruleStatus,
            enabled,
            currentIM,
            targetIM
        )

        if let data = logEntry.data(using: .utf8) {
            DebugLog.append(data)
        }
    }
}
