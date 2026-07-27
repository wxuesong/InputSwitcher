import AppKit
import QuartzCore

final class SwitchNotificationWindow: NSWindow {
    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let iconContainer = NSView()
    private var dismissWorkItem: DispatchWorkItem?
    private var presentationID = 0

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 72),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        level = .floating
        ignoresMouseEvents = true
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .stationary]
        setupViews()
    }

    private func setupViews() {
        let containerView = NSView(frame: contentView!.bounds)
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.84).cgColor
        containerView.layer?.cornerRadius = 14
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 0.5
        containerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.22).cgColor
        containerView.autoresizingMask = [.width, .height]

        iconContainer.wantsLayer = true
        iconContainer.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.14).cgColor
        iconContainer.layer?.cornerRadius = 11
        iconContainer.layer?.masksToBounds = true
        iconContainer.frame = NSRect(x: 12, y: 12, width: 48, height: 48)

        iconView.imageScaling = .scaleProportionallyUpOrDown
        iconView.imageAlignment = .alignCenter
        iconView.contentTintColor = .white
        iconView.frame = iconContainer.bounds.insetBy(dx: 8, dy: 8)
        iconView.autoresizingMask = [.width, .height]
        iconContainer.addSubview(iconView)

        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = .white
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 74, y: 37, width: 152, height: 20)

        subtitleLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.68)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.frame = NSRect(x: 74, y: 19, width: 152, height: 16)

        containerView.addSubview(iconContainer)
        containerView.addSubview(titleLabel)
        containerView.addSubview(subtitleLabel)
        contentView = containerView
    }

    func show(inputSourceName: String, appName: String) {
        guard RuleStore.shared.showSwitchNotification else { return }

        dismissWorkItem?.cancel()
        presentationID += 1
        let currentPresentationID = presentationID
        iconView.image = getInputSourceIcon(name: inputSourceName)
        titleLabel.stringValue = inputSourceName
        subtitleLabel.stringValue = appName
        position(on: NSScreen.main ?? NSScreen.screens.first)

        alphaValue = 0
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }

        let workItem = DispatchWorkItem { [weak self] in
            self?.fadeOut(presentationID: currentPresentationID)
        }
        dismissWorkItem = workItem
        DispatchQueue.main.asyncAfter(
            deadline: .now() + RuleStore.shared.notificationDuration,
            execute: workItem
        )
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
            context.duration = 0.24
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.presentationID == presentationID else { return }
                self.orderOut(nil)
            }
        }
    }

    private func getInputSourceIcon(name: String) -> NSImage {
        let lowercased = name.lowercased()
        let symbol: String
        if name.contains("ABC") || lowercased.contains("english") {
            symbol = "character.textbox"
        } else if name.contains("拼音") || name.contains("Pinyin") {
            symbol = "character.cursor.ibeam"
        } else if name.contains("五笔") || name.contains("Wubi") {
            symbol = "textformat.abc"
        } else if name.contains("注音") || name.contains("Zhuyin") {
            symbol = "character.book.closed"
        } else {
            symbol = "keyboard"
        }

        let config = NSImage.SymbolConfiguration(pointSize: 24, weight: .medium)
        return NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
            ?? NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)!
    }
}
