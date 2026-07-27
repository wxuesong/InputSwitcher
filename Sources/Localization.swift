import Foundation

enum L10n {
    private static let strings = loadStrings()

    static func string(_ key: String, _ args: CVarArg...) -> String {
        let format = strings[key] ?? key
        if args.isEmpty {
            return format
        }
        return String(format: format, arguments: args)
    }

    private static func loadStrings() -> [String: String] {
        let language = detectLanguage()
        let english = loadStringsFile(language: "en")
        guard language != "en" else { return english }
        return english.merging(loadStringsFile(language: language)) { _, localized in localized }
    }

    private static func loadStringsFile(language: String) -> [String: String] {
        // 尝试多种路径方式查找本地化文件
        var url: URL?

        // 方式1: 构建产物中的标准资源子目录
        url = Bundle.main.url(forResource: language, withExtension: "strings", subdirectory: "Localizations")

        // 方式2: 直接路径（这个方式成功了）
        if url == nil {
            url = Bundle.main.url(forResource: "Localizations/\(language)", withExtension: "strings")
        }

        // 方式3: 完整路径
        if url == nil {
            if let resourcePath = Bundle.main.resourcePath {
                let fullPath = resourcePath + "/Localizations/\(language).strings"
                if FileManager.default.fileExists(atPath: fullPath) {
                    url = URL(fileURLWithPath: fullPath)
                }
            }
        }

        guard let finalUrl = url,
              let data = try? Data(contentsOf: finalUrl),
              let content = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // 跳过注释和空行
            if trimmed.isEmpty || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("//") {
                continue
            }

            // 解析 "key" = "value";
            guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }

            let keyPart = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
            let valuePart = String(trimmed[trimmed.index(after: equalIndex)...])
                .trimmingCharacters(in: .whitespaces)

            // 移除末尾的分号
            let valueClean = valuePart.hasSuffix(";")
                ? String(valuePart.dropLast()).trimmingCharacters(in: .whitespaces)
                : valuePart

            if let key = extractQuoted(keyPart),
               let value = extractQuoted(valueClean) {
                result[key] = value
            }
        }

        return result
    }

    private static func extractQuoted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return nil
        }
        let start = trimmed.index(after: trimmed.startIndex)
        let end = trimmed.index(before: trimmed.endIndex)
        return unescape(String(trimmed[start..<end]))
    }

    private static func unescape(_ text: String) -> String {
        var result = ""
        var isEscaped = false

        for character in text {
            if isEscaped {
                switch character {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                default:
                    result.append("\\")
                    result.append(character)
                }
                isEscaped = false
            } else if character == "\\" {
                isEscaped = true
            } else {
                result.append(character)
            }
        }

        if isEscaped {
            result.append("\\")
        }

        return result
    }

    private static func detectLanguage() -> String {
        guard let preferred = Locale.preferredLanguages.first?.lowercased() else {
            return "en"
        }

        // 简体中文
        if preferred.contains("zh-hans") || preferred.contains("zh-cn") {
            return "zh-Hans"
        }
        // 繁体中文
        else if preferred.contains("zh-hant") || preferred.contains("zh-tw") || preferred.contains("zh-hk") {
            return "zh-Hant"
        }

        let supportedLanguages = ["ja", "ko", "de", "fr", "es"]
        if let language = supportedLanguages.first(where: { preferred.hasPrefix($0) }) {
            return language
        }
        if preferred.hasPrefix("pt") {
            return "pt-BR"
        }

        // 默认英文
        return "en"
    }
}
