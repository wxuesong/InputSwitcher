import SwiftUI

@MainActor
enum AdaptiveIconAssets {
    static let menuBarTemplateImage = menuBarTemplateImage(in: .main)

    static func menuBarTemplateImage(in bundle: Bundle) -> NSImage? {
        guard let source = bundle.image(forResource: "MenuBarIcon_dark"),
              let image = source.copy() as? NSImage else { return nil }
        image.isTemplate = true
        image.size = NSSize(width: 22, height: 22)
        return image
    }

    static func applicationIcon(isDark _: Bool, in bundle: Bundle = .main) -> NSImage {
        return bundle.image(forResource: "InputSwitcher")
            ?? NSApp.applicationIconImage
    }

    static func applicationIcon(for appearance: NSAppearance) -> NSImage {
        let match = appearance.bestMatch(from: [.darkAqua, .aqua])
        return applicationIcon(isDark: match == .darkAqua)
    }
}

struct AdaptiveApplicationIcon: View {
    @Environment(\.colorScheme) private var colorScheme
    let size: CGFloat

    var body: some View {
        Image(nsImage: AdaptiveIconAssets.applicationIcon(isDark: colorScheme == .dark))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
    }
}

@main
struct InputSwitcherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Group {
                if let icon = AdaptiveIconAssets.menuBarTemplateImage {
                    Image(nsImage: icon)
                        .renderingMode(.template)
                } else {
                    Image(systemName: "keyboard")
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .inputSwitcherOpenSettingsRequested)) { _ in
                openSettingsWindow()
            }
        }

        Window(L10n.string("settings.title"), id: "settings") {
            SettingsView()
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(L10n.string("menu.settings")) {
                    openWindow(id: "settings")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }
    }

    private func openSettingsWindow() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }
}
