import Foundation

public enum Scanner {
    static let temporaryExtensions: Set<String> = ["crdownload", "download", "part", "partial", "tmp", "temp"]
    static let excludedDirectories: Set<String> = ["node_modules", "vendor", "Library", "Applications", "Photos Library.photoslibrary"]

    public static func scan(source: URL, destination: URL, rules: [SortingRule], recursive: Bool, minimumAge: TimeInterval = 10, policy: FolderPolicy = FolderPolicy()) throws -> ScanResult {
        let source = source.standardizedFileURL
        let destination = destination.standardizedFileURL
        try policy.validateSource(source)
        try policy.validateFolder(destination)
        guard source != destination, !PathSafety.isInside(source, root: destination) else {
            throw SortlaneError.unsafeFile("Choose separate source and destination folders. The source cannot be inside the destination.")
        }
        try PathSafety.rejectSymlinkComponents(source)
        try PathSafety.rejectSymlinkComponents(destination)
        for rule in rules { try rule.validate() }
        let matchers = rules.filter(\.isEnabled).map(RuleMatcher.init)
        let now = Date()
        var warnings: [String] = []
        let keys: [URLResourceKey] = [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .isPackageKey, .isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { url, error in
            warnings.append("\(url.lastPathComponent): \(error.localizedDescription)")
            return true
        }) else { throw SortlaneError.unavailable("Unable to read this folder.") }
        var proposals: [FileProposal] = []
        var skipped = 0
        for case let url as URL in enumerator {
            try Task.checkCancellation()
            if PathSafety.isInside(url, root: destination) { enumerator.skipDescendants(); skipped += 1; continue }
            do {
                let values = try url.resourceValues(forKeys: Set(keys))
                if values.isSymbolicLink == true || values.isPackage == true {
                    enumerator.skipDescendants(); skipped += 1; continue
                }
                if values.isDirectory == true {
                    if !recursive || excludedDirectories.contains(url.lastPathComponent) { enumerator.skipDescendants(); skipped += 1 }
                    else {
                        do { try policy.validateSource(url) }
                        catch { enumerator.skipDescendants(); skipped += 1 }
                    }
                    continue
                }
                guard values.isRegularFile == true else { skipped += 1; continue }
                if temporaryExtensions.contains(url.pathExtension.lowercased()) || (values.isUbiquitousItem == true && values.ubiquitousItemDownloadingStatus != .current) {
                    skipped += 1; continue
                }
                let snapshot = try FileSnapshot.read(url)
                guard Date().timeIntervalSince(snapshot.modified) >= minimumAge else { skipped += 1; continue }
                let rule = matchers.first { $0.matches(snapshot, now: now) }?.rule
                var proposal = FileProposal(snapshot: snapshot, relativeDestination: rule?.destinationFolder(for: snapshot),
                                            reason: rule.map { "Matched \($0.name)" } ?? "No rule matches this file", origin: rule == nil ? .unmatched : .rule)
                if let folder = proposal.relativeDestination {
                    do {
                        let target = try PathSafety.destination(root: destination, folder: folder, filename: url.lastPathComponent)
                        try policy.validateFolder(target.deletingLastPathComponent())
                        if FileManager.default.fileExists(atPath: target.path) { proposal.issue = "A file already exists at the destination"; proposal.isSelected = false }
                    } catch { proposal.issue = error.localizedDescription; proposal.isSelected = false }
                }
                proposals.append(proposal)
            } catch { warnings.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        // Two different source files may resolve to the same still-empty destination.
        var targets: [String: [Int]] = [:]
        for (index, proposal) in proposals.enumerated() {
            if let folder = proposal.relativeDestination {
                let path = folder + "/" + proposal.snapshot.url.lastPathComponent
                targets[path.lowercased(), default: []].append(index)
            }
        }
        for indices in targets.values where indices.count > 1 {
            for index in indices { proposals[index].issue = "Multiple files would use the same destination"; proposals[index].isSelected = false }
        }
        return ScanResult(proposals: proposals.sorted { $0.snapshot.url.lastPathComponent.localizedStandardCompare($1.snapshot.url.lastPathComponent) == .orderedAscending }, skipped: skipped, warnings: warnings)
    }
}
