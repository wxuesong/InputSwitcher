import Foundation

let testString = """
/* Menu Bar */
"menu.toggle_enabled" = "Enable Auto-Switch";
"menu.set_input_for" = "Set Input Method for \\"%@\\"";
"""

var result: [String: String] = [:]
let lines = testString.components(separatedBy: .newlines)

for line in lines {
    let trimmed = line.trimmingCharacters(in: .whitespaces)

    if trimmed.isEmpty || trimmed.hasPrefix("/*") || trimmed.hasPrefix("*") || trimmed.hasPrefix("//") {
        continue
    }

    guard let equalIndex = trimmed.firstIndex(of: "=") else { continue }

    let keyPart = String(trimmed[..<equalIndex]).trimmingCharacters(in: .whitespaces)
    let valuePart = String(trimmed[trimmed.index(after: equalIndex)...])
        .trimmingCharacters(in: .whitespaces)

    let valueClean = valuePart.hasSuffix(";")
        ? String(valuePart.dropLast()).trimmingCharacters(in: .whitespaces)
        : valuePart

    func extractQuoted(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("\""), trimmed.hasSuffix("\""), trimmed.count >= 2 else {
            return nil
        }
        let start = trimmed.index(after: trimmed.startIndex)
        let end = trimmed.index(before: trimmed.endIndex)
        return String(trimmed[start..<end])
    }

    if let key = extractQuoted(keyPart),
       let value = extractQuoted(valueClean) {
        result[key] = value
        print("\(key) = \(value)")
    }
}

print("\n总共解析: \(result.count) 条")
