import AppKit
import SwiftUI

@MainActor
final class OnboardingWindowController: NSObject, NSWindowDelegate {
    static let shared = OnboardingWindowController()

    private static let completedKey = "onboardingCompleted"
    private var window: NSPanel?

    private override init() {}

    func showIfNeeded(force: Bool = false) {
        DispatchQueue.main.async {
            guard force || UserDefaults.standard.object(forKey: Self.completedKey) == nil else { return }

            if !force && !RuleStore.shared.rules.isEmpty {
                UserDefaults.standard.set(true, forKey: Self.completedKey)
                return
            }

            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = L10n.string("onboarding.title")
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.delegate = self
            panel.contentViewController = NSHostingController(
                rootView: OnboardingView { [weak self, weak panel] in
                    self?.complete(panel: panel)
                }
            )
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
            self.window = panel
        }
    }

    private func complete(panel: NSPanel?) {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        panel?.close()
        window = nil
    }

    func windowWillClose(_ notification: Notification) {
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        window = nil
    }
}

private struct OnboardingView: View {
    @ObservedObject private var store = RuleStore.shared
    @ObservedObject private var inputSources = InputSourceCatalog.shared
    @ObservedObject private var purchase = PurchaseManager.shared
    private let onComplete: () -> Void

    init(onComplete: @escaping () -> Void) {
        self.onComplete = onComplete
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    VStack(spacing: 10) {
                        Image(systemName: "keyboard.badge.ellipsis")
                            .font(.system(size: 38, weight: .medium))
                            .foregroundStyle(Color.accentColor)
                        Text(L10n.string("onboarding.welcome"))
                            .font(.title2.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(L10n.string("onboarding.subtitle"))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        OnboardingSettingRow(
                            title: L10n.string("settings.default_input_source"),
                            description: L10n.string("onboarding.default_input_description")
                        ) {
                            Picker("", selection: $store.defaultInputSource) {
                                Text(L10n.string("settings.keep_current")).tag("")
                                ForEach(inputSources.sources) { source in
                                    Text(source.name).tag(source.id)
                                }
                            }
                            .labelsHidden()
                            .frame(width: 190, alignment: .trailing)
                        }

                        OnboardingSettingRow(
                            title: L10n.string("settings.enabled"),
                            description: L10n.string("settings.enabled_description")
                        ) {
                            Toggle("", isOn: $store.enabled)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }

                        OnboardingSettingRow(
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

                        OnboardingSettingRow(
                            title: L10n.string("settings.launch_at_login"),
                            description: L10n.string("settings.launch_at_login_description")
                        ) {
                            Toggle("", isOn: $store.launchAtLogin)
                                .toggleStyle(.switch)
                                .labelsHidden()
                        }
                    }
                    .padding(18)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Text(L10n.string("onboarding.privacy_note"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 34)
                .padding(.top, 28)
                .padding(.bottom, 18)
            }

            Divider()

            HStack {
                Button(L10n.string("onboarding.skip"), action: onComplete)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(L10n.string("onboarding.start"), action: onComplete)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)
        }
        .frame(width: 520, height: 470)
    }
}

private struct OnboardingSettingRow<Control: View>: View {
    let title: String
    let description: String
    let control: Control

    init(title: String, description: String, @ViewBuilder control: () -> Control) {
        self.title = title
        self.description = description
        self.control = control()
    }

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body)
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 10)
            control.frame(width: 190, alignment: .trailing)
        }
    }
}
