import Foundation
import CryptoKit
import Darwin

public struct ApplyResult: Sendable {
    public var moved: Int = 0
    public var errors: [String] = []
}

public actor Organizer {
    private let database: Database
    private let policy: FolderPolicy
    public init(databaseURL: URL, policy: FolderPolicy = FolderPolicy()) throws {
        database = try Database(url: databaseURL); self.policy = policy
    }

    public func loadSettings() throws -> Data? { try database.setting(key: "configuration") }
    public func saveSettings(_ data: Data) throws { try database.saveSetting(data, key: "configuration") }
    public func history() throws -> [MoveOperation] { try database.operations() }
    public func validatePlan(_ proposals: [FileProposal], destination: URL) -> [FileProposal] {
        ReviewPlan.validate(proposals, destination: destination, policy: policy)
    }

    public func scan(source: URL, destination: URL, rules: [SortingRule], recursive: Bool, previous: [FileProposal] = []) throws -> ScanResult {
        var result = try Scanner.scan(source: source, destination: destination, rules: rules, recursive: recursive, policy: policy)
        if !previous.isEmpty { result.proposals = ReviewPlan.validate(ReviewPlan.merge(fresh: result.proposals, previous: previous), destination: destination, policy: policy) }
        return result
    }

    public func apply(_ proposals: [FileProposal], sourceRoot: URL, destinationRoot: URL) -> ApplyResult {
        var result = ApplyResult()
        for proposal in proposals where proposal.isSelected {
            if Task.isCancelled { break }
            do {
                try Task.checkCancellation()
                try move(proposal, sourceRoot: sourceRoot, destinationRoot: destinationRoot)
                result.moved += 1
            } catch { result.errors.append("\(proposal.snapshot.url.lastPathComponent): \(error.localizedDescription)") }
        }
        return result
    }

    private func move(_ proposal: FileProposal, sourceRoot: URL, destinationRoot: URL) throws {
        try policy.validateSource(sourceRoot)
        try policy.validateFolder(destinationRoot)
        try policy.validateSource(proposal.snapshot.url.deletingLastPathComponent())
        guard let folder = proposal.relativeDestination, proposal.issue == nil else { throw SortlaneError.unsafeFile("This file needs review.") }
        guard sourceRoot.standardizedFileURL != destinationRoot.standardizedFileURL,
              !PathSafety.isInside(sourceRoot, root: destinationRoot),
              PathSafety.isInside(proposal.snapshot.url, root: sourceRoot),
              !PathSafety.isInside(proposal.snapshot.url, root: destinationRoot) else { throw SortlaneError.unsafeFile("The source or destination is outside this plan.") }
        try PathSafety.rejectSymlinkComponents(proposal.snapshot.url)
        let target = try PathSafety.destination(root: destinationRoot, folder: folder, filename: proposal.snapshot.url.lastPathComponent)
        try policy.validateFolder(target.deletingLastPathComponent())
        guard !FileManager.default.fileExists(atPath: target.path) else { throw SortlaneError.conflict("Destination already exists. Nothing was overwritten.") }
        let before = try FileSnapshot.read(proposal.snapshot.url)
        guard proposal.snapshot.hasSameIdentity(as: before), Date().timeIntervalSince(before.modified) >= 10 else {
            throw SortlaneError.changed("File changed since the preview. Scan again.")
        }
        let digest = try Self.digest(at: before.url)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try PathSafety.rejectSymlinkComponents(target)
        let parentAttributes = try FileManager.default.attributesOfItem(atPath: target.deletingLastPathComponent().path)
        guard (parentAttributes[.systemNumber] as? NSNumber)?.uint64Value == before.volumeID else {
            throw SortlaneError.unsafeFile("Moving between disks is not supported in this preview. Choose a destination on the same disk.")
        }
        guard before.hasSameIdentity(as: try FileSnapshot.read(before.url)) else { throw SortlaneError.changed("File changed while being checked.") }
        var operation = MoveOperation(source: before.url, destination: target, snapshot: before, digest: digest)
        try database.save(operation)
        do { try Self.renameExclusively(from: before.url, to: target) }
        catch {
            operation.status = .failed; operation.message = error.localizedDescription
            try database.save(operation)
            throw error
        }
        // If saving fails, the prepared entry remains recoverable on next launch.
        operation.status = .moved
        try database.save(operation)
    }

    public func undo(id: UUID) throws {
        guard var operation = try database.operations().first(where: { $0.id == id }), operation.status == .moved else {
            throw SortlaneError.unavailable("This operation cannot be undone.")
        }
        try policy.validateSource(operation.source.deletingLastPathComponent())
        try policy.validateFolder(operation.destination.deletingLastPathComponent())
        try PathSafety.rejectSymlinkComponents(operation.source)
        try PathSafety.rejectSymlinkComponents(operation.destination)
        guard !FileManager.default.fileExists(atPath: operation.source.path) else { throw SortlaneError.conflict("The original location is occupied. Undo would overwrite a file.") }
        guard operation.snapshot.hasSameIdentity(as: try FileSnapshot.read(operation.destination)),
              try Self.digest(at: operation.destination) == operation.digest else {
            throw SortlaneError.changed("The moved file has changed. It was left in place.")
        }
        guard FileManager.default.fileExists(atPath: operation.source.deletingLastPathComponent().path) else {
            throw SortlaneError.unavailable("The original folder no longer exists.")
        }
        operation.status = .undoPrepared
        try database.save(operation)
        do { try Self.renameExclusively(from: operation.destination, to: operation.source) }
        catch { operation.status = .moved; try database.save(operation); throw error }
        operation.status = .undone
        try database.save(operation)
    }

    public func recoverInterruptedOperations() throws -> Int {
        var count = 0
        for var operation in try database.operations() where operation.status == .prepared || operation.status == .undoPrepared {
            let expected = operation.status == .prepared ? operation.destination : operation.source
            let other = operation.status == .prepared ? operation.source : operation.destination
            let completed = operation.status == .prepared ? OperationStatus.moved : .undone
            let notCompleted = operation.status == .prepared ? OperationStatus.failed : .moved
            if try matchesRecordedFile(expected, operation: operation), !FileManager.default.fileExists(atPath: other.path) {
                operation.status = completed; operation.message = "Recovered after interruption"
            } else if try matchesRecordedFile(other, operation: operation), !FileManager.default.fileExists(atPath: expected.path) {
                operation.status = notCompleted; operation.message = "Interrupted before the move completed"
            } else {
                operation.status = .needsReview; operation.message = "File locations changed after interruption. Check both paths in Finder."
            }
            try database.save(operation); count += 1
        }
        return count
    }

    private func matchesRecordedFile(_ url: URL, operation: MoveOperation) throws -> Bool {
        guard FileManager.default.fileExists(atPath: url.path) else { return false }
        do {
            try policy.validateFolder(url.deletingLastPathComponent())
            try PathSafety.rejectSymlinkComponents(url)
            let snapshot = try FileSnapshot.read(url)
            guard operation.snapshot.hasSameIdentity(as: snapshot) else { return false }
            return try Self.digest(at: url) == operation.digest
        } catch { return false }
    }

    static func renameExclusively(from source: URL, to target: URL) throws {
        let result = source.withUnsafeFileSystemRepresentation { src in
            target.withUnsafeFileSystemRepresentation { dst in renamex_np(src!, dst!, UInt32(RENAME_EXCL)) }
        }
        guard result == 0 else {
            let code = errno
            if code == EEXIST { throw SortlaneError.conflict("Destination already exists. Nothing was overwritten.") }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code))
        }
    }

    static func digest(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
