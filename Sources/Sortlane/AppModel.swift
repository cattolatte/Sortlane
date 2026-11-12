import AppKit
import SwiftUI
import SortlaneCore
import UniformTypeIdentifiers

enum QueueFilter: String, CaseIterable, Identifiable {
    case all = "All files", ready = "Ready", needsReview = "Review", conflicts = "Conflicts", ai = "AI suggestions"
    var id: String { rawValue }
}
enum QueueSort: String, CaseIterable, Identifiable {
    case name = "Name", size = "Largest first", newest = "Newest first"
    var id: String { rawValue }
}

struct SavedFolder: Codable {
    var bookmark: Data
    var displayPath: String
    init(_ url: URL) throws {
        bookmark = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        displayPath = url.path
    }
    func resolve() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        return url
    }
}

struct Configuration: Codable {
    var source: SavedFolder?
    var destination: SavedFolder?
    var rules = SortingRule.defaults
    var recursive = false
}

enum Screen: String, CaseIterable, Identifiable {
    case inbox = "Overview", rules = "Sorting rules", history = "Activity"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .inbox: "square.grid.2x2"; case .rules: "slider.horizontal.3"; case .history: "clock.arrow.circlepath" }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var screen: Screen = .inbox
    @Published var config = Configuration()
    @Published var source: URL?
    @Published var destination: URL?
    @Published var proposals: [FileProposal] = []
    @Published var history: [MoveOperation] = []
    @Published var busy = false
    @Published var status = "Choose a folder to get started."
    @Published var error: String?
    @Published var monitoring = false
    @Published var automaticRules = false
    @Published var skipped = 0
    @Published var lastScan: Date?
    @Published var aiReady = false
    @Published var aiStatus = "Checking Apple Intelligence…"
    @Published var search = ""
    @Published var isDemo = false
    @Published var initialized = false
    @Published var queueFilter: QueueFilter = .all
    @Published var queueSort: QueueSort = .name
    @Published var inspectedID: UUID?
    @Published var progress: Double?
    @Published var workCancellable = false
    @Published var historySearch = ""
    private var activeTask: Task<Void, Never>?
    private var starting = false
    let dataDirectory: URL
    private var organizer: Organizer?
    private let classifier = AppleClassifier()
    private let watcher = FolderWatcher()
    private var saveTask: Task<Void, Never>?
    var folderPolicy: FolderPolicy { FolderPolicy(roots: [FolderPolicy.userHome, dataDirectory.appendingPathComponent("Sample files")]) }

    init(dataDirectory: URL) { self.dataDirectory = dataDirectory }
    var selectedCount: Int { proposals.filter { $0.isSelected && $0.issue == nil }.count }
    var reviewCount: Int { proposals.filter { $0.origin != .rule || $0.issue != nil }.count }
    var selectedBytes: Int64 { proposals.filter(\.isSelected).reduce(0) { $0 + $1.snapshot.size } }
    var canScan: Bool { source != nil && destination != nil && !busy && initialized }
    var inspectedProposal: FileProposal? { proposals.first { $0.id == inspectedID } }
    var visibleProposals: [FileProposal] {
        let filtered = proposals.filter { proposal in
            let match = search.isEmpty || [proposal.snapshot.url.lastPathComponent, proposal.relativeDestination ?? "", proposal.reason].contains { $0.localizedCaseInsensitiveContains(search) }
            guard match else { return false }
            switch queueFilter {
            case .all: return true
            case .ready: return proposal.relativeDestination != nil && proposal.issue == nil
            case .needsReview: return proposal.origin != .rule || proposal.issue != nil
            case .conflicts: return proposal.issue != nil
            case .ai: return proposal.origin == .appleAI
            }
        }
        return filtered.sorted {
            switch queueSort {
            case .name: break
            case .size: if $0.snapshot.size != $1.snapshot.size { return $0.snapshot.size > $1.snapshot.size }
            case .newest: if $0.snapshot.modified != $1.snapshot.modified { return $0.snapshot.modified > $1.snapshot.modified }
            }
            return $0.snapshot.url.path.localizedStandardCompare($1.snapshot.url.path) == .orderedAscending
        }
    }
    func inspect(_ id: UUID) { inspectedID = inspectedID == id ? nil : id }
    func setSelected(_ id: UUID, _ selected: Bool) {
        guard !busy, let i = proposals.firstIndex(where: { $0.id == id }), proposals[i].issue == nil, proposals[i].relativeDestination != nil else { return }
        proposals[i].isSelected = selected
    }
    func selectVisible(_ selected: Bool) {
        guard !busy else { return }
        let ids = Set(visibleProposals.map(\.id))
        for i in proposals.indices where ids.contains(proposals[i].id) && proposals[i].issue == nil && proposals[i].relativeDestination != nil { proposals[i].isSelected = selected }
    }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func cancelWork() { activeTask?.cancel(); workCancellable = false; status = "Stopping after the current safe step…" }
    private func performWork(cancellable: Bool = true, _ action: @escaping @MainActor () async -> Void) async {
        guard !busy else { return }
        busy = true; workCancellable = cancellable; progress = nil
        let task = Task { await action() }
        activeTask = task
        await task.value
        activeTask = nil; busy = false; workCancellable = false; progress = nil
    }
    func assignDestination(id: UUID, folder: String) async {
        guard !busy, let destination, let organizer, let i = proposals.firstIndex(where: { $0.id == id }) else { return }
        do {
            let target = try PathSafety.destination(root: destination, folder: folder, filename: proposals[i].snapshot.url.lastPathComponent)
            try folderPolicy.validateFolder(target.deletingLastPathComponent())
            var next = proposals
            next[i].relativeDestination = folder; next[i].origin = .manual
            next[i].reason = "Destination chosen by you"; next[i].issue = nil; next[i].isSelected = false
            await performWork(cancellable: false) { self.proposals = await organizer.validatePlan(next, destination: destination) }
            status = "Destination updated. Select the file when you're ready to move it."
        } catch { self.error = error.localizedDescription }
    }
    func exportRules() {
        guard !busy else { return }
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Sortlane rules.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(config.rules).write(to: url, options: .atomic)
            status = "Rules exported."
        } catch { self.error = error.localizedDescription }
    }
    func importRules() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource(); defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
            let data = try handle.read(upToCount: 1_000_001) ?? Data()
            guard data.count <= 1_000_000 else { throw SortlaneError.unsafeFile("Rule files must be smaller than 1 MB.") }
            var rules = try JSONDecoder().decode([SortingRule].self, from: data)
            guard !rules.isEmpty, config.rules.count + rules.count <= 100 else { throw SortlaneError.unsafeFile("Keep your library to 100 rules or fewer.") }
            for i in rules.indices { try rules[i].validate(); rules[i].id = UUID(); rules[i].isEnabled = false }
            config.rules += rules; rulesChanged()
            status = "Imported \(rules.count) rules, disabled for review. Enable them in Sorting rules."
        } catch { self.error = error.localizedDescription }
    }

    func start(demo: Bool) async {
        guard !starting, !initialized else { return }
        starting = true; defer { starting = false }
        do {
            let organizer = try Organizer(databaseURL: dataDirectory.appendingPathComponent("sortlane.sqlite"), policy: folderPolicy)
            self.organizer = organizer
            if let data = try await organizer.loadSettings() {
                do { config = try JSONDecoder().decode(Configuration.self, from: data) }
                catch { self.error = "Saved settings could not be read. Select your folders again." }
                do {
                    if let folder = config.source { source = try folder.resolve(); _ = source?.startAccessingSecurityScopedResource() }
                    if let folder = config.destination { destination = try folder.resolve(); _ = destination?.startAccessingSecurityScopedResource() }
                } catch { self.error = "A saved folder is unavailable. Select it again. \(error.localizedDescription)" }
            }
            let recovered = try await organizer.recoverInterruptedOperations()
            history = try await organizer.history()
            initialized = true
            let sampleRoot = dataDirectory.appendingPathComponent("Sample files")
            isDemo = source.map { PathSafety.isInside($0, root: sampleRoot) } == true && destination.map { PathSafety.isInside($0, root: sampleRoot) } == true
            refreshAI()
            if demo { try await createDemo() }
            else {
                if isDemo { try addOCRSample() }
                status = recovered > 0 ? "Recovered \(recovered) interrupted operations. Check Activity." : "Ready when you are. Your files stay in place until you organize them."
            }
        } catch { self.error = error.localizedDescription; status = "Setup needs attention." }
    }

    func refreshAI() {
        let state = AppleClassifier.availabilityDescription()
        aiReady = state.available; aiStatus = state.description
    }

    func chooseFolder(isSource: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false; panel.canCreateDirectories = !isSource
        panel.title = isSource ? "Choose a folder to organize" : "Choose where organized files belong"
        panel.message = isSource ? "Start with Downloads or a dedicated inbox. Files are previewed before moving." : "Category folders such as Documents and Images will be created here."
        guard panel.runModal() == .OK, let chosen = panel.url else { return }
        let url = chosen.resolvingSymlinksInPath()
        do {
            if isSource { try folderPolicy.validateSource(url) } else { try folderPolicy.validateFolder(url) }
            let saved = try SavedFolder(url)
            _ = url.startAccessingSecurityScopedResource()
            if isSource { source?.stopAccessingSecurityScopedResource(); source = url; config.source = saved }
            else { destination?.stopAccessingSecurityScopedResource(); destination = url; config.destination = saved }
            proposals = []; lastScan = nil; isDemo = false; automaticRules = false
            persist(); updateMonitoring()
            status = "Folders updated. Scan to preview the sorting plan."
        } catch { self.error = error.localizedDescription }
    }

    func persist() {
        guard let organizer else { return }
        // Serialize configuration writes so older edits cannot overwrite newer ones.
        let previous = saveTask
        do {
            let data = try JSONEncoder().encode(config)
            saveTask = Task {
                await previous?.value
                do { try await organizer.saveSettings(data) } catch { self.error = error.localizedDescription }
            }
        } catch { self.error = error.localizedDescription }
    }

    func rulesChanged() { proposals = []; lastScan = nil; automaticRules = false; persist() }

    func scan(background: Bool = false) async {
        guard canScan, let organizer, let source, let destination else { return }
        let rules = config.rules, recursive = config.recursive, previous = proposals
        await performWork {
            if !background { self.status = "Checking files and matching your rules…" }
            do {
                let result = try await organizer.scan(source: source, destination: destination, rules: rules, recursive: recursive, previous: previous)
                try Task.checkCancellation()
                self.proposals = result.proposals; self.skipped = result.skipped; self.lastScan = Date()
                if let id = self.inspectedID, !self.proposals.contains(where: { $0.id == id }) { self.inspectedID = nil }
                self.status = "\(self.proposals.count) files scanned · \(result.skipped) skipped"
                if !result.warnings.isEmpty && !background { self.error = result.warnings.prefix(5).joined(separator: "\n") }
                if background && self.automaticRules {
                    let eligible = self.proposals.filter { $0.origin == .rule && $0.issue == nil && $0.isSelected }
                    if !eligible.isEmpty {
                        let applied = await organizer.apply(eligible, sourceRoot: source, destinationRoot: destination)
                        self.history = try await organizer.history()
                        self.proposals.removeAll { !FileManager.default.fileExists(atPath: $0.snapshot.url.path) }
                        self.status = "Automatically organized \(applied.moved) files."
                        if !applied.errors.isEmpty { self.error = applied.errors.prefix(5).joined(separator: "\n") }
                    }
                }
            } catch is CancellationError { self.status = "Scan cancelled. No files were moved." }
            catch { self.error = error.localizedDescription; self.status = "Scan needs attention." }
        }
    }

    func applySelected() async {
        guard let organizer, let source, let destination, !busy else { return }
        let selected = proposals.filter { $0.isSelected && $0.issue == nil }
        guard !selected.isEmpty else { return }
        await performWork {
            var moved = 0; var failures: [String] = []
            for (offset, proposal) in selected.enumerated() {
                if Task.isCancelled { break }
                self.progress = Double(offset) / Double(selected.count)
                self.status = "Organizing \(offset + 1) of \(selected.count)…"
                let result = await organizer.apply([proposal], sourceRoot: source, destinationRoot: destination)
                moved += result.moved; failures += result.errors
            }
            do { self.history = try await organizer.history() } catch { self.error = error.localizedDescription }
            self.proposals.removeAll { !FileManager.default.fileExists(atPath: $0.snapshot.url.path) }
            if let id = self.inspectedID, !self.proposals.contains(where: { $0.id == id }) { self.inspectedID = nil }
            self.status = "\(Task.isCancelled ? "Stopped. " : "")Organized \(moved) of \(selected.count) files. Undo is available in Activity."
            if !failures.isEmpty { self.error = failures.prefix(5).joined(separator: "\n") }
        }
    }

    func undo(_ operation: MoveOperation) async {
        guard let organizer, !busy else { return }
        automaticRules = false
        await performWork(cancellable: false) {
            do {
                try await organizer.undo(id: operation.id)
                self.history = try await organizer.history()
                self.proposals = []; self.inspectedID = nil; self.lastScan = nil
                self.status = "Restored \(operation.source.lastPathComponent). Automatic moves are paused."
            } catch { self.error = error.localizedDescription }
        }
    }

    func refineWithAI() async {
        guard !busy, let destination, let organizer else { return }
        refreshAI()
        guard aiReady else { error = aiStatus; return }
        let candidates = proposals.filter {
            $0.issue == nil && $0.origin != .manual && ($0.relativeDestination == "Documents" || $0.relativeDestination == "Images" || $0.origin == .unmatched) && AppleClassifier.supportedExtensions.contains($0.snapshot.url.pathExtension.lowercased())
        }
        guard !candidates.isEmpty else { status = "AI can read PDFs, text documents, and images matched to Documents or Images."; return }
        await performWork {
            var failures: [String] = []; var suggestions = 0
            for (offset, candidate) in candidates.enumerated() {
                if Task.isCancelled { break }
                self.progress = Double(offset) / Double(candidates.count)
                self.status = "Reading \(offset + 1) of \(candidates.count) locally…"
                do {
                    let suggestion = try await self.classifier.suggest(for: candidate.snapshot, policy: self.folderPolicy)
                    guard let index = self.proposals.firstIndex(where: { $0.id == candidate.id }) else { continue }
                    if let folder = suggestion.folder {
                        self.proposals[index].relativeDestination = folder
                        self.proposals[index].reason = suggestion.explanation
                        self.proposals[index].origin = .appleAI
                        self.proposals[index].isSelected = false
                        suggestions += 1
                    }
                } catch is CancellationError { break }
                catch { failures.append("\(candidate.snapshot.url.lastPathComponent): \(error.localizedDescription)") }
            }
            self.proposals = await organizer.validatePlan(self.proposals, destination: destination)
            self.status = "\(Task.isCancelled ? "Stopped. " : "")\(suggestions) AI suggestions ready for your review."
            if !failures.isEmpty { self.error = failures.prefix(5).joined(separator: "\n") }
        }
    }

    func updateMonitoring() {
        watcher.stop()
        guard monitoring, let source, destination != nil else { automaticRules = false; return }
        watcher.start(url: source) { [weak self] in
            guard let self, !self.busy else { return }
            Task { await self.scan(background: true) }
        }
    }

    func createDemo() async throws {
        let root = dataDirectory.appendingPathComponent("Sample files", isDirectory: true)
        let inbox = root.appendingPathComponent("Inbox", isDirectory: true)
        let output = root.appendingPathComponent("Organized", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let marker = root.appendingPathComponent(".created")
        if !FileManager.default.fileExists(atPath: marker.path) {
            let examples = [
                "Weekend reading.md": "# A guide to urban gardens\nStudy notes on soil composition, irrigation, and seasonal planting. These notes are for an introductory horticulture course.",
                "November receipt.txt": "RECEIPT\nExample Stationery Shop\nDate: November 11, 2026\nNotebook: 8.00\nPens: 4.00\nTOTAL PAID: 12.00\nPayment received. Thank you for your purchase.",
                "Project brief.txt": "PROJECT BRIEF\nWebsite redesign for an imaginary client. Deliverables: design mockups, accessibility review, and a production handoff. Deadline: December 10.",
                "Research notes.md": "# Learning Swift\nCourse notes: Swift value types, optionals, concurrency, and structured error handling. Practice exercises for next week's class.",
                "Unsorted.data": "This sample has an unfamiliar extension and should stay in the review queue.",
                "Still downloading.crdownload": "Incomplete download placeholder."
            ]
            for (name, text) in examples {
                let file = inbox.appendingPathComponent(name)
                try Data(text.utf8).write(to: file)
                try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: file.path)
            }
            try Data().write(to: marker)
        }
        source = inbox; destination = output
        config.source = try SavedFolder(inbox); config.destination = try SavedFolder(output)
        isDemo = true; persist()
        try addOCRSample()
        await scan()
        status = "Sample workspace · try organizing and undoing without using your own files."
    }

    private func addOCRSample() throws {
        let root = dataDirectory.appendingPathComponent("Sample files")
        let marker = root.appendingPathComponent(".ocr-sample-created")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        let file = root.appendingPathComponent("Inbox/Scanned receipt.png")
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        let image = NSImage(size: NSSize(width: 1200, height: 800))
        image.lockFocus()
        NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 1200, height: 800).fill()
        let lines = ["RECEIPT", "EXAMPLE STATIONERY STORE", "Date: 12 November 2026", "Notebook: 8.00", "Pens: 4.00", "TOTAL PAID: 12.00", "Payment received. Thank you!"]
        for (index, line) in lines.enumerated() {
            (line as NSString).draw(at: NSPoint(x: 80, y: 680 - index * 85), withAttributes: [.font: NSFont.systemFont(ofSize: 40, weight: index == 0 ? .bold : .regular), .foregroundColor: NSColor.black])
        }
        image.unlockFocus()
        if let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            try png.write(to: file, options: .withoutOverwriting)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: file.path)
            try Data().write(to: marker)
        }
    }
}
