import Foundation
import Combine
import AppKit
import Security

struct Rule: Codable, Identifiable, Hashable {
    var id: String { bundleID }
    let bundleID: String
    var appName: String
    var inputSourceID: String
    var isLocked: Bool = false
    var syncedInputSourceID: String? = nil
    var syncedInputSourceName: String? = nil
    var isAutoLearned: Bool = false

    init(
        bundleID: String,
        appName: String,
        inputSourceID: String,
        isLocked: Bool = false,
        syncedInputSourceID: String? = nil,
        syncedInputSourceName: String? = nil,
        isAutoLearned: Bool = false
    ) {
        self.bundleID = bundleID
        self.appName = appName
        self.inputSourceID = inputSourceID
        self.isLocked = isLocked
        self.syncedInputSourceID = syncedInputSourceID
        self.syncedInputSourceName = syncedInputSourceName
        self.isAutoLearned = isAutoLearned
    }

    private enum CodingKeys: String, CodingKey {
        case bundleID
        case appName
        case inputSourceID
        case isLocked
        case syncedInputSourceID
        case syncedInputSourceName
        case isAutoLearned
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        appName = try container.decode(String.self, forKey: .appName)
        inputSourceID = try container.decode(String.self, forKey: .inputSourceID)
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        syncedInputSourceID = try container.decodeIfPresent(String.self, forKey: .syncedInputSourceID)
        syncedInputSourceName = try container.decodeIfPresent(String.self, forKey: .syncedInputSourceName)
        isAutoLearned = try container.decodeIfPresent(Bool.self, forKey: .isAutoLearned) ?? false
    }
}

enum NotificationPosition: String, CaseIterable, Identifiable, Codable {
    case topLeading
    case topCenter
    case topTrailing
    case centerLeading
    case center
    case centerTrailing
    case bottomLeading
    case bottomCenter
    case bottomTrailing

    var id: String { rawValue }
}

enum CloudSyncStatus: Equatable {
    case disabled
    case requiresPro
    case unavailable
    case syncing
    case synced
    case conflict
    case failed
}

@MainActor
final class RuleStore: ObservableObject {
    static let shared = RuleStore()
    static let learningMinimumObservations = 3
    static let maximumImportSize = 5 * 1024 * 1024
    static let maximumRuleCount = 10_000

    private static let learningConfidence = 0.7
    private static let learningHistoryLifetime: TimeInterval = 30 * 24 * 60 * 60
    private static let learningHistoryLimit = 10

    private static let rulesKey = "rules"
    private static let enabledKey = "enabled"
    private static let smartLearningEnabledKey = "smartLearningEnabled"
    private static let learningHistoryKey = "learningHistory"
    private static let enabledShortcutKey = "enabledShortcut"
    private static let globalLockShortcutKey = "globalLockShortcut"
    private static let launchAtLoginKey = "launchAtLogin"
    private static let debugModeKey = "debugMode"
    private static let menuRuleCountKey = "menuRuleCount"
    private static let defaultInputSourceKey = "defaultInputSource"
    private static let showSwitchNotificationKey = "showSwitchNotification"  // 新增：切换通知
    private static let notificationPositionKey = "notificationPosition"
    private static let notificationDurationKey = "notificationDuration"
    private static let globalLockEnabledKey = "globalLockEnabled"
    private static let cloudSyncEnabledKey = "cloudSyncEnabled"
    private static let cloudRevisionKey = "cloudRevision"
    private static let cloudVersionVectorKey = "cloudVersionVector"
    private static let cloudDeviceIDKey = "cloudDeviceID"
    private static let inputSourceReplacementsKey = "inputSourceReplacements"
    private static let syncedDefaultInputSourceIDKey = "syncedDefaultInputSourceID"
    private static let syncedDefaultInputSourceNameKey = "syncedDefaultInputSourceName"

    private enum CloudKey {
        static let snapshot = "snapshot.v1"
        static let rules = "rules"
        static let enabled = "enabled"
        static let globalLockEnabled = "globalLockEnabled"
        static let debugMode = "debugMode"
        static let menuRuleCount = "menuRuleCount"
        static let defaultInputSource = "defaultInputSource"
        static let showSwitchNotification = "showSwitchNotification"
        static let notificationPosition = "notificationPosition"
        static let notificationDuration = "notificationDuration"
    }

    private struct CloudSnapshot: Codable {
        let schemaVersion: Int
        let modifiedAt: TimeInterval
        let sourceDeviceID: String
        let rules: [Rule]
        let enabled: Bool
        let globalLockEnabled: Bool
        let debugMode: Bool
        let menuRuleCount: Int
        let defaultInputSource: String
        let showSwitchNotification: Bool
        let notificationPosition: NotificationPosition
        let notificationDuration: Double
        let smartLearningEnabled: Bool?
        let inputSourceNames: [String: String]?
        let versionVector: [String: Int]?
    }

    private struct LearningObservation: Codable {
        let inputSourceID: String
        let observedAt: TimeInterval
    }

    private var cloudStore: NSUbiquitousKeyValueStore {
        NSUbiquitousKeyValueStore.default
    }
    private var isApplyingCloudValues = false
    private var initialCloudSyncTask: Task<Void, Never>?
    private var pendingCloudSnapshot: CloudSnapshot?
    private var localChangesPending = false
    private var localRevision: TimeInterval
    private var localVersionVector: [String: Int]
    private let deviceID: String
    private var inputSourceReplacements: [String: String] = [:]
    private var syncedDefaultInputSourceID: String?
    private var syncedDefaultInputSourceName: String?
    private var learningHistory: [String: [LearningObservation]] = [:]
    private var isUpdatingLaunchAtLogin = false

    let cloudSyncAvailable: Bool
    @Published private(set) var cloudSyncStatus: CloudSyncStatus = .disabled
    @Published private(set) var cloudConflictDeviceID: String?
    @Published private(set) var launchAtLoginError: String?

    @Published var rules: [Rule] {
        didSet {
            save()
            localStateDidChange()
        }
    }

    @Published var enabled: Bool {
        didSet {
            UserDefaults.standard.set(enabled, forKey: Self.enabledKey)
            localStateDidChange()
        }
    }

    @Published var smartLearningEnabled: Bool {
        didSet {
            UserDefaults.standard.set(smartLearningEnabled, forKey: Self.smartLearningEnabledKey)
            localStateDidChange()
        }
    }

    @Published var enabledShortcutID: String {
        didSet {
            UserDefaults.standard.set(enabledShortcutID, forKey: Self.enabledShortcutKey)
            GlobalHotKeyManager.shared.updateShortcuts(
                enabled: enabledShortcut,
                globalLock: globalLockShortcut
            )
        }
    }

    @Published var globalLockShortcutID: String {
        didSet {
            UserDefaults.standard.set(globalLockShortcutID, forKey: Self.globalLockShortcutKey)
            GlobalHotKeyManager.shared.updateShortcuts(
                enabled: enabledShortcut,
                globalLock: globalLockShortcut
            )
        }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)
            if let error = LaunchAtLoginManager.shared.setEnabled(launchAtLogin) {
                launchAtLoginError = error.localizedDescription
                isUpdatingLaunchAtLogin = true
                launchAtLogin = LaunchAtLoginManager.shared.isEnabled()
                UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)
                isUpdatingLaunchAtLogin = false
            } else {
                launchAtLoginError = nil
            }
        }
    }

    @Published var debugMode: Bool {
        didSet {
            UserDefaults.standard.set(debugMode, forKey: Self.debugModeKey)
            if !debugMode {
                DebugLog.remove()
            }
            localStateDidChange()
        }
    }

    @Published var menuRuleCount: Int {
        didSet {
            UserDefaults.standard.set(menuRuleCount, forKey: Self.menuRuleCountKey)
            localStateDidChange()
        }
    }

    @Published var defaultInputSource: String {  // 新增：默认输入法
        didSet {
            if !isApplyingCloudValues {
                clearSyncedDefaultInputSource()
            }
            UserDefaults.standard.set(defaultInputSource, forKey: Self.defaultInputSourceKey)
            localStateDidChange()
        }
    }

    @Published var showSwitchNotification: Bool {  // 新增：显示切换通知
        didSet {
            UserDefaults.standard.set(showSwitchNotification, forKey: Self.showSwitchNotificationKey)
            localStateDidChange()
        }
    }

    @Published var notificationPosition: NotificationPosition {
        didSet {
            UserDefaults.standard.set(notificationPosition.rawValue, forKey: Self.notificationPositionKey)
            localStateDidChange()
        }
    }

    @Published var notificationDuration: Double {
        didSet {
            UserDefaults.standard.set(notificationDuration, forKey: Self.notificationDurationKey)
            localStateDidChange()
        }
    }

    @Published var globalLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(globalLockEnabled, forKey: Self.globalLockEnabledKey)
            localStateDidChange()
        }
    }

    @Published var cloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(cloudSyncEnabled, forKey: Self.cloudSyncEnabledKey)
            if cloudSyncEnabled {
                startCloudSync()
            } else {
                initialCloudSyncTask?.cancel()
                initialCloudSyncTask = nil
                pendingCloudSnapshot = nil
                cloudConflictDeviceID = nil
                cloudSyncStatus = .disabled
            }
        }
    }

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.rulesKey),
           let decoded = try? JSONDecoder().decode([Rule].self, from: data) {
            rules = Self.sanitizedStoredRules(decoded)
        } else {
            rules = []
        }
        enabled = UserDefaults.standard.object(forKey: Self.enabledKey) as? Bool ?? true
        smartLearningEnabled = UserDefaults.standard.object(forKey: Self.smartLearningEnabledKey) as? Bool ?? false
        enabledShortcutID = UserDefaults.standard.string(forKey: Self.enabledShortcutKey)
            ?? GlobalShortcutOption.defaultEnabled.id
        globalLockShortcutID = UserDefaults.standard.string(forKey: Self.globalLockShortcutKey)
            ?? GlobalShortcutOption.defaultGlobalLock.id
        if let learningData = UserDefaults.standard.data(forKey: Self.learningHistoryKey),
           let decodedHistory = try? JSONDecoder().decode([String: [LearningObservation]].self, from: learningData) {
            learningHistory = decodedHistory
        }
        let savedDebugMode = UserDefaults.standard.object(forKey: Self.debugModeKey) as? Bool ?? false
        debugMode = savedDebugMode
        if !savedDebugMode {
            DebugLog.remove()
        }
        menuRuleCount = Self.normalizedMenuRuleCount(
            UserDefaults.standard.object(forKey: Self.menuRuleCountKey) as? Int ?? 5
        )
        defaultInputSource = UserDefaults.standard.string(forKey: Self.defaultInputSourceKey) ?? ""
        showSwitchNotification = UserDefaults.standard.object(forKey: Self.showSwitchNotificationKey) as? Bool ?? false
        notificationPosition = NotificationPosition(
            rawValue: UserDefaults.standard.string(forKey: Self.notificationPositionKey) ?? "topTrailing"
        ) ?? .topTrailing
        notificationDuration = min(
            max(UserDefaults.standard.object(forKey: Self.notificationDurationKey) as? Double ?? 1.0, 0.1),
            4.0
        )
        globalLockEnabled = UserDefaults.standard.object(forKey: Self.globalLockEnabledKey) as? Bool ?? false
        cloudSyncEnabled = UserDefaults.standard.object(forKey: Self.cloudSyncEnabledKey) as? Bool ?? true
        inputSourceReplacements = UserDefaults.standard.dictionary(forKey: Self.inputSourceReplacementsKey) as? [String: String] ?? [:]
        syncedDefaultInputSourceID = UserDefaults.standard.string(forKey: Self.syncedDefaultInputSourceIDKey)
        syncedDefaultInputSourceName = UserDefaults.standard.string(forKey: Self.syncedDefaultInputSourceNameKey)
        localRevision = UserDefaults.standard.double(forKey: Self.cloudRevisionKey)
        localVersionVector = UserDefaults.standard.dictionary(forKey: Self.cloudVersionVectorKey)?
            .compactMapValues { ($0 as? NSNumber)?.intValue } ?? [:]
        if let savedDeviceID = UserDefaults.standard.string(forKey: Self.cloudDeviceIDKey) {
            deviceID = savedDeviceID
        } else {
            let newDeviceID = UUID().uuidString
            UserDefaults.standard.set(newDeviceID, forKey: Self.cloudDeviceIDKey)
            deviceID = newDeviceID
        }
        cloudSyncAvailable = Self.hasValidCloudEntitlement

        launchAtLogin = LaunchAtLoginManager.shared.isEnabled()
        UserDefaults.standard.set(launchAtLogin, forKey: Self.launchAtLoginKey)

        if cloudSyncAvailable {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(cloudStoreDidChange(_:)),
                name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                object: cloudStore
            )
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(proEntitlementDidChange),
            name: .proEntitlementDidChange,
            object: nil
        )
        if cloudSyncEnabled {
            startCloudSync()
        }
        save()
    }

    deinit {
        initialCloudSyncTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    private static var hasValidCloudEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(
                task,
                "com.apple.developer.ubiquity-kvstore-identifier" as CFString,
                nil
              ) as? String else {
            return false
        }
        return !value.isEmpty && !value.contains("$(")
    }

    private func startCloudSync() {
        guard PurchaseManager.shared.isPro else {
            cloudSyncStatus = .requiresPro
            return
        }
        guard cloudSyncAvailable else {
            cloudSyncStatus = .unavailable
            return
        }

        initialCloudSyncTask?.cancel()
        cloudSyncStatus = .syncing
        guard cloudStore.synchronize() else {
            cloudSyncStatus = .failed
            return
        }

        // Give the KVS daemon time to populate its local cache before deciding
        // that the cloud is empty. An external-change notification resolves it sooner.
        let task = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
            self?.resolveCloudState()
        }
        initialCloudSyncTask = task
    }

    private func localStateDidChange() {
        guard !isApplyingCloudValues else { return }

        localChangesPending = true
        localRevision = Date().timeIntervalSince1970
        localVersionVector[deviceID, default: 0] += 1
        UserDefaults.standard.set(localRevision, forKey: Self.cloudRevisionKey)
        UserDefaults.standard.set(localVersionVector, forKey: Self.cloudVersionVectorKey)
        uploadCurrentSnapshot()
    }

    private func uploadCurrentSnapshot() {
        guard PurchaseManager.shared.isPro, cloudSyncEnabled, cloudSyncAvailable else { return }

        if localRevision == 0 {
            localRevision = Date().timeIntervalSince1970
            UserDefaults.standard.set(localRevision, forKey: Self.cloudRevisionKey)
        }
        if localVersionVector.isEmpty {
            localVersionVector[deviceID] = 1
            UserDefaults.standard.set(localVersionVector, forKey: Self.cloudVersionVectorKey)
        }

        let cloudPayload = makeCloudRulePayload()
        let cloudDefaultInputSource = syncedDefaultInputSourceID ?? defaultInputSource
        var inputSourceNames = cloudPayload.inputSourceNames
        if !cloudDefaultInputSource.isEmpty {
            let defaultName = syncedDefaultInputSourceName ?? InputSourceManager.name(forID: defaultInputSource)
            if let defaultName {
                inputSourceNames[cloudDefaultInputSource] = defaultName
            }
        }

        let snapshot = CloudSnapshot(
            schemaVersion: 1,
            modifiedAt: localRevision,
            sourceDeviceID: deviceID,
            rules: cloudPayload.rules,
            enabled: enabled,
            globalLockEnabled: globalLockEnabled,
            debugMode: debugMode,
            menuRuleCount: menuRuleCount,
            defaultInputSource: cloudDefaultInputSource,
            showSwitchNotification: showSwitchNotification,
            notificationPosition: notificationPosition,
            notificationDuration: notificationDuration,
            smartLearningEnabled: smartLearningEnabled,
            inputSourceNames: inputSourceNames,
            versionVector: localVersionVector
        )

        guard let data = try? JSONEncoder().encode(snapshot) else {
            cloudSyncStatus = .failed
            return
        }

        cloudSyncStatus = .syncing
        cloudStore.set(data, forKey: CloudKey.snapshot)
        if cloudStore.synchronize() {
            localChangesPending = false
            cloudSyncStatus = .synced
        } else {
            cloudSyncStatus = .failed
        }
    }

    private func resolveCloudState() {
        initialCloudSyncTask?.cancel()
        initialCloudSyncTask = nil
        guard PurchaseManager.shared.isPro, cloudSyncEnabled, cloudSyncAvailable else { return }

        if let data = cloudStore.data(forKey: CloudKey.snapshot) {
            guard let snapshot = try? JSONDecoder().decode(CloudSnapshot.self, from: data),
                  snapshot.schemaVersion == 1 else {
                cloudSyncStatus = .failed
                return
            }

            if let remoteVector = snapshot.versionVector {
                switch Self.compareVersionVectors(localVersionVector, remoteVector) {
                case .equal:
                    localChangesPending = false
                    cloudSyncStatus = .synced
                case .remoteDominates:
                    apply(snapshot)
                case .localDominates:
                    uploadCurrentSnapshot()
                case .concurrent:
                    pendingCloudSnapshot = snapshot
                    cloudConflictDeviceID = snapshot.sourceDeviceID
                    cloudSyncStatus = .conflict
                    presentCloudConflictAlertIfNeeded()
                }
                return
            }

            if snapshot.modifiedAt > localRevision {
                if localChangesPending {
                    pendingCloudSnapshot = snapshot
                    cloudConflictDeviceID = snapshot.sourceDeviceID
                    cloudSyncStatus = .conflict
                    presentCloudConflictAlertIfNeeded()
                } else {
                    apply(snapshot)
                }
            } else if snapshot.modifiedAt < localRevision {
                uploadCurrentSnapshot()
            } else {
                cloudSyncStatus = .synced
            }
            return
        }

        if loadLegacyCloudValues() {
            localRevision = Date().timeIntervalSince1970
            UserDefaults.standard.set(localRevision, forKey: Self.cloudRevisionKey)
        }
        uploadCurrentSnapshot()
    }

    private func apply(_ snapshot: CloudSnapshot) {
        isApplyingCloudValues = true
        defer { isApplyingCloudValues = false }

        let resolved = resolveInputSources(
            rules: Self.sanitizedStoredRules(snapshot.rules),
            defaultInputSource: snapshot.defaultInputSource,
            names: snapshot.inputSourceNames ?? [:]
        )

        rules = Self.sanitizedStoredRules(resolved.rules)
        enabled = snapshot.enabled
        globalLockEnabled = snapshot.globalLockEnabled
        debugMode = snapshot.debugMode
        menuRuleCount = Self.normalizedMenuRuleCount(snapshot.menuRuleCount)
        applySyncedDefaultInputSource(
            localID: resolved.defaultInputSource,
            cloudID: snapshot.defaultInputSource,
            cloudName: snapshot.inputSourceNames?[snapshot.defaultInputSource]
        )
        showSwitchNotification = snapshot.showSwitchNotification
        notificationPosition = snapshot.notificationPosition
        notificationDuration = min(max(snapshot.notificationDuration, 0.1), 4.0)
        if let smartLearningEnabled = snapshot.smartLearningEnabled {
            self.smartLearningEnabled = smartLearningEnabled
        }
        localRevision = snapshot.modifiedAt
        localVersionVector = snapshot.versionVector ?? [snapshot.sourceDeviceID: 1]
        UserDefaults.standard.set(localRevision, forKey: Self.cloudRevisionKey)
        UserDefaults.standard.set(localVersionVector, forKey: Self.cloudVersionVectorKey)
        localChangesPending = false
        pendingCloudSnapshot = nil
        cloudConflictDeviceID = nil
        cloudSyncStatus = .synced
    }

    func reviewCloudConflict() {
        presentCloudConflictAlertIfNeeded()
    }

    private func presentCloudConflictAlertIfNeeded() {
        guard pendingCloudSnapshot != nil else { return }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("settings.icloud_conflict_title")
        alert.informativeText = L10n.string(
            "settings.icloud_conflict_message",
            String(cloudConflictDeviceID?.prefix(8) ?? "")
        )
        alert.addButton(withTitle: L10n.string("settings.icloud_use_cloud"))
        alert.addButton(withTitle: L10n.string("settings.icloud_keep_local"))
        alert.addButton(withTitle: L10n.string("settings.cancel"))

        NSApp.activate(ignoringOtherApps: true)
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            if let snapshot = pendingCloudSnapshot {
                apply(snapshot)
            }
        case .alertSecondButtonReturn:
            if let remoteVector = pendingCloudSnapshot?.versionVector {
                for (remoteDeviceID, remoteRevision) in remoteVector {
                    localVersionVector[remoteDeviceID] = max(
                        localVersionVector[remoteDeviceID, default: 0],
                        remoteRevision
                    )
                }
            }
            pendingCloudSnapshot = nil
            cloudConflictDeviceID = nil
            localRevision = Date().timeIntervalSince1970
            localVersionVector[deviceID, default: 0] += 1
            UserDefaults.standard.set(localRevision, forKey: Self.cloudRevisionKey)
            UserDefaults.standard.set(localVersionVector, forKey: Self.cloudVersionVectorKey)
            localChangesPending = true
            uploadCurrentSnapshot()
        default:
            cloudSyncStatus = .conflict
        }
    }

    enum VersionVectorOrder: Equatable {
        case equal
        case localDominates
        case remoteDominates
        case concurrent
    }

    static func compareVersionVectors(_ local: [String: Int], _ remote: [String: Int]) -> VersionVectorOrder {
        let deviceIDs = Set(local.keys).union(remote.keys)
        var localIsGreater = false
        var remoteIsGreater = false
        for deviceID in deviceIDs {
            let localValue = local[deviceID, default: 0]
            let remoteValue = remote[deviceID, default: 0]
            localIsGreater = localIsGreater || localValue > remoteValue
            remoteIsGreater = remoteIsGreater || remoteValue > localValue
        }
        switch (localIsGreater, remoteIsGreater) {
        case (false, false): return .equal
        case (true, false): return .localDominates
        case (false, true): return .remoteDominates
        case (true, true): return .concurrent
        }
    }

    private func makeCloudRulePayload() -> (rules: [Rule], inputSourceNames: [String: String]) {
        var inputSourceNames: [String: String] = [:]
        let cloudRules = rules.map { localRule in
            var cloudRule = localRule
            let cloudID = localRule.syncedInputSourceID ?? localRule.inputSourceID
            let sourceName = localRule.syncedInputSourceName ?? InputSourceManager.name(forID: localRule.inputSourceID)

            cloudRule.inputSourceID = cloudID
            cloudRule.syncedInputSourceID = nil
            cloudRule.syncedInputSourceName = nil
            if let sourceName {
                inputSourceNames[cloudID] = sourceName
            }
            return cloudRule
        }
        return (cloudRules, inputSourceNames)
    }

    private func resolveInputSources(
        rules cloudRules: [Rule],
        defaultInputSource cloudDefaultInputSource: String,
        names: [String: String]
    ) -> (rules: [Rule], defaultInputSource: String) {
        let availableSources = InputSourceManager.selectableSources()
        let availableIDs = Set(availableSources.map(\.id))
        var resolvedIDs: [String: String] = [:]
        var deferredIDs: Set<String> = []

        func resolve(_ cloudID: String) -> String {
            guard !cloudID.isEmpty else { return "" }
            if availableIDs.contains(cloudID) { return cloudID }
            if let resolved = resolvedIDs[cloudID] { return resolved }
            if deferredIDs.contains(cloudID) { return cloudID }

            if let savedReplacement = inputSourceReplacements[cloudID],
               availableIDs.contains(savedReplacement) {
                resolvedIDs[cloudID] = savedReplacement
                return savedReplacement
            }

            if inputSourceReplacements.removeValue(forKey: cloudID) != nil {
                UserDefaults.standard.set(inputSourceReplacements, forKey: Self.inputSourceReplacementsKey)
            }
            guard let replacement = promptForInputSourceReplacement(
                missingID: cloudID,
                missingName: names[cloudID],
                availableSources: availableSources
            ) else {
                deferredIDs.insert(cloudID)
                return cloudID
            }

            inputSourceReplacements[cloudID] = replacement
            UserDefaults.standard.set(inputSourceReplacements, forKey: Self.inputSourceReplacementsKey)
            resolvedIDs[cloudID] = replacement
            return replacement
        }

        let localRules = cloudRules.map { cloudRule in
            let cloudID = cloudRule.syncedInputSourceID ?? cloudRule.inputSourceID
            let localID = resolve(cloudID)
            var localRule = cloudRule
            localRule.inputSourceID = localID

            if localID != cloudID || !availableIDs.contains(cloudID) {
                localRule.syncedInputSourceID = cloudID
                localRule.syncedInputSourceName = names[cloudID] ?? cloudRule.syncedInputSourceName
            } else {
                localRule.syncedInputSourceID = nil
                localRule.syncedInputSourceName = nil
            }
            return localRule
        }

        return (localRules, resolve(cloudDefaultInputSource))
    }

    private func promptForInputSourceReplacement(
        missingID: String,
        missingName: String?,
        availableSources: [InputSource]
    ) -> String? {
        guard !availableSources.isEmpty else { return nil }

        let displayName = missingName ?? missingID
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("sync.missing_input_title", displayName)
        alert.informativeText = L10n.string("sync.missing_input_message")

        let picker = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 300, height: 26), pullsDown: false)
        availableSources.forEach { picker.addItem(withTitle: $0.name) }
        if let currentID = InputSourceManager.currentID(),
           let currentIndex = availableSources.firstIndex(where: { $0.id == currentID }) {
            picker.selectItem(at: currentIndex)
        }
        alert.accessoryView = picker
        alert.addButton(withTitle: L10n.string("sync.use_replacement"))
        alert.addButton(withTitle: L10n.string("sync.not_now"))

        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn,
              picker.indexOfSelectedItem >= 0 else {
            return nil
        }
        return availableSources[picker.indexOfSelectedItem].id
    }

    private func applySyncedDefaultInputSource(localID: String, cloudID: String, cloudName: String?) {
        if !cloudID.isEmpty && (localID != cloudID || InputSourceManager.name(forID: cloudID) == nil) {
            syncedDefaultInputSourceID = cloudID
            syncedDefaultInputSourceName = cloudName
            UserDefaults.standard.set(cloudID, forKey: Self.syncedDefaultInputSourceIDKey)
            UserDefaults.standard.set(cloudName, forKey: Self.syncedDefaultInputSourceNameKey)
        } else {
            clearSyncedDefaultInputSource()
        }
        defaultInputSource = localID
    }

    private func clearSyncedDefaultInputSource() {
        syncedDefaultInputSourceID = nil
        syncedDefaultInputSourceName = nil
        UserDefaults.standard.removeObject(forKey: Self.syncedDefaultInputSourceIDKey)
        UserDefaults.standard.removeObject(forKey: Self.syncedDefaultInputSourceNameKey)
    }

    private func loadLegacyCloudValues() -> Bool {
        guard cloudStore.object(forKey: CloudKey.rules) != nil ||
                cloudStore.object(forKey: CloudKey.enabled) != nil else {
            return false
        }

        isApplyingCloudValues = true
        defer { isApplyingCloudValues = false }

        if let data = cloudStore.data(forKey: CloudKey.rules),
           let cloudRules = try? JSONDecoder().decode([Rule].self, from: data) {
            rules = Self.sanitizedStoredRules(cloudRules)
        }
        if cloudStore.object(forKey: CloudKey.enabled) != nil {
            enabled = cloudStore.bool(forKey: CloudKey.enabled)
        }
        if cloudStore.object(forKey: CloudKey.globalLockEnabled) != nil {
            globalLockEnabled = cloudStore.bool(forKey: CloudKey.globalLockEnabled)
        }
        if cloudStore.object(forKey: CloudKey.debugMode) != nil {
            debugMode = cloudStore.bool(forKey: CloudKey.debugMode)
        }
        if let value = cloudStore.object(forKey: CloudKey.menuRuleCount) as? NSNumber {
            menuRuleCount = Self.normalizedMenuRuleCount(value.intValue)
        }
        if let value = cloudStore.string(forKey: CloudKey.defaultInputSource) {
            defaultInputSource = value
        }
        if cloudStore.object(forKey: CloudKey.showSwitchNotification) != nil {
            showSwitchNotification = cloudStore.bool(forKey: CloudKey.showSwitchNotification)
        }
        if let value = cloudStore.string(forKey: CloudKey.notificationPosition),
           let position = NotificationPosition(rawValue: value) {
            notificationPosition = position
        }
        if let value = cloudStore.object(forKey: CloudKey.notificationDuration) as? NSNumber {
            notificationDuration = min(max(value.doubleValue, 0.1), 4.0)
        }
        return true
    }

    @objc private func cloudStoreDidChange(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            guard let self, PurchaseManager.shared.isPro, self.cloudSyncEnabled else { return }

            let reason = (notification.userInfo?[NSUbiquitousKeyValueStoreChangeReasonKey] as? NSNumber)?.intValue
            if reason == NSUbiquitousKeyValueStoreQuotaViolationChange {
                self.cloudSyncStatus = .failed
                return
            }

            self.resolveCloudState()
        }
    }

    @objc private func proEntitlementDidChange() {
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if PurchaseManager.shared.isPro {
                if self.cloudSyncEnabled {
                    self.startCloudSync()
                }
            } else {
                self.initialCloudSyncTask?.cancel()
                self.initialCloudSyncTask = nil
                self.cloudSyncStatus = self.cloudSyncEnabled ? .requiresPro : .disabled
            }
        }
    }

    func rule(for bundleID: String) -> Rule? {
        rules.first { $0.bundleID == bundleID }
    }

    static func normalizedMenuRuleCount(_ value: Int) -> Int {
        if value <= 0 { return 0 }
        if value <= 5 { return 5 }
        if value <= 10 { return 10 }
        return 15
    }

    static func sanitizedStoredRules(_ storedRules: [Rule]) -> [Rule] {
        var seenBundleIDs: Set<String> = []
        return storedRules.prefix(Self.maximumRuleCount).compactMap { rule in
            let bundleID = rule.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let appName = rule.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let inputSourceID = rule.inputSourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty,
                  bundleID.count <= 512,
                  !inputSourceID.isEmpty,
                  inputSourceID.count <= 512,
                  seenBundleIDs.insert(bundleID).inserted else {
                return nil
            }
            return Rule(
                bundleID: bundleID,
                appName: appName.isEmpty ? bundleID : appName,
                inputSourceID: inputSourceID,
                isLocked: rule.isLocked,
                syncedInputSourceID: rule.syncedInputSourceID,
                syncedInputSourceName: rule.syncedInputSourceName,
                isAutoLearned: rule.isAutoLearned
            )
        }
    }

    func activeRule(for bundleID: String) -> Rule? {
        guard let index = rules.firstIndex(where: { $0.bundleID == bundleID }) else { return nil }
        guard PurchaseManager.shared.isPro || index < PurchaseManager.freeRuleLimit else { return nil }
        return rules[index]
    }

    var enabledShortcut: GlobalShortcutOption {
        GlobalShortcutOption.option(for: enabledShortcutID, fallback: .defaultEnabled)
    }

    var globalLockShortcut: GlobalShortcutOption {
        GlobalShortcutOption.option(for: globalLockShortcutID, fallback: .defaultGlobalLock)
    }

    var shortcutsConflict: Bool {
        enabledShortcutID != "disabled" && enabledShortcutID == globalLockShortcutID
    }

    func recordLearningObservation(bundleID: String, inputSourceID: String) -> Bool {
        guard PurchaseManager.shared.isPro else { return false }
        let now = Date().timeIntervalSince1970
        let cutoff = now - Self.learningHistoryLifetime
        var observations = (learningHistory[bundleID] ?? []).filter { $0.observedAt >= cutoff }
        observations.append(LearningObservation(inputSourceID: inputSourceID, observedAt: now))
        observations = Array(observations.suffix(Self.learningHistoryLimit))
        learningHistory[bundleID] = observations
        saveLearningHistory()

        let matchingCount = observations.filter { $0.inputSourceID == inputSourceID }.count
        let confidence = Double(matchingCount) / Double(observations.count)
        return matchingCount >= Self.learningMinimumObservations && confidence >= Self.learningConfidence
    }

    private func clearLearningHistory(for bundleID: String) {
        learningHistory.removeValue(forKey: bundleID)
        saveLearningHistory()
    }

    private func saveLearningHistory() {
        guard let data = try? JSONEncoder().encode(learningHistory) else { return }
        UserDefaults.standard.set(data, forKey: Self.learningHistoryKey)
    }

    var defaultInputSourceDisplayName: String {
        InputSourceManager.name(forID: defaultInputSource)
            ?? syncedDefaultInputSourceName
            ?? defaultInputSource
    }

    var canAddRule: Bool {
        PurchaseManager.shared.isPro || rules.count < PurchaseManager.freeRuleLimit
    }

    func canAddRule(bundleID: String) -> Bool {
        rules.contains(where: { $0.bundleID == bundleID }) || canAddRule
    }

    static func isRuleLockActive(
        bundleID: String,
        rules: [Rule],
        isPro: Bool
    ) -> Bool {
        guard let index = rules.firstIndex(where: { $0.bundleID == bundleID }),
              rules[index].isLocked else { return false }
        if isPro { return true }
        guard index < PurchaseManager.freeRuleLimit else { return false }
        return rules.prefix(PurchaseManager.freeRuleLimit)
            .filter(\.isLocked)
            .prefix(PurchaseManager.freeLockedRuleLimit)
            .contains { $0.bundleID == bundleID }
    }

    static func canEnableRuleLock(
        bundleID: String,
        rules: [Rule],
        isPro: Bool
    ) -> Bool {
        guard let index = rules.firstIndex(where: { $0.bundleID == bundleID }) else { return false }
        if isPro { return true }
        if rules[index].isLocked {
            return isRuleLockActive(bundleID: bundleID, rules: rules, isPro: false)
        }
        guard index < PurchaseManager.freeRuleLimit else { return false }
        let lockedFreeRules = rules.prefix(PurchaseManager.freeRuleLimit).filter(\.isLocked).count
        return lockedFreeRules < PurchaseManager.freeLockedRuleLimit
    }

    func isRuleLockActive(bundleID: String) -> Bool {
        Self.isRuleLockActive(
            bundleID: bundleID,
            rules: rules,
            isPro: PurchaseManager.shared.isPro
        )
    }

    @discardableResult
    func toggleRuleLock(bundleID: String) -> Bool {
        guard let index = rules.firstIndex(where: { $0.bundleID == bundleID }) else { return false }
        if rules[index].isLocked {
            rules[index].isLocked = false
            rules[index].isAutoLearned = false
            return true
        }
        guard Self.canEnableRuleLock(
            bundleID: bundleID,
            rules: rules,
            isPro: PurchaseManager.shared.isPro
        ) else { return false }
        rules[index].isLocked = true
        rules[index].isAutoLearned = false
        return true
    }

    @discardableResult
    func setRule(
        bundleID: String,
        appName: String,
        inputSourceID: String,
        isLocked: Bool? = nil,
        isAutoLearned: Bool = false
    ) -> Bool {
        let normalizedBundleID = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedAppName = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedInputSourceID = inputSourceID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedBundleID.isEmpty,
              normalizedBundleID.count <= 512,
              !normalizedInputSourceID.isEmpty,
              normalizedInputSourceID.count <= 512 else {
            return false
        }

        if let index = rules.firstIndex(where: { $0.bundleID == normalizedBundleID }) {
            rules[index].inputSourceID = normalizedInputSourceID
            rules[index].appName = normalizedAppName.isEmpty ? normalizedBundleID : normalizedAppName
            if let isLocked {
                rules[index].isLocked = isLocked
            }
            rules[index].syncedInputSourceID = nil
            rules[index].syncedInputSourceName = nil
            rules[index].isAutoLearned = isAutoLearned
            clearLearningHistory(for: normalizedBundleID)
            return true
        } else {
            guard canAddRule else { return false }
            rules.append(
                Rule(
                    bundleID: normalizedBundleID,
                    appName: normalizedAppName.isEmpty ? normalizedBundleID : normalizedAppName,
                    inputSourceID: normalizedInputSourceID,
                    isLocked: isLocked ?? false,
                    isAutoLearned: isAutoLearned
                )
            )
            clearLearningHistory(for: normalizedBundleID)
            return true
        }
    }

    func removeRule(bundleID: String) {
        rules.removeAll { $0.bundleID == bundleID }
    }

    @discardableResult
    func removeAutoLearnedRule(bundleID: String) -> Bool {
        guard let rule = rule(for: bundleID), rule.isAutoLearned else { return false }
        rules.removeAll { $0.bundleID == bundleID }
        clearLearningHistory(for: bundleID)
        return true
    }

    // 新增：批量删除
    func removeRules(bundleIDs: Set<String>) {
        rules.removeAll { bundleIDs.contains($0.bundleID) }
    }

    // 新增：批量设置输入法
    func setInputSource(_ inputSourceID: String, for bundleIDs: Set<String>) {
        for index in rules.indices where bundleIDs.contains(rules[index].bundleID) {
            rules[index].inputSourceID = inputSourceID
            rules[index].syncedInputSourceID = nil
            rules[index].syncedInputSourceName = nil
            rules[index].isAutoLearned = false
        }
    }

    // 新增：导出规则
    func exportRules() -> Data? {
        guard PurchaseManager.shared.isPro else { return nil }
        return try? JSONEncoder().encode(makeCloudRulePayload().rules)
    }

    // 新增：导入规则
    func importRules(from data: Data, merge: Bool = false) -> Bool {
        guard PurchaseManager.shared.isPro else { return false }
        guard data.count <= Self.maximumImportSize else { return false }
        guard let imported = try? JSONDecoder().decode([Rule].self, from: data) else {
            return false
        }

        guard let validated = Self.validatedImportedRules(imported) else { return false }

        if merge {
            // 合并模式：保留现有规则，只添加新的
            for rule in validated {
                if !rules.contains(where: { $0.bundleID == rule.bundleID }) {
                    rules.append(rule)
                }
            }
        } else {
            // 替换模式：完全替换
            rules = validated
        }
        return true
    }

    static func validatedImportedRules(_ imported: [Rule]) -> [Rule]? {
        guard imported.count <= Self.maximumRuleCount else { return nil }
        var seenBundleIDs: Set<String> = []
        var validated: [Rule] = []
        validated.reserveCapacity(imported.count)
        for rule in imported {
            let bundleID = rule.bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
            let appName = rule.appName.trimmingCharacters(in: .whitespacesAndNewlines)
            let inputSourceID = rule.inputSourceID.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !bundleID.isEmpty,
                  bundleID.count <= 512,
                  !inputSourceID.isEmpty,
                  inputSourceID.count <= 512,
                  seenBundleIDs.insert(bundleID).inserted else {
                return nil
            }
            validated.append(
                Rule(
                    bundleID: bundleID,
                    appName: appName.isEmpty ? bundleID : appName,
                    inputSourceID: inputSourceID,
                    isLocked: rule.isLocked,
                    isAutoLearned: false
                )
            )
        }
        return validated
    }

    // 新增：检测无效规则（应用已卸载）
    func detectInvalidRules() -> [Rule] {
        return rules.filter { rule in
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) == nil
        }
    }

    // 新增：清理无效规则
    func removeInvalidRules() -> Int {
        guard PurchaseManager.shared.isPro else { return 0 }
        let invalidRules = detectInvalidRules()
        let count = invalidRules.count
        rules.removeAll { rule in
            invalidRules.contains(where: { $0.bundleID == rule.bundleID })
        }
        return count
    }

    private func save() {
        if let data = try? JSONEncoder().encode(rules) {
            UserDefaults.standard.set(data, forKey: Self.rulesKey)
        }
    }
}
