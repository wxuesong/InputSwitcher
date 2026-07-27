import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject private var store = RuleStore.shared
    @ObservedObject private var inputSources = InputSourceCatalog.shared
    @State private var selectedSection: SettingsSection = .rules
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: $selectedSection) {
                Section {
                    Label(L10n.string("settings.tab_rules"), systemImage: "list.bullet")
                        .tag(SettingsSection.rules)
                    Label(L10n.string("settings.sidebar_general"), systemImage: "gear")
                        .tag(SettingsSection.general)
                    Label(L10n.string("settings.notifications_section"), systemImage: "bell")
                        .tag(SettingsSection.notifications)
                    Label(L10n.string("settings.shortcuts_section"), systemImage: "command")
                        .tag(SettingsSection.shortcuts)
                    Label(L10n.string("settings.data_and_sync"), systemImage: "arrow.triangle.2.circlepath.icloud")
                        .tag(SettingsSection.sync)
                    Label(L10n.string("settings.advanced_settings"), systemImage: "gearshape.2")
                        .tag(SettingsSection.advanced)
                    Label(L10n.string("pro.required_badge"), systemImage: "crown")
                        .tag(SettingsSection.pro)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle(L10n.string("settings.title"))
            .navigationSplitViewColumnWidth(min: 240, ideal: 250, max: 300)
        } detail: {
            Group {
                switch selectedSection {
                case .rules:
                    RulesTab(store: store, sources: inputSources.sources)
                case .general:
                    GeneralTab(store: store, sources: inputSources.sources, section: .general)
                case .notifications:
                    GeneralTab(store: store, sources: inputSources.sources, section: .notifications)
                case .shortcuts:
                    GeneralTab(store: store, sources: inputSources.sources, section: .shortcuts)
                case .sync:
                    GeneralTab(store: store, sources: inputSources.sources, section: .sync)
                case .advanced:
                    GeneralTab(store: store, sources: inputSources.sources, section: .advanced)
                case .pro:
                    GeneralTab(store: store, sources: inputSources.sources, section: .pro)
                }
            }
            .navigationTitle(L10n.string(selectedSection.titleKey))
        }
        .hidingSidebarToggle()
        .frame(width: 860, height: 560)
    }
}

private extension View {
    @ViewBuilder
    func hidingSidebarToggle() -> some View {
        if #available(macOS 14.0, *) {
            toolbar(removing: .sidebarToggle)
                .background(SidebarToggleHider())
        } else {
            background(SidebarToggleHider())
        }
    }
}

private struct SidebarToggleHider: NSViewRepresentable {
    func makeNSView(context: Context) -> SidebarToggleTrackingView {
        let view = SidebarToggleTrackingView(frame: .zero)
        view.removeToggleButtonWhenReady()
        return view
    }

    func updateNSView(_ view: SidebarToggleTrackingView, context: Context) {
        view.removeToggleButtonWhenReady()
    }
}

private final class SidebarToggleTrackingView: NSView {
    private weak var observedWindow: NSWindow?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func windowDidUpdate(_ notification: Notification) {
        removeToggleButtonWhenReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let observedWindow {
            NotificationCenter.default.removeObserver(
                self,
                name: NSWindow.didUpdateNotification,
                object: observedWindow
            )
        }
        observedWindow = window
        if let window {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidUpdate(_:)),
                name: NSWindow.didUpdateNotification,
                object: window
            )
        }
        removeToggleButtonWhenReady()
    }

    func removeToggleButtonWhenReady() {
        DispatchQueue.main.async {
            guard let toolbar = self.window?.toolbar else { return }
            let matchingIndexes = toolbar.items.indices.filter { index in
                let identifier = toolbar.items[index].itemIdentifier
                if identifier == .toggleSidebar { return true }
                let normalized = identifier.rawValue
                    .lowercased()
                    .filter(\.isLetter)
                return normalized.contains("togglesidebar") ||
                    normalized.contains("sidebartoggle")
            }
            for index in matchingIndexes.reversed() {
                toolbar.removeItem(at: index)
            }
            if !matchingIndexes.isEmpty, let observedWindow = self.observedWindow {
                NotificationCenter.default.removeObserver(
                    self,
                    name: NSWindow.didUpdateNotification,
                    object: observedWindow
                )
                self.observedWindow = nil
            }
        }
    }
}

private enum SettingsSection: String, Hashable {
    case rules
    case general
    case notifications
    case shortcuts
    case sync
    case advanced
    case pro

    var titleKey: String {
        switch self {
        case .rules: return "settings.tab_rules"
        case .general: return "settings.sidebar_general"
        case .notifications: return "settings.notifications_section"
        case .shortcuts: return "settings.shortcuts_section"
        case .sync: return "settings.data_and_sync"
        case .advanced: return "settings.advanced_settings"
        case .pro: return "pro.required_badge"
        }
    }
}

// MARK: - 规则选项卡
private enum RuleLayout {
    static let spacing: CGFloat = 12
    static let selectionWidth: CGFloat = 24
    static let iconWidth: CGFloat = 36
    static let inputWidth: CGFloat = 190
    static let actionWidth: CGFloat = 24
}

private struct RulesTab: View {
    @ObservedObject var store: RuleStore
    @ObservedObject private var purchase = PurchaseManager.shared
    let sources: [InputSource]

    @State private var selectedRules: Set<String> = []
    @State private var showingBatchInputPicker = false
    @State private var searchText = ""
    @State private var invalidRuleCount = 0

    // 过滤后的规则
    private var filteredRules: [Rule] {
        if searchText.isEmpty {
            return store.rules
        }
        return store.rules.filter { rule in
            rule.appName.localizedCaseInsensitiveContains(searchText) ||
            rule.bundleID.localizedCaseInsensitiveContains(searchText)
        }
    }

    private var allVisibleRulesSelected: Bool {
        !filteredRules.isEmpty && filteredRules.allSatisfy { selectedRules.contains($0.bundleID) }
    }

    private var someVisibleRulesSelected: Bool {
        filteredRules.contains { selectedRules.contains($0.bundleID) } && !allVisibleRulesSelected
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            if store.rules.isEmpty {
                emptyState
            } else if filteredRules.isEmpty {
                noResultsState
            } else {
                VStack(spacing: 0) {
                    listHeader
                        .frame(height: 36)
                    Divider()

                    GeometryReader { geometry in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach($store.rules) { $rule in
                                    if filteredRules.contains(where: { $0.id == rule.id }) {
                                        RuleRow(
                                            rule: $rule,
                                            sources: sources,
                                            isSelected: selectedRules.contains(rule.bundleID),
                                            isRuleLocked: store.isRuleLockActive(bundleID: rule.bundleID),
                                            isGloballyLocked: purchase.isPro && store.globalLockEnabled,
                                            onToggleSelection: { toggleSelection(rule.bundleID) },
                                            onToggleLock: { toggleRuleLock(rule.bundleID) },
                                            onDelete: { deleteRule(rule.bundleID) }
                                        )

                                        Divider()
                                            .padding(.leading, 72)
                                    }
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                            .padding(.horizontal, 16)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }

            if !selectedRules.isEmpty {
                Divider()
                selectionBar
            }
        }
        .onChange(of: store.rules) { rules in
            let validBundleIDs = Set(rules.map(\.bundleID))
            selectedRules.formIntersection(validBundleIDs)
            refreshInvalidRuleCount()
        }
        .onAppear(perform: refreshInvalidRuleCount)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.string("settings.rules_title"))
                        .font(.title2.weight(.semibold))
                    Text(
                        purchase.isPro
                            ? L10n.string("settings.rules_summary", store.rules.count)
                            : L10n.string(
                                "settings.rules_summary_free",
                                store.rules.count,
                                PurchaseManager.freeRuleLimit
                            )
                    )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    if invalidRuleCount > 0 {
                        Label(
                            L10n.string("settings.invalid_rules_summary", invalidRuleCount),
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.caption)
                        .foregroundStyle(.orange)
                    }
                }

                Spacer()

                Button(action: toggleGlobalLock) {
                    Label(
                        L10n.string("settings.global_lock"),
                        systemImage: purchase.isPro
                            ? (store.globalLockEnabled ? "lock.shield.fill" : "lock.shield")
                            : "lock.fill"
                    )
                    .lineLimit(1)
                    .foregroundStyle(
                        purchase.isPro && store.globalLockEnabled
                            ? Color.accentColor
                            : Color.primary
                    )
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .help(L10n.string("settings.global_lock"))

                Button(action: addApp) {
                    Label(L10n.string("settings.add_app"), systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }

            if !store.rules.isEmpty {
                HStack {
                    HStack(spacing: 7) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField(L10n.string("settings.search_placeholder"), text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button(action: { searchText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(L10n.string("settings.clear_search"))
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.primary.opacity(0.045))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay {
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(Color.primary.opacity(0.10), lineWidth: 0.5)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var listHeader: some View {
        HStack(spacing: RuleLayout.spacing) {
            Button(action: toggleSelectAll) {
                Image(systemName: allVisibleRulesSelected
                    ? "checklist.checked"
                    : (someVisibleRulesSelected ? "minus.square" : "checklist"))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(allVisibleRulesSelected || someVisibleRulesSelected
                        ? Color.accentColor
                        : Color.secondary)
                    .frame(width: RuleLayout.selectionWidth, height: RuleLayout.selectionWidth)
            }
            .buttonStyle(.plain)
            .help(L10n.string(allVisibleRulesSelected ? "settings.deselect_all" : "settings.select_all"))

            Color.clear.frame(width: RuleLayout.iconWidth)
            Text(L10n.string("settings.app_name"))
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(L10n.string("settings.input_method"))
                .frame(width: RuleLayout.inputWidth, alignment: .leading)
            Image(systemName: "lock")
                .frame(width: RuleLayout.actionWidth)
                .foregroundStyle(purchase.isPro && store.globalLockEnabled ? Color.accentColor : Color.secondary)
                .help(L10n.string("settings.locked"))
            Color.clear.frame(width: RuleLayout.actionWidth)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 22)
        .background(Color.primary.opacity(0.025))
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 42, weight: .regular))
                .foregroundStyle(.tertiary)
            Text(L10n.string("settings.empty_title"))
                .font(.title3.weight(.semibold))
            Text(L10n.string("settings.empty_description"))
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(action: addApp) {
                Label(L10n.string("settings.add_app"), systemImage: "plus")
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
    }

    private var noResultsState: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(.tertiary)
            Text(L10n.string("settings.no_results"))
                .font(.headline)
            Button(L10n.string("settings.clear_search")) {
                searchText = ""
            }
            .buttonStyle(.link)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var selectionBar: some View {
        HStack(spacing: 12) {
            Label(L10n.string("settings.selected_count", selectedRules.count), systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button(L10n.string("settings.batch_set_input")) {
                showingBatchInputPicker = true
            }
            .popover(isPresented: $showingBatchInputPicker) {
                BatchInputPicker(sources: sources) { inputSourceID in
                    store.setInputSource(inputSourceID, for: selectedRules)
                    selectedRules.removeAll()
                    showingBatchInputPicker = false
                }
            }

            Button(L10n.string("settings.batch_delete"), role: .destructive) {
                store.removeRules(bundleIDs: selectedRules)
                selectedRules.removeAll()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func refreshInvalidRuleCount() {
        invalidRuleCount = store.detectInvalidRules().count
    }

    private func toggleSelection(_ bundleID: String) {
        if selectedRules.contains(bundleID) {
            selectedRules.remove(bundleID)
        } else {
            selectedRules.insert(bundleID)
        }
    }

    private func deleteRule(_ bundleID: String) {
        selectedRules.remove(bundleID)
        store.removeRule(bundleID: bundleID)
    }

    private func toggleRuleLock(_ bundleID: String) {
        guard store.toggleRuleLock(bundleID: bundleID) else {
            showProUpgrade()
            return
        }
    }

    private func toggleSelectAll() {
        let visibleBundleIDs = Set(filteredRules.map(\.bundleID))
        if allVisibleRulesSelected {
            selectedRules.subtract(visibleBundleIDs)
        } else {
            selectedRules.formUnion(visibleBundleIDs)
        }
    }

    private func addApp() {
        guard store.canAddRule else {
            showProUpgrade()
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = true
        panel.prompt = L10n.string("settings.add_app")

        guard panel.runModal() == .OK else { return }

        // 优先使用默认输入法，否则使用当前输入法
        let defaultSource: String
        if !store.defaultInputSource.isEmpty {
            defaultSource = store.defaultInputSource
        } else if let currentID = InputSourceManager.currentID() {
            defaultSource = currentID
        } else {
            defaultSource = sources.first?.id ?? ""
        }

        var reachedFreeLimit = false
        for url in panel.urls {
            guard let bundle = Bundle(url: url),
                  let bundleID = bundle.bundleIdentifier
            else { continue }
            let name = (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
                ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
                ?? url.deletingPathExtension().lastPathComponent
            if store.rule(for: bundleID) == nil {
                if !store.setRule(bundleID: bundleID, appName: name, inputSourceID: defaultSource) {
                    reachedFreeLimit = true
                    break
                }
            }
        }
        if reachedFreeLimit {
            showProUpgrade()
        }
    }

    private func toggleGlobalLock() {
        guard purchase.isPro else {
            showProUpgrade()
            return
        }
        store.globalLockEnabled.toggle()
    }

    private func showProUpgrade() {
        ProWindowController.shared.show()
    }
}

// MARK: - 批量输入法选择器
private struct BatchInputPicker: View {
    let sources: [InputSource]
    let onSelect: (String) -> Void

    var body: some View {
        VStack(spacing: 12) {
            Text(L10n.string("settings.batch_set_input"))
                .font(.headline)

            ForEach(sources) { source in
                Button(source.name) {
                    onSelect(source.id)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .frame(minWidth: 200)
    }
}

// MARK: - 设置分区
private struct GeneralTab: View {
    @ObservedObject var store: RuleStore
    let sources: [InputSource]
    let section: SettingsSection

    @ViewBuilder
    var body: some View {
        if section == .pro {
            ProSettingsPage()
        } else {
            Form {
                sectionContent
            }
            .formStyle(.grouped)
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .general:
            RuntimeSettingsPage(store: store)
            RuleBehaviorPage(store: store, sources: sources)
            MenuBarSettingsPage(store: store)
        case .notifications:
            NotificationsPage(store: store)
        case .shortcuts:
            ShortcutsPage(store: store)
        case .sync:
            SyncPage(store: store)
        case .advanced:
            AdvancedPage(store: store)
        case .pro:
            EmptyView()
        case .rules:
            EmptyView()
        }
    }
}

private struct RuntimeSettingsPage: View {
    @ObservedObject var store: RuleStore

    var body: some View {
        Section {
            SettingRow(
                title: L10n.string("settings.enabled"),
                description: L10n.string("settings.enabled_description")
            ) {
                Toggle("", isOn: $store.enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            SettingRow(
                title: L10n.string("settings.launch_at_login"),
                description: store.launchAtLoginError ?? L10n.string("settings.launch_at_login_description")
            ) {
                Toggle("", isOn: $store.launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }
        } header: {
            Text(L10n.string("settings.runtime_section"))
        }
    }
}

private struct MenuBarSettingsPage: View {
    @ObservedObject var store: RuleStore

    var body: some View {
        Section {
            SettingRow(
                title: L10n.string("settings.menu_rule_count"),
                description: L10n.string("settings.menu_rule_count_description")
            ) {
                Picker("", selection: $store.menuRuleCount) {
                    Text(L10n.string("settings.menu_rule_none")).tag(0)
                    Text(L10n.string("settings.menu_rule_5")).tag(5)
                    Text(L10n.string("settings.menu_rule_10")).tag(10)
                    Text(L10n.string("settings.menu_rule_15")).tag(15)
                }
                .labelsHidden()
                .frame(width: 120, alignment: .trailing)
            }
        } header: {
            Text(L10n.string("settings.menu_bar_section"))
        }
    }
}

private enum LegalDocumentURL {
    static let privacyPolicy = URL(string: "https://wxuesong.github.io/InputSwitcher/privacy/")!
    static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
}

private struct ProSettingsPage: View {
    @ObservedObject private var purchase = PurchaseManager.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 7) {
                    AdaptiveApplicationIcon(size: 84)

                    Text(L10n.string("pro.settings_page_title"))
                        .font(.title2.weight(.semibold))

                    Text(
                        purchase.isPro
                            ? L10n.string("pro.thank_you")
                            : L10n.string("pro.subtitle", PurchaseManager.freeRuleLimit)
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 430)
                }

                VStack(spacing: 0) {
                    ForEach(Array(ProFeatureCatalog.items.enumerated()), id: \.element.titleKey) { index, feature in
                        HStack(spacing: 12) {
                            Image(systemName: feature.icon)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .frame(width: 28, height: 28)
                                .background(Color.accentColor.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 6))

                            Text(L10n.string(feature.titleKey))
                                .font(.callout.weight(.medium))

                            Spacer()

                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(purchase.isPro ? Color.green : Color.secondary)

                        }
                        .padding(.horizontal, 14)
                        .frame(height: 40)

                        if index < ProFeatureCatalog.items.count - 1 {
                            Divider()
                                .padding(.leading, 54)
                        }
                    }
                }
                .frame(maxWidth: 470)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                }

                if purchase.isPro {
                    Label(L10n.string("pro.unlocked"), systemImage: "checkmark.seal.fill")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(.green)
                } else {
                    HStack(spacing: 12) {
                        Button {
                            Task { await purchase.restorePurchases() }
                        } label: {
                            Label(L10n.string("pro.restore"), systemImage: "arrow.clockwise")
                        }
                        .disabled(isBusy)

                        Button {
                            Task { await purchase.purchasePro() }
                        } label: {
                            Label(
                                L10n.string("pro.purchase", purchase.displayPrice),
                                systemImage: "cart.fill"
                            )
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy || purchase.product == nil)
                    }
                }

                HStack(spacing: 8) {
                    Link(
                        L10n.string("legal.privacy_policy"),
                        destination: LegalDocumentURL.privacyPolicy
                    )
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Link(
                        L10n.string("legal.terms_of_use"),
                        destination: LegalDocumentURL.termsOfUse
                    )
                }
                .font(.caption)

                purchaseStatus
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
        .task {
            await purchase.refresh()
        }
    }

    @ViewBuilder
    private var purchaseStatus: some View {
        switch purchase.activity {
        case .loading:
            ProgressView(L10n.string("pro.loading"))
                .controlSize(.small)
        case .purchasing:
            ProgressView(L10n.string("pro.purchasing"))
                .controlSize(.small)
        case .restoring:
            ProgressView(L10n.string("pro.restoring"))
                .controlSize(.small)
        case .pending:
            Label(L10n.string("pro.pending"), systemImage: "hourglass")
                .font(.callout)
                .foregroundStyle(.orange)
        case .failed:
            Label(L10n.string("pro.failed"), systemImage: "exclamationmark.triangle.fill")
                .font(.callout)
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
        case .idle:
            EmptyView()
        }
    }

    private var isBusy: Bool {
        purchase.activity == .loading ||
            purchase.activity == .purchasing ||
            purchase.activity == .restoring
    }
}

private struct RuleBehaviorPage: View {
    @ObservedObject var store: RuleStore
    let sources: [InputSource]
    @ObservedObject private var purchase = PurchaseManager.shared

    var body: some View {
        Section {
            SettingRow(
                title: L10n.string("settings.default_input_source"),
                description: L10n.string("settings.default_input_source_description")
            ) {
                Picker("", selection: $store.defaultInputSource) {
                    Text(L10n.string("settings.keep_current")).tag("")
                    Divider()
                    ForEach(sources) { source in
                        Text(source.name).tag(source.id)
                    }
                    if !store.defaultInputSource.isEmpty,
                       !sources.contains(where: { $0.id == store.defaultInputSource }) {
                        Text(store.defaultInputSourceDisplayName).tag(store.defaultInputSource)
                    }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .trailing)
            }

            SettingRow(
                title: L10n.string("settings.smart_learning"),
                description: purchase.isPro
                    ? L10n.string("settings.smart_learning_description", RuleStore.learningMinimumObservations)
                    : L10n.string("pro.required_description")
            ) {
                if purchase.isPro {
                    Toggle("", isOn: $store.smartLearningEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                } else {
                    Button(action: { ProWindowController.shared.show() }) {
                        Label(L10n.string("pro.required_badge"), systemImage: "lock.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }

            SettingRow(
                title: L10n.string("settings.global_lock"),
                description: purchase.isPro
                    ? L10n.string("settings.global_lock_description")
                    : L10n.string("pro.required_description")
            ) {
                if purchase.isPro {
                    Toggle("", isOn: $store.globalLockEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                } else {
                    Button(action: { ProWindowController.shared.show() }) {
                        Label(L10n.string("pro.required_badge"), systemImage: "lock.fill")
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Text(L10n.string("settings.rules_section"))
        }
    }
}

private struct NotificationsPage: View {
    @ObservedObject var store: RuleStore

    var body: some View {
        Section {
            SettingRow(
                title: L10n.string("settings.show_switch_notification"),
                description: L10n.string("settings.show_switch_notification_description")
            ) {
                Toggle("", isOn: $store.showSwitchNotification)
                    .toggleStyle(.switch)
                    .labelsHidden()
            }

            SettingRow(
                title: L10n.string("settings.notification_position"),
                description: L10n.string("settings.notification_position_description")
            ) {
                Picker("", selection: $store.notificationPosition) {
                    ForEach(NotificationPosition.allCases) { position in
                        Text(notificationPositionLabel(position)).tag(position)
                    }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .trailing)
            }
            .disabled(!store.showSwitchNotification)

            SettingRow(
                title: L10n.string("settings.notification_duration"),
                description: L10n.string("settings.notification_duration_description")
            ) {
                HStack(spacing: 8) {
                    Text(String(format: "%.1f s", store.notificationDuration))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 38, alignment: .trailing)
                    Slider(value: roundedNotificationDuration, in: 0.1...4.0)
                        .frame(width: 180)
                }
            }
            .disabled(!store.showSwitchNotification)
        }
    }

    private var roundedNotificationDuration: Binding<Double> {
        Binding(
            get: { store.notificationDuration },
            set: { store.notificationDuration = ($0 * 10).rounded() / 10 }
        )
    }

    private func notificationPositionLabel(_ position: NotificationPosition) -> String {
        switch position {
        case .topLeading: return L10n.string("settings.position_top_left")
        case .topCenter: return L10n.string("settings.position_top_center")
        case .topTrailing: return L10n.string("settings.position_top_right")
        case .centerLeading: return L10n.string("settings.position_center_left")
        case .center: return L10n.string("settings.position_center")
        case .centerTrailing: return L10n.string("settings.position_center_right")
        case .bottomLeading: return L10n.string("settings.position_bottom_left")
        case .bottomCenter: return L10n.string("settings.position_bottom_center")
        case .bottomTrailing: return L10n.string("settings.position_bottom_right")
        }
    }
}

private struct ShortcutsPage: View {
    @ObservedObject var store: RuleStore
    @ObservedObject private var hotKeys = GlobalHotKeyManager.shared

    var body: some View {
        Section {
            shortcutRow(
                title: "settings.enabled_shortcut",
                description: "settings.enabled_shortcut_description",
                selection: $store.enabledShortcutID
            )
            shortcutRow(
                title: "settings.global_lock_shortcut",
                description: "settings.global_lock_shortcut_description",
                selection: $store.globalLockShortcutID
            )
            if store.shortcutsConflict {
                Label(L10n.string("settings.shortcuts_conflict"), systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            if hotKeys.registrationFailed {
                Label(
                    L10n.string("settings.shortcuts_registration_failed"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
        }
    }

    private func shortcutRow(
        title: String,
        description: String,
        selection: Binding<String>
    ) -> some View {
        SettingRow(title: L10n.string(title), description: L10n.string(description)) {
            Picker("", selection: selection) {
                ForEach(GlobalShortcutOption.all) { option in
                    Text(option.displayName).tag(option.id)
                }
            }
            .labelsHidden()
            .frame(width: 160, alignment: .trailing)
        }
    }
}

private struct SyncPage: View {
    @ObservedObject var store: RuleStore
    @ObservedObject private var purchase = PurchaseManager.shared

    var body: some View {
        Group {
            Section {
                SettingRow(
                    title: L10n.string("settings.icloud_sync_content"),
                    description: cloudSyncDescription
                ) {
                    if purchase.isPro {
                        HStack(spacing: 8) {
                            Image(systemName: cloudSyncStatusIcon)
                                .foregroundStyle(cloudSyncStatusColor)
                                .help(cloudSyncDescription)
                            if store.cloudSyncStatus == .conflict {
                                Button { store.reviewCloudConflict() } label: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.orange)
                                .help(L10n.string("settings.icloud_review_conflict"))
                            }
                            Toggle("", isOn: $store.cloudSyncEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .disabled(!store.cloudSyncAvailable)
                        }
                    } else {
                        Button(action: { ProWindowController.shared.show() }) {
                            Label(L10n.string("pro.required_badge"), systemImage: "lock.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text(L10n.string("settings.icloud_sync"))
            }

            Section {
                HStack(alignment: .center, spacing: 24) {
                    Text(L10n.string("settings.import_export_description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 16)

                    VStack(alignment: .trailing, spacing: 8) {
                        Button(action: exportRules) {
                            Label(
                                L10n.string("settings.export_rules"),
                                systemImage: purchase.isPro ? "square.and.arrow.up" : "lock.fill"
                            )
                        }
                        Button(action: importRules) {
                            Label(
                                L10n.string("settings.import_rules"),
                                systemImage: purchase.isPro ? "square.and.arrow.down" : "lock.fill"
                            )
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text(L10n.string("settings.import_export_section"))
            }

            Section {
                HStack(alignment: .center, spacing: 24) {
                    Text(L10n.string("settings.rule_maintenance_description"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 16)

                    Button(action: cleanupInvalidRules) {
                        Label(
                            L10n.string("settings.cleanup_invalid"),
                            systemImage: purchase.isPro ? "wand.and.stars" : "lock.fill"
                        )
                    }
                }
                .frame(maxWidth: .infinity)
            } header: {
                Text(L10n.string("settings.rule_maintenance_section"))
            }
        }
    }

    private func cleanupInvalidRules() {
        guard purchase.isPro else {
            ProWindowController.shared.show()
            return
        }

        let count = store.detectInvalidRules().count
        guard count > 0 else {
            showAlert(L10n.string("settings.cleanup_none"))
            return
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = L10n.string("settings.cleanup_confirm_title")
        alert.informativeText = L10n.string("settings.cleanup_confirm_message", count)
        alert.addButton(withTitle: L10n.string("settings.cleanup_confirm"))
        alert.addButton(withTitle: L10n.string("settings.cancel"))
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let removedCount = store.removeInvalidRules()
        showAlert(L10n.string("settings.cleanup_success", removedCount))
    }

    private func exportRules() {
        guard purchase.isPro else {
            ProWindowController.shared.show()
            return
        }
        guard let data = store.exportRules() else { return }

        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "InputSwitcher-Rules.json"
        panel.prompt = L10n.string("settings.export_rules")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            try data.write(to: url)
            showAlert(L10n.string("settings.export_success"))
        } catch {
            showAlert(L10n.string("settings.import_failed"))
        }
    }

    private func importRules() {
        guard purchase.isPro else {
            ProWindowController.shared.show()
            return
        }

        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = L10n.string("settings.import_rules")

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
            guard values.isRegularFile == true,
                  let fileSize = values.fileSize,
                  fileSize <= RuleStore.maximumImportSize else {
                showAlert(L10n.string("settings.import_failed"))
                return
            }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)

            let alert = NSAlert()
            alert.messageText = L10n.string("settings.import_mode_title")
            alert.informativeText = L10n.string("settings.import_mode_message")
            alert.addButton(withTitle: L10n.string("settings.import_merge"))
            alert.addButton(withTitle: L10n.string("settings.import_replace"))
            alert.addButton(withTitle: L10n.string("settings.cancel"))

            let response = alert.runModal()
            if response == .alertFirstButtonReturn {
                showImportResult(store.importRules(from: data, merge: true))
            } else if response == .alertSecondButtonReturn {
                showImportResult(store.importRules(from: data, merge: false))
            }
        } catch {
            showAlert(L10n.string("settings.import_failed"))
        }
    }

    private func showImportResult(_ succeeded: Bool) {
        showAlert(
            succeeded
                ? L10n.string("settings.import_success", store.rules.count)
                : L10n.string("settings.import_failed")
        )
    }

    private func showAlert(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.runModal()
    }

    private var cloudSyncDescription: String {
        guard purchase.isPro else { return L10n.string("pro.required_description") }
        guard store.cloudSyncAvailable else { return L10n.string("settings.icloud_sync_unavailable") }
        switch store.cloudSyncStatus {
        case .disabled: return L10n.string("settings.icloud_sync_description")
        case .requiresPro: return L10n.string("pro.required_description")
        case .unavailable: return L10n.string("settings.icloud_sync_unavailable")
        case .syncing: return L10n.string("settings.icloud_sync_syncing")
        case .synced: return L10n.string("settings.icloud_sync_synced")
        case .conflict: return L10n.string("settings.icloud_sync_conflict")
        case .failed: return L10n.string("settings.icloud_sync_failed")
        }
    }

    private var cloudSyncStatusIcon: String {
        switch store.cloudSyncStatus {
        case .syncing: return "arrow.triangle.2.circlepath.icloud"
        case .synced: return "checkmark.icloud.fill"
        case .conflict, .failed, .unavailable, .requiresPro: return "exclamationmark.icloud.fill"
        case .disabled: return "icloud"
        }
    }

    private var cloudSyncStatusColor: Color {
        switch store.cloudSyncStatus {
        case .synced: return .green
        case .failed, .unavailable, .requiresPro, .conflict: return .orange
        case .disabled, .syncing: return .secondary
        }
    }
}

private struct AdvancedPage: View {
    @ObservedObject var store: RuleStore
    @ObservedObject private var purchase = PurchaseManager.shared

    var body: some View {
        Group {
            Section {
                SettingRow(
                    title: L10n.string("settings.debug_mode"),
                    description: L10n.string("settings.debug_mode_description")
                ) {
                    Toggle("", isOn: $store.debugMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            }

#if DEBUG
            Section {
                SettingRow(
                    title: L10n.string("settings.test_unlock"),
                    description: L10n.string("settings.test_unlock_description")
                ) {
                    Toggle("", isOn: $purchase.testUnlockEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                Label(
                    L10n.string("settings.test_unlock_warning"),
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)
            }
#endif
        }
    }
}

// MARK: - 通用设置兼容实现
private struct SettingRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control

    init(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 16)

            control
                .frame(width: 260, alignment: .trailing)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct LegacyGeneralTab: View {
    @ObservedObject var store: RuleStore
    @ObservedObject private var purchase = PurchaseManager.shared
    let sources: [InputSource]

    var body: some View {
        Form {
            Section {
                SettingRow(
                    title: L10n.string(purchase.isPro ? "pro.active_title" : "pro.settings_title"),
                    description: L10n.string(purchase.isPro ? "pro.active_subtitle" : "pro.settings_description")
                ) {
                    if purchase.isPro {
                        Label(L10n.string("pro.unlocked"), systemImage: "checkmark.seal.fill")
                            .foregroundStyle(.green)
                    } else {
                        Button(action: { ProWindowController.shared.show() }) {
                            Label(L10n.string("pro.upgrade_short"), systemImage: "sparkles")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            }

            Section {
                SettingRow(
                    title: L10n.string("settings.enabled"),
                    description: L10n.string("settings.enabled_description")
                ) {
                    Toggle("", isOn: $store.enabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.string("settings.launch_at_login"),
                    description: L10n.string("settings.launch_at_login_description")
                ) {
                    Toggle("", isOn: $store.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.string("settings.icloud_sync"),
                    description: cloudSyncDescription
                ) {
                    if purchase.isPro {
                        HStack(spacing: 8) {
                            if store.cloudSyncEnabled && store.cloudSyncAvailable {
                                Image(systemName: cloudSyncStatusIcon)
                                    .foregroundStyle(cloudSyncStatusColor)
                                    .help(cloudSyncDescription)
                            }

                            if store.cloudSyncStatus == .conflict {
                                Button {
                                    store.reviewCloudConflict()
                                } label: {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.orange)
                                .help(L10n.string("settings.icloud_review_conflict"))
                            }

                            Toggle("", isOn: $store.cloudSyncEnabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                                .disabled(!store.cloudSyncAvailable)
                        }
                    } else {
                        Button(action: { ProWindowController.shared.show() }) {
                            Label(L10n.string("pro.required_badge"), systemImage: "lock.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } header: {
                Text(L10n.string("settings.general_section"))
            }

            Section {
                SettingRow(
                    title: L10n.string("settings.smart_learning"),
                    description: purchase.isPro
                        ? L10n.string(
                            "settings.smart_learning_description",
                            RuleStore.learningMinimumObservations
                        )
                        : L10n.string("pro.required_description")
                ) {
                    if purchase.isPro {
                        Toggle("", isOn: $store.smartLearningEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    } else {
                        Button(action: { ProWindowController.shared.show() }) {
                            Label(L10n.string("pro.required_badge"), systemImage: "lock.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingRow(
                    title: L10n.string("settings.global_lock"),
                    description: purchase.isPro
                        ? L10n.string("settings.global_lock_description")
                        : L10n.string("pro.required_description")
                ) {
                    if purchase.isPro {
                        Toggle("", isOn: $store.globalLockEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    } else {
                        Button(action: { ProWindowController.shared.show() }) {
                            Label(L10n.string("pro.required_badge"), systemImage: "lock.fill")
                        }
                        .buttonStyle(.bordered)
                    }
                }

                SettingRow(
                    title: L10n.string("settings.default_input_source"),
                    description: L10n.string("settings.default_input_source_description")
                ) {
                    Picker("", selection: $store.defaultInputSource) {
                        Text(L10n.string("settings.keep_current")).tag("")
                        Divider()
                        ForEach(sources) { source in
                            Text(source.name).tag(source.id)
                        }
                        if !store.defaultInputSource.isEmpty,
                           !sources.contains(where: { $0.id == store.defaultInputSource }) {
                            Text(store.defaultInputSourceDisplayName).tag(store.defaultInputSource)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200, alignment: .trailing)
                }
            } header: {
                Text(L10n.string("settings.rules_section"))
            }

            Section {
                SettingRow(
                    title: L10n.string("settings.show_switch_notification"),
                    description: L10n.string("settings.show_switch_notification_description")
                ) {
                    Toggle("", isOn: $store.showSwitchNotification)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }

                SettingRow(
                    title: L10n.string("settings.notification_position"),
                    description: L10n.string("settings.notification_position_description")
                ) {
                    Picker("", selection: $store.notificationPosition) {
                        ForEach(NotificationPosition.allCases) { position in
                            Text(notificationPositionLabel(position)).tag(position)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 200, alignment: .trailing)
                }
                .disabled(!store.showSwitchNotification)

                SettingRow(
                    title: L10n.string("settings.notification_duration"),
                    description: L10n.string("settings.notification_duration_description")
                ) {
                    HStack(spacing: 8) {
                        Text(String(format: "%.1f s", store.notificationDuration))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                        Slider(value: roundedNotificationDuration, in: 0.1...4.0)
                            .frame(width: 180)
                    }
                }
                .disabled(!store.showSwitchNotification)
            } header: {
                Text(L10n.string("settings.notifications_section"))
            }

            Section {
                SettingRow(
                    title: L10n.string("settings.menu_rule_count"),
                    description: L10n.string("settings.menu_rule_count_description")
                ) {
                    Picker("", selection: $store.menuRuleCount) {
                        Text(L10n.string("settings.menu_rule_none")).tag(0)
                        Text(L10n.string("settings.menu_rule_5")).tag(5)
                        Text(L10n.string("settings.menu_rule_10")).tag(10)
                        Text(L10n.string("settings.menu_rule_15")).tag(15)
                    }
                    .labelsHidden()
                    .frame(width: 120, alignment: .trailing)
                }
            } header: {
                Text(L10n.string("settings.menu_bar_section"))
            }

            Section {
                SettingRow(
                    title: L10n.string("settings.enabled_shortcut"),
                    description: L10n.string("settings.enabled_shortcut_description")
                ) {
                    Picker("", selection: $store.enabledShortcutID) {
                        ForEach(GlobalShortcutOption.all) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160, alignment: .trailing)
                }

                SettingRow(
                    title: L10n.string("settings.global_lock_shortcut"),
                    description: L10n.string("settings.global_lock_shortcut_description")
                ) {
                    Picker("", selection: $store.globalLockShortcutID) {
                        ForEach(GlobalShortcutOption.all) { option in
                            Text(option.displayName).tag(option.id)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 160, alignment: .trailing)
                }

                if store.shortcutsConflict {
                    Label(L10n.string("settings.shortcuts_conflict"), systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(L10n.string("settings.shortcuts_section"))
            }

            Section {
                SettingRow(
                    title: L10n.string("settings.debug_mode"),
                    description: L10n.string("settings.debug_mode_description")
                ) {
                    Toggle("", isOn: $store.debugMode)
                        .toggleStyle(.switch)
                        .labelsHidden()
                }
            } header: {
                Text(L10n.string("settings.advanced_settings"))
            }
        }
        .formStyle(.grouped)
        .padding(.horizontal, 8)
    }

    private var roundedNotificationDuration: Binding<Double> {
        Binding(
            get: { store.notificationDuration },
            set: { store.notificationDuration = ($0 * 10).rounded() / 10 }
        )
    }

    private var cloudSyncDescription: String {
        guard purchase.isPro else {
            return L10n.string("pro.required_description")
        }
        guard store.cloudSyncAvailable else {
            return L10n.string("settings.icloud_sync_unavailable")
        }

        switch store.cloudSyncStatus {
        case .disabled:
            return L10n.string("settings.icloud_sync_description")
        case .requiresPro:
            return L10n.string("pro.required_description")
        case .unavailable:
            return L10n.string("settings.icloud_sync_unavailable")
        case .syncing:
            return L10n.string("settings.icloud_sync_syncing")
        case .synced:
            return L10n.string("settings.icloud_sync_synced")
        case .conflict:
            return L10n.string("settings.icloud_sync_conflict")
        case .failed:
            return L10n.string("settings.icloud_sync_failed")
        }
    }

    private var cloudSyncStatusIcon: String {
        switch store.cloudSyncStatus {
        case .syncing:
            return "arrow.triangle.2.circlepath.icloud"
        case .synced:
            return "checkmark.icloud.fill"
        case .conflict:
            return "exclamationmark.icloud.fill"
        case .failed, .unavailable, .requiresPro:
            return "exclamationmark.icloud.fill"
        case .disabled:
            return "icloud"
        }
    }

    private var cloudSyncStatusColor: Color {
        switch store.cloudSyncStatus {
        case .synced:
            return .green
        case .failed, .unavailable, .requiresPro:
            return .orange
        case .conflict:
            return .orange
        case .disabled, .syncing:
            return .secondary
        }
    }

    private func notificationPositionLabel(_ position: NotificationPosition) -> String {
        switch position {
        case .topLeading: return L10n.string("settings.position_top_left")
        case .topCenter: return L10n.string("settings.position_top_center")
        case .topTrailing: return L10n.string("settings.position_top_right")
        case .centerLeading: return L10n.string("settings.position_center_left")
        case .center: return L10n.string("settings.position_center")
        case .centerTrailing: return L10n.string("settings.position_center_right")
        case .bottomLeading: return L10n.string("settings.position_bottom_left")
        case .bottomCenter: return L10n.string("settings.position_bottom_center")
        case .bottomTrailing: return L10n.string("settings.position_bottom_right")
        }
    }
}

// MARK: - 规则行
private struct RuleRow: View {
    @Binding var rule: Rule
    let sources: [InputSource]
    let isSelected: Bool
    let isRuleLocked: Bool
    let isGloballyLocked: Bool
    let onToggleSelection: () -> Void
    let onToggleLock: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: RuleLayout.spacing) {
            Button(action: onToggleSelection) {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: RuleLayout.selectionWidth, height: RuleLayout.selectionWidth)
            }
            .buttonStyle(.plain)
            .help(L10n.string(isSelected ? "settings.deselect_rule" : "settings.select_rule"))

            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: RuleLayout.iconWidth, height: RuleLayout.iconWidth)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(rule.appName)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if rule.isAutoLearned {
                        Image(systemName: "sparkles")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.accentColor)
                            .help(L10n.string("settings.auto_learned_rule"))
                    }
                }
                HStack(spacing: 5) {
                    Text(rule.bundleID)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !appIsInstalled {
                        Label(L10n.string("settings.app_unavailable"), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if !inputSourceAvailable {
                        Label(L10n.string("settings.input_method_unavailable"), systemImage: "keyboard.badge.exclamationmark")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                    } else if rule.syncedInputSourceID != nil {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help(L10n.string("settings.icloud_local_mapping"))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Picker(L10n.string("settings.input_method"), selection: inputSourceSelection) {
                ForEach(sources) { source in
                    Text(source.name).tag(source.id)
                }
                // 规则里的输入法已被停用时,保留原值避免选择器空白
                if !sources.contains(where: { $0.id == rule.inputSourceID }) {
                    Text(rule.syncedInputSourceName ?? rule.inputSourceID).tag(rule.inputSourceID)
                }
            }
            .labelsHidden()
            .frame(width: RuleLayout.inputWidth, alignment: .leading)

            Button(action: onToggleLock) {
                Image(systemName: effectiveLocked ? "lock.fill" : "lock.open")
                    .foregroundStyle(effectiveLocked ? Color.accentColor : Color.secondary)
                    .frame(width: RuleLayout.actionWidth, height: RuleLayout.actionWidth)
            }
            .buttonStyle(.plain)
            .help(L10n.string(isGloballyLocked ? "settings.global_lock_active_help" : "settings.locked"))

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.secondary)
                    .frame(width: RuleLayout.actionWidth, height: RuleLayout.actionWidth)
            }
            .buttonStyle(.plain)
            .help(L10n.string("settings.delete_rule"))
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 6)
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackgroundColor)
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var rowBackgroundColor: Color {
        if isSelected {
            return Color.accentColor.opacity(0.1)
        }
        return isHovering ? Color.secondary.opacity(0.07) : Color.clear
    }

    private var effectiveLocked: Bool {
        isGloballyLocked || isRuleLocked
    }

    private var appIsInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) != nil
    }

    private var inputSourceAvailable: Bool {
        InputSourceManager.name(forID: rule.inputSourceID) != nil
    }

    private var inputSourceSelection: Binding<String> {
        Binding(
            get: { rule.inputSourceID },
            set: { newValue in
                rule.inputSourceID = newValue
                rule.syncedInputSourceID = nil
                rule.syncedInputSourceName = nil
                rule.isAutoLearned = false
            }
        )
    }

    private var appIcon: NSImage {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: rule.bundleID) {
            return NSWorkspace.shared.icon(forFile: url.path)
        }
        return NSWorkspace.shared.icon(for: .applicationBundle)
    }
}
