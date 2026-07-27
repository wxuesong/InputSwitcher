import AppKit
import QuartzCore

final class AutoRuleNotificationWindow: NSPanel {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let undoButton = NSButton(title: "", target: nil, action: nil)
    private var dismissWorkItem: DispatchWorkItem?
    private var undoAction: (() -> Void)?
    private var presentationID = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 330, height: 76),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        setupViews()
    }

    private func setupViews() {
        let container = NSView(frame: contentView!.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.88).cgColor
        container.layer?.cornerRadius = 12
        container.layer?.borderWidth = 0.5
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.2).cgColor
        container.autoresizingMask = [.width, .height]

        let icon = NSImageView(frame: NSRect(x: 14, y: 22, width: 30, height: 30))
        icon.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: nil)
        icon.contentTintColor = .systemBlue
        icon.imageScaling = .scaleProportionallyUpOrDown

        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.frame = NSRect(x: 54, y: 40, width: 174, height: 18)

        subtitleLabel.font = NSFont.systemFont(ofSize: 11)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(x: 54, y: 21, width: 174, height: 16)

        undoButton.bezelStyle = .rounded
        undoButton.isBordered = false
        undoButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        undoButton.contentTintColor = .systemBlue
        undoButton.target = self
        undoButton.action = #selector(undoPressed)
        undoButton.frame = NSRect(x: 238, y: 24, width: 78, height: 28)

        container.addSubview(icon)
        container.addSubview(titleLabel)
        container.addSubview(subtitleLabel)
        container.addSubview(undoButton)
        contentView = container
    }

    func show(appName: String, inputSourceName: String, undo: @escaping () -> Void) {
        dismissWorkItem?.cancel()
        presentationID += 1
        let currentPresentationID = presentationID
        undoAction = undo
        titleLabel.stringValue = L10n.string("learning.auto_created")
        subtitleLabel.stringValue = "\(appName) · \(inputSourceName)"
        undoButton.title = L10n.string("learning.undo")
        position(on: NSScreen.main ?? NSScreen.screens.first)
        alphaValue = 0
        orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut(presentationID: currentPresentationID)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + max(2.5, RuleStore.shared.notificationDuration), execute: workItem)
    }

    @objc private func undoPressed() {
        undoAction?()
        undoAction = nil
        fadeOut(presentationID: presentationID)
    }

    private func position(on screen: NSScreen?) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let inset: CGFloat = 24
        let x: CGFloat
        let y: CGFloat
        switch RuleStore.shared.notificationPosition {
        case .topLeading, .centerLeading, .bottomLeading:
            x = visible.minX + inset
        case .topCenter, .center, .bottomCenter:
            x = visible.midX - frame.width / 2
        case .topTrailing, .centerTrailing, .bottomTrailing:
            x = visible.maxX - frame.width - inset
        }
        switch RuleStore.shared.notificationPosition {
        case .topLeading, .topCenter, .topTrailing:
            y = visible.maxY - frame.height - inset
        case .centerLeading, .center, .centerTrailing:
            y = visible.midY - frame.height / 2
        case .bottomLeading, .bottomCenter, .bottomTrailing:
            y = visible.minY + inset
        }
        setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func fadeOut(presentationID: Int) {
        guard presentationID == self.presentationID else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationID == presentationID else { return }
                self.orderOut(nil)
            }
        }
    }
}
