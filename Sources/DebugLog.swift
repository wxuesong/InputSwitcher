import Foundation

enum DebugLog {
    private static let maximumSize = 1_048_576

    static var url: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("InputSwitcher_debug.log")
    }

    static func remove() {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func append(_ data: Data) {
        let currentSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
            .intValue ?? 0
        if currentSize + data.count > maximumSize {
            try? FileManager.default.removeItem(at: url)
        }

        if let fileHandle = try? FileHandle(forWritingTo: url) {
            fileHandle.seekToEndOfFile()
            fileHandle.write(data)
            fileHandle.closeFile()
        } else {
            try? data.write(to: url, options: .atomic)
        }
    }
}
