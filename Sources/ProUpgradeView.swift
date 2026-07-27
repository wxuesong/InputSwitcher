import AppKit
import SwiftUI

enum ProFeatureCatalog {
    static let items: [(icon: String, titleKey: String)] = [
        ("list.bullet.rectangle", "pro.feature_unlimited"),
        ("brain.head.profile", "pro.feature_smart_learning"),
        ("lock.shield", "pro.feature_locking"),
        ("arrow.up.arrow.down.square", "pro.feature_import_export"),
        ("wand.and.stars", "pro.feature_cleanup"),
        ("icloud", "pro.feature_icloud")
    ]
}

private enum ProUpgradeMetrics {
    static let contentHeight: CGFloat = 410

    static var featureColumnWidth: CGFloat {
        let font = NSFont.systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        let longestLabel = ProFeatureCatalog.items
            .map { L10n.string($0.titleKey) as NSString }
            .map { $0.size(withAttributes: [.font: font]).width }
            .max() ?? 0
        return min(max(longestLabel + 44, 210), 260)
    }

    static var contentWidth: CGFloat {
        min(max(featureColumnWidth * 2 + 70, 500), 590)
    }
}

@MainActor
final class ProWindowController {
    static let shared = ProWindowController()

    private var window: NSPanel?

    private init() {}

    func show() {
        DispatchQueue.main.async {
            if let window = self.window {
                window.center()
                NSApp.activate(ignoringOtherApps: true)
                window.orderFrontRegardless()
                window.makeKey()
                return
            }

            let panel = NSPanel(
                contentRect: NSRect(
                    x: 0,
                    y: 0,
                    width: ProUpgradeMetrics.contentWidth,
                    height: ProUpgradeMetrics.contentHeight
                ),
                styleMask: [.titled, .closable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.title = L10n.string("pro.window_title")
            panel.titleVisibility = .hidden
            panel.titlebarAppearsTransparent = true
            panel.isMovableByWindowBackground = true
            panel.isReleasedWhenClosed = false
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
            panel.hidesOnDeactivate = false
            panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
            panel.standardWindowButton(.zoomButton)?.isHidden = true
            panel.contentViewController = NSHostingController(
                rootView: ProUpgradeView { [weak panel] in panel?.close() }
            )
            panel.center()
            NSApp.activate(ignoringOtherApps: true)
            panel.orderFrontRegardless()
            panel.makeKey()
            self.window = panel
        }
    }
}

struct ProUpgradeView: View {
    @ObservedObject private var purchase = PurchaseManager.shared
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    VStack(spacing: 7) {
                        AdaptiveApplicationIcon(size: 56)

                        Text(L10n.string(purchase.isPro ? "pro.active_title" : "pro.title"))
                            .font(.title3.weight(.semibold))
                            .multilineTextAlignment(.center)
                        Text(
                            purchase.isPro
                                ? L10n.string("pro.active_subtitle")
                                : L10n.string("pro.subtitle", PurchaseManager.freeRuleLimit)
                        )
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: 440)
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 18, alignment: .leading),
                            GridItem(.flexible(), spacing: 18, alignment: .leading)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(ProFeatureCatalog.items, id: \.titleKey) { feature in
                            HStack(spacing: 10) {
                                Image(systemName: feature.icon)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Color.accentColor)
                                    .frame(width: 28, height: 28)
                                    .background(Color.accentColor.opacity(0.12))
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                Text(L10n.string(feature.titleKey))
                                    .font(.callout.weight(.medium))
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, minHeight: 38, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    }

                }
                .padding(.horizontal, 26)
                .padding(.top, 18)
                .padding(.bottom, 14)
            }

            if purchase.activity != .idle {
                purchaseMessage
                    .font(.caption)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 7)
            }

            Divider()

            HStack(spacing: 12) {
                if !purchase.isPro {
                    Button {
                        Task { await purchase.restorePurchases() }
                    } label: {
                        Label(L10n.string("pro.restore"), systemImage: "arrow.clockwise")
                    }
                    .disabled(isBusy)
                } else {
                    Label(L10n.string("pro.unlocked"), systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                        .font(.callout.weight(.medium))
                }

                Spacer()

                Button(L10n.string("pro.close"), action: onClose)
                    .keyboardShortcut(.cancelAction)

                if !purchase.isPro {
                    Button {
                        Task { await purchase.purchasePro() }
                    } label: {
                        Label(
                            purchaseButtonTitle,
                            systemImage: "cart.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isBusy || purchase.product == nil)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .frame(width: ProUpgradeMetrics.contentWidth, height: ProUpgradeMetrics.contentHeight)
        .task {
            await purchase.refresh()
        }
    }

    @ViewBuilder
    private var purchaseMessage: some View {
        switch purchase.activity {
        case .loading:
            Label(L10n.string("pro.loading"), systemImage: "clock")
                .foregroundStyle(.secondary)
        case .purchasing:
            ProgressView(L10n.string("pro.purchasing"))
                .controlSize(.small)
        case .restoring:
            ProgressView(L10n.string("pro.restoring"))
                .controlSize(.small)
        case .pending:
            Label(L10n.string("pro.pending"), systemImage: "hourglass")
                .foregroundStyle(.orange)
        case .failed:
            Label(L10n.string("pro.failed"), systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        case .idle:
            EmptyView()
        }
    }

    private var isBusy: Bool {
        purchase.activity == .loading ||
            purchase.activity == .purchasing ||
            purchase.activity == .restoring
    }

    private var purchaseButtonTitle: String {
        guard purchase.product != nil else { return L10n.string("pro.price_unavailable") }
        return L10n.string("pro.purchase", purchase.displayPrice)
    }
}
