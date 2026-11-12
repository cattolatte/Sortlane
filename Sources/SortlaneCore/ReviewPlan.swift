import Foundation

public enum ReviewPlan {
    /// Rescanning must not turn an unapproved AI suggestion back into an automatic rule move.
    public static func merge(fresh: [FileProposal], previous: [FileProposal]) -> [FileProposal] {
        let oldByURL = Dictionary(previous.map { ($0.snapshot.url, $0) }, uniquingKeysWith: { _, latest in latest })
        return fresh.map { fresh in
            guard let old = oldByURL[fresh.snapshot.url], old.snapshot == fresh.snapshot else { return fresh }
            var updated = fresh
            updated.id = old.id
            if old.origin == .appleAI || old.origin == .manual {
                updated.relativeDestination = old.relativeDestination
                updated.reason = old.reason
                updated.origin = old.origin
                updated.issue = old.issue
                updated.isSelected = old.isSelected && old.issue == nil
                return updated
            }
            updated.isSelected = old.isSelected && old.issue == nil && fresh.issue == nil
            return updated
        }
    }

    /// Revalidate the actual merged destinations, including AI destinations, after every scan.
    public static func validate(_ proposals: [FileProposal], destination: URL, policy: FolderPolicy) -> [FileProposal] {
        var checked = proposals
        var targets: [String: [Int]] = [:]
        for index in checked.indices {
            guard let folder = checked[index].relativeDestination else { checked[index].isSelected = false; continue }
            checked[index].issue = nil
            do {
                let target = try PathSafety.destination(root: destination, folder: folder, filename: checked[index].snapshot.url.lastPathComponent)
                try policy.validateFolder(target.deletingLastPathComponent())
                targets[target.path.lowercased(), default: []].append(index)
                if FileManager.default.fileExists(atPath: target.path) {
                    checked[index].issue = "A file already exists at the destination"
                    checked[index].isSelected = false
                }
            } catch { checked[index].issue = error.localizedDescription; checked[index].isSelected = false }
        }
        for indices in targets.values where indices.count > 1 {
            for index in indices {
                checked[index].issue = "Multiple files would use the same destination"
                checked[index].isSelected = false
            }
        }
        return checked
    }
}
