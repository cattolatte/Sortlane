import SwiftUI
import SortlaneCore

struct RuleEditor: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: SortingRule
    @State private var extensions = ""
    @State private var minimum = ""
    @State private var maximum = ""
    @State private var minimumAge = ""
    @State private var maximumAge = ""
    @State private var pattern = ""
    @State private var excluded = ""
    @State private var validation: String?
    let save: (SortingRule) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "slider.horizontal.3").font(.system(size: 23)).foregroundStyle(Color.laneAccent).frame(width: 47, height: 47).background(Color.laneAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 5) {
                    Text("Shape your sorting rule").font(.system(size: 21, weight: .semibold)).tracking(-0.5)
                    Text("All conditions must match. Empty fields match anything.").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
            }.padding(24)
            Divider()
            Form {
                Section("Identity") {
                    TextField("Rule name", text: $rule.name)
                    Toggle("Enabled", isOn: $rule.isEnabled)
                }
                Section {
                    TextField("File extensions", text: $extensions, prompt: Text("pdf, txt, md"))
                    TextField("Name contains", text: $rule.nameContains, prompt: Text("invoice"))
                    TextField("Name pattern", text: $pattern, prompt: Text("invoice-*.pdf"))
                    TextField("Exclude names containing", text: $excluded, prompt: Text("draft"))
                } header: { Text("Match these files") } footer: { Text("Patterns match the whole filename: * matches any characters, ? matches one. Matching ignores case.").font(.caption) }
                Section {
                    HStack {
                        TextField("At least (MB)", text: $minimum, prompt: Text("0"))
                        TextField("At most (MB)", text: $maximum, prompt: Text("Any"))
                    }
                    HStack {
                        TextField("Older than (days)", text: $minimumAge, prompt: Text("0"))
                        TextField("Newer than (days)", text: $maximumAge, prompt: Text("Any"))
                    }
                } header: { Text("Size & age") } footer: { Text("Age uses the last modification time. Fractional values such as 0.5 days are supported.").font(.caption) }
                Section {
                    TextField("Folder", text: $rule.destination, prompt: Text("Documents/{year}/{month}"))
                    HStack(spacing: 8) {
                        Text("Quick start").font(.caption).foregroundStyle(.secondary)
                        Button("By year") { rule.destination = "Documents/{year}" }.controlSize(.mini)
                        Button("By month") { rule.destination = "Documents/{year}/{month}" }.controlSize(.mini)
                        Button("Receipts") { rule.destination = "Documents/Receipts" }.controlSize(.mini)
                    }
                } header: { Text("Give them a home") } footer: { Text("Inside your selected output folder. {year} and {month} use the file's modification date. System and protected folders remain excluded.").font(.caption) }
            }.formStyle(.grouped).textFieldStyle(.roundedBorder)
            Divider()
            HStack {
                if let validation { Label(validation, systemImage: "exclamationmark.circle").font(.system(size: 10)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save rule") { validateAndSave() }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }.padding(20)
        }.frame(width: 580, height: 700).tint(.laneAccent).onAppear {
            extensions = rule.extensions.joined(separator: ", ")
            minimum = rule.minimumBytes.map { String(Double($0) / 1_000_000) } ?? ""
            maximum = rule.maximumBytes.map { String(Double($0) / 1_000_000) } ?? ""
            minimumAge = rule.minimumAgeDays.map { String($0) } ?? ""
            maximumAge = rule.maximumAgeDays.map { String($0) } ?? ""
            pattern = rule.namePattern ?? ""; excluded = rule.excludedNameContains ?? ""
        }
    }
    private func validateAndSave() {
        do {
            rule.name = rule.name.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.destination = rule.destination.trimmingCharacters(in: .whitespacesAndNewlines)
            rule.extensions = extensions.split(separator: ",").map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).lowercased() }.filter { !$0.isEmpty }
            rule.minimumBytes = try size(minimum); rule.maximumBytes = try size(maximum)
            rule.minimumAgeDays = try number(minimumAge); rule.maximumAgeDays = try number(maximumAge)
            rule.namePattern = pattern.isEmpty ? nil : pattern; rule.excludedNameContains = excluded.isEmpty ? nil : excluded
            try rule.validate()
            save(rule); dismiss()
        } catch { validation = error.localizedDescription }
    }
    private func number(_ value: String) throws -> Double? {
        let value = value.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty else { return nil }
        guard let number = Double(value), number.isFinite, number >= 0 else { throw SortlaneError.unsafeFile("Enter a valid nonnegative number.") }
        return number
    }
    private func size(_ value: String) throws -> Int64? {
        guard let number = try number(value) else { return nil }
        guard number < Double(Int64.max) / 1_000_000 else { throw SortlaneError.unsafeFile("File size is too large.") }
        return Int64(number * 1_000_000)
    }
}
