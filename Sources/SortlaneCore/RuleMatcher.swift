import Foundation

public extension SortingRule {
    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 120 else { throw SortlaneError.unsafeFile("Enter a rule name of 1–120 characters.") }
        try PathSafety.validateRelativeFolder(destination)
        let unresolved = destination.replacingOccurrences(of: "{year}", with: "2026").replacingOccurrences(of: "{month}", with: "11")
        guard !unresolved.contains("{"), !unresolved.contains("}") else { throw SortlaneError.unsafeFile("Folder templates support {year} and {month} only.") }
        guard (namePattern?.count ?? 0) <= 256 else { throw SortlaneError.unsafeFile("Keep filename patterns under 256 characters.") }
        for age in [minimumAgeDays, maximumAgeDays].compactMap({ $0 }) {
            guard age.isFinite, age >= 0, age <= 365_000 else { throw SortlaneError.unsafeFile("File ages must be between 0 and 365,000 days.") }
        }
        if let low = minimumAgeDays, let high = maximumAgeDays, low > high { throw SortlaneError.unsafeFile("Minimum age cannot exceed maximum age.") }
        for size in [minimumBytes, maximumBytes].compactMap({ $0 }) where size < 0 { throw SortlaneError.unsafeFile("File sizes cannot be negative.") }
        if let low = minimumBytes, let high = maximumBytes, low > high { throw SortlaneError.unsafeFile("Minimum size cannot exceed maximum size.") }
        guard extensions.count <= 100, extensions.allSatisfy({ !$0.isEmpty && $0.count <= 32 && !$0.contains("/") && !$0.contains("\\") }) else { throw SortlaneError.unsafeFile("Enter a comma-separated list of extensions such as pdf, jpg, txt.") }
    }
    func destinationFolder(for file: FileSnapshot) -> String {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: file.modified)
        return destination.replacingOccurrences(of: "{year}", with: String(format: "%04d", parts.year ?? 2000))
            .replacingOccurrences(of: "{month}", with: String(format: "%02d", parts.month ?? 1))
    }
}

struct RuleMatcher {
    let rule: SortingRule
    let extensions: Set<String>
    init(_ rule: SortingRule) {
        self.rule = rule
        extensions = Set(rule.extensions.map { $0.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ". ")) })
    }
    func matches(_ file: FileSnapshot, now: Date) -> Bool {
        let name = file.url.lastPathComponent
        let age = max(0, now.timeIntervalSince(file.modified) / 86_400)
        guard rule.isEnabled, extensions.isEmpty || extensions.contains(file.url.pathExtension.lowercased()),
              rule.nameContains.isEmpty || name.localizedCaseInsensitiveContains(rule.nameContains),
              rule.minimumBytes.map({ file.size >= $0 }) ?? true, rule.maximumBytes.map({ file.size <= $0 }) ?? true,
              rule.minimumAgeDays.map({ age >= $0 }) ?? true, rule.maximumAgeDays.map({ age <= $0 }) ?? true else { return false }
        if let excluded = rule.excludedNameContains, !excluded.isEmpty, name.localizedCaseInsensitiveContains(excluded) { return false }
        if let pattern = rule.namePattern, !pattern.isEmpty { return Self.glob(name, pattern: pattern) }
        return true
    }
    // Bounded wildcard matching without a regex engine or catastrophic backtracking.
    static func glob(_ value: String, pattern: String) -> Bool {
        let text = Array(value.lowercased()), pattern = Array(pattern.lowercased())
        var row = [Bool](repeating: false, count: text.count + 1); row[0] = true
        for character in pattern {
            var next = [Bool](repeating: false, count: text.count + 1)
            if character == "*" { next[0] = row[0] }
            for index in text.indices {
                next[index + 1] = character == "*" ? row[index + 1] || next[index] : row[index] && (character == "?" || character == text[index])
            }
            row = next
        }
        return row[text.count]
    }
}
