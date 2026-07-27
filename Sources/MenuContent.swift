import SwiftUI

struct MenuContent: View {
    @ObservedObject private var store = RuleStore.shared
    @ObservedObject private var tracker = FrontAppTracker.shared
    @ObservedObject private var purchase = PurchaseManager.shared
    @ObservedObject private var inputSources = InputSourceCatalog.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Toggle(L10n.string("menu.toggle_enabled"), isOn: $store.enabled)
            .displayingMenuShortcut(store.enabledShortcut)
        if purchase.isPro {
            Toggle(L10n.string("menu.global_lock"), isOn: $store.globalLockEnabled)
                .displayingMenuShortcut(store.globalLockShortcut)
        } else {
            Button {
                ProWindowController.shared.show()
            } label: {
                Label(L10n.string("menu.global_lock"), systemImage: "lock.fill")
            }
            .displayingMenuShortcut(store.globalLockShortcut)
        }

        Divider()

        if let app = tracker.frontApp {
            let currentRule = store.rule(for: app.bundleID)
            Menu(L10n.string("menu.set_input_for", app.name)) {
                ForEach(inputSources.sources) { source in
                    Button {
                        setRule(for: app, inputSourceID: source.id)
                    } label: {
                        if source.id == currentRule?.inputSourceID {
                            Label(source.name, systemImage: "checkmark")
                        } else {
                            Text(source.name)
                        }
                    }
                }
                if currentRule != nil {
                    Divider()
                    Button(L10n.string("menu.remove_rule")) {
                        store.removeRule(bundleID: app.bundleID)
                    }
                }
            }
        }

        if tracker.recentApps.count > 1 {
            Menu(L10n.string("menu.recent_apps")) {
                ForEach(Array(tracker.recentApps.prefix(5)), id: \.bundleID) { app in
                    let currentRule = store.rule(for: app.bundleID)
                    Menu(app.name) {
                        ForEach(inputSources.sources) { source in
                            Button {
                                setRule(for: app, inputSourceID: source.id)
                            } label: {
                                if source.id == currentRule?.inputSourceID {
                                    Label(source.name, systemImage: "checkmark")
                                } else {
                                    Text(source.name)
                                }
                            }
                        }
                        if currentRule != nil {
                            Divider()
                            Button(L10n.string("menu.remove_rule")) {
                                store.removeRule(bundleID: app.bundleID)
                            }
                        }
                    }
                }
            }
        }

        if !store.rules.isEmpty && store.menuRuleCount > 0 {
            Divider()
            Text(L10n.string("menu.rules_count", store.rules.count))
            ForEach(Array(store.rules.prefix(max(0, store.menuRuleCount)))) { rule in
                Text("\(rule.appName) → \(InputSourceManager.name(forID: rule.inputSourceID) ?? rule.inputSourceID)")
            }
        }

        Divider()

        if store.debugMode {
            Menu(L10n.string("menu.debug")) {
                if let app = tracker.frontApp {
                    Button(L10n.string("menu.current_app_info")) {
                        showAppInfo(app)
                    }
                }

                Button(L10n.string("menu.open_debug_log")) {
                    openDebugLog()
                }
            }
        }

        if !purchase.isPro {
            Button {
                ProWindowController.shared.show()
            } label: {
                Label(L10n.string("pro.menu_upgrade"), systemImage: "sparkles")
            }
        }

        Button(L10n.string("menu.settings")) {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",", modifiers: [.command])

        Divider()

        Button(L10n.string("menu.quit")) {
            NSApp.terminate(nil)
        }
    }

    private func setRule(for app: FrontApp, inputSourceID: String) {
        guard store.canAddRule(bundleID: app.bundleID) else {
            ProWindowController.shared.show()
            return
        }
        store.setRule(
            bundleID: app.bundleID,
            appName: app.name,
            inputSourceID: inputSourceID
        )
    }

    private func openDebugLog() {
        let logURL = DebugLog.url

        if !FileManager.default.fileExists(atPath: logURL.path) {
            // 创建空日志文件
            try? L10n.string("debug.log_header").write(to: logURL, atomically: true, encoding: .utf8)
        }

        NSWorkspace.shared.open(logURL)
    }

    private func showAppInfo(_ app: FrontApp) {
        let alert = NSAlert()
        alert.messageText = L10n.string("appinfo.title")
        alert.informativeText = """
        \(L10n.string("appinfo.name", app.name))
        \(L10n.string("appinfo.bundle_id", app.bundleID))

        \(L10n.string("appinfo.has_rule", store.rule(for: app.bundleID) != nil ? L10n.string("appinfo.yes") : L10n.string("appinfo.no")))
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: L10n.string("appinfo.copy_bundle_id"))
        alert.addButton(withTitle: L10n.string("appinfo.close"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.bundleID, forType: .string)
        }
    }
}

private extension View {
    @ViewBuilder
    func displayingMenuShortcut(_ shortcut: GlobalShortcutOption) -> some View {
        switch shortcut.id {
        case "control-option-command-e":
            keyboardShortcut("e", modifiers: [.control, .option, .command])
        case "control-option-command-space":
            keyboardShortcut(.space, modifiers: [.control, .option, .command])
        case "control-option-command-k":
            keyboardShortcut("k", modifiers: [.control, .option, .command])
        case "control-option-command-l":
            keyboardShortcut("l", modifiers: [.control, .option, .command])
        default:
            self
        }
    }
}
