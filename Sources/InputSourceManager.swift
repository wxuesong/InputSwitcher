import Carbon
import Combine
import Foundation

struct InputSource: Identifiable, Hashable {
    let id: String
    let name: String
}

private final class InputSourceCache: @unchecked Sendable {
    let lock = NSLock()
    var sources: [InputSource]?
}

enum InputSourceManager {
    private static let cache = InputSourceCache()

    /// 当前已启用、可选择的键盘输入法列表(含拼音等输入法模式)
    static func selectableSources(forceRefresh: Bool = false) -> [InputSource] {
        cache.lock.lock()
        if !forceRefresh, let sources = cache.sources {
            cache.lock.unlock()
            return sources
        }
        cache.lock.unlock()

        guard let cfList = TISCreateInputSourceList(nil, false)?.takeRetainedValue() else { return [] }
        let list = cfList as NSArray
        var result: [InputSource] = []
        for item in list {
            guard CFGetTypeID(item as CFTypeRef) == TISInputSourceGetTypeID() else { continue }
            let source = item as! TISInputSource
            guard boolProperty(source, kTISPropertyInputSourceIsSelectCapable),
                  stringProperty(source, kTISPropertyInputSourceCategory) == (kTISCategoryKeyboardInputSource as String),
                  let id = stringProperty(source, kTISPropertyInputSourceID),
                  let name = stringProperty(source, kTISPropertyLocalizedName)
            else { continue }
            result.append(InputSource(id: id, name: name))
        }
        cache.lock.lock()
        cache.sources = result
        cache.lock.unlock()
        return result
    }

    static func currentID() -> String? {
        guard let source = TISCopyCurrentKeyboardInputSource()?.takeRetainedValue() else { return nil }
        return stringProperty(source, kTISPropertyInputSourceID)
    }

    static func name(forID id: String) -> String? {
        selectableSources().first { $0.id == id }?.name
    }

    @discardableResult
    static func select(id: String) -> Bool {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue(),
              (cfList as NSArray).count > 0
        else { return false }
        let item = (cfList as NSArray)[0]
        guard CFGetTypeID(item as CFTypeRef) == TISInputSourceGetTypeID() else { return false }
        let source = item as! TISInputSource
        return TISSelectInputSource(source) == noErr
    }

    // MARK: - TIS property helpers

    private static func stringProperty(_ source: TISInputSource, _ key: CFString) -> String? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        return Unmanaged<CFString>.fromOpaque(ptr).takeUnretainedValue() as String
    }

    private static func boolProperty(_ source: TISInputSource, _ key: CFString) -> Bool {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return false }
        return CFBooleanGetValue(Unmanaged<CFBoolean>.fromOpaque(ptr).takeUnretainedValue())
    }
}

@MainActor
final class InputSourceCatalog: NSObject, ObservableObject {
    static let shared = InputSourceCatalog()

    @Published private(set) var sources: [InputSource]

    private override init() {
        sources = InputSourceManager.selectableSources()
        super.init()
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(enabledSourcesDidChange),
            name: Notification.Name(kTISNotifyEnabledKeyboardInputSourcesChanged as String),
            object: nil
        )
    }

    deinit {
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func enabledSourcesDidChange(_ notification: Notification) {
        sources = InputSourceManager.selectableSources(forceRefresh: true)
    }
}
