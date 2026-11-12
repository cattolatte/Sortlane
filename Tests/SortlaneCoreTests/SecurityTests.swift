import XCTest
@testable import SortlaneCore

@MainActor
final class SecurityTests: XCTestCase {
    struct Fixture {
        let root: URL
        let source: URL
        let destination: URL
        let policy: FolderPolicy
        init() throws {
            // macOS normalizes /private/var back to the /var symlink. Use a real,
            // project-local directory so the symlink policy remains uncompromised.
            root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .appendingPathComponent(".build/SecurityFixtures/\(UUID().uuidString)", isDirectory: true)
            source = root.appendingPathComponent("Inbox", isDirectory: true)
            destination = root.appendingPathComponent("Organized", isDirectory: true)
            policy = FolderPolicy(roots: [root])
            try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        }
        func cleanup() { try? FileManager.default.removeItem(at: root) }
        func file(_ name: String = "note.txt", content: String = "original contents", in folder: URL? = nil) throws -> URL {
            let url = (folder ?? source).appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(content.utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-60)], ofItemAtPath: url.path)
            return url
        }
        func organizer() throws -> Organizer { try Organizer(databaseURL: root.appendingPathComponent("state.sqlite"), policy: policy) }
        func scan(recursive: Bool = false, rules: [SortingRule] = SortingRule.defaults) throws -> ScanResult {
            try Scanner.scan(source: source, destination: destination, rules: rules, recursive: recursive, policy: policy)
        }
    }

    func testSystemHomeAndPrivateFoldersAreRejected() throws {
        let home = FolderPolicy.userHome
        let policy = FolderPolicy()
        for path in ["/", "/System", "/Library", "/Applications", "/usr", "/private", "/Users", home.path, home.appendingPathComponent("Library").path, home.appendingPathComponent(".ssh").path, home.appendingPathComponent("Documents/.secrets").path, home.appendingPathComponent("Applications").path] {
            XCTAssertThrowsError(try policy.validateFolder(URL(fileURLWithPath: path)), path)
        }
        XCTAssertNoThrow(try policy.validateFolder(home.appendingPathComponent("Downloads")))
    }

    func testTraversalAndHiddenDestinationsAreRejected() throws {
        for path in ["../Documents", "/etc", "Documents/../../Library", "Documents//Bills", "", "Documents/.hidden", "Documents/.", "Documents/", "Documents\0evil"] {
            XCTAssertThrowsError(try PathSafety.validateRelativeFolder(path), path)
        }
        XCTAssertNoThrow(try PathSafety.validateRelativeFolder("Documents/Receipts"))
    }

    func testSimilarPathPrefixIsNotInsideRoot() {
        XCTAssertFalse(PathSafety.isInside(URL(fileURLWithPath: "/Users/me/Downloads-other/file"), root: URL(fileURLWithPath: "/Users/me/Downloads")))
    }

    func testPreviewDoesNotMoveFiles() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let scan = try fixture.scan()
        XCTAssertEqual(scan.proposals.count, 1)
        XCTAssertEqual(scan.proposals[0].relativeDestination, "Documents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path), [])
    }

    func testSkipsTemporaryHiddenAndRecentlyModifiedFiles() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file("incomplete.crdownload")
        _ = try fixture.file(".secret.txt")
        let recent = try fixture.file("recent.txt")
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: recent.path)
        _ = try fixture.file("finished.txt")
        let result = try fixture.scan()
        XCTAssertEqual(result.proposals.map { $0.snapshot.url.lastPathComponent }, ["finished.txt"])
    }

    func testSkipsSymlinkFilesAndDirectories() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let external = try fixture.file("secret.txt", in: fixture.root.appendingPathComponent("Outside"))
        try FileManager.default.createSymbolicLink(at: fixture.source.appendingPathComponent("linked.txt"), withDestinationURL: external)
        try FileManager.default.createSymbolicLink(at: fixture.source.appendingPathComponent("linked-folder"), withDestinationURL: external.deletingLastPathComponent())
        XCTAssertTrue(try fixture.scan(recursive: true).proposals.isEmpty)
    }

    func testProtectedAndProjectSubfoldersAreNotTraversed() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        for (name, marker) in [("Project", "Package.swift"), ("Private", ".sortlane-protected"), ("Website", "package.json")] {
            let folder = fixture.source.appendingPathComponent(name)
            _ = try fixture.file(marker, in: folder)
            _ = try fixture.file("notes.txt", in: folder)
        }
        _ = try fixture.file("allowed.txt")
        XCTAssertEqual(try fixture.scan(recursive: true).proposals.map { $0.snapshot.url.lastPathComponent }, ["allowed.txt"])
    }

    func testUnknownFilesStayUnselected() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file("unknown.blob")
        let proposal = try XCTUnwrap(fixture.scan().proposals.first)
        XCTAssertFalse(proposal.isSelected)
        XCTAssertNil(proposal.relativeDestination)
    }

    func testFirstMatchingRuleWinsAndConditionsAreAnded() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file("invoice.txt")
        let rules: [SortingRule] = [
            .init(name: "Wrong type", extensions: ["pdf"], nameContains: "invoice", destination: "Wrong"),
            .init(name: "Too large", extensions: ["txt"], minimumBytes: 1000, destination: "Wrong"),
            .init(name: "Invoices", extensions: ["TXT"], nameContains: "INVOICE", destination: "Documents/Bills")
        ] + SortingRule.defaults
        XCTAssertEqual(try fixture.scan(rules: rules).proposals.first?.relativeDestination, "Documents/Bills")
    }

    func testSourceAndDestinationCannotOverlapBackwards() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        XCTAssertThrowsError(try Scanner.scan(source: fixture.source, destination: fixture.source, rules: [], recursive: true, policy: fixture.policy))
    }

    func testNestedDestinationIsExcludedFromScan() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let nested = fixture.source.appendingPathComponent("Sorted")
        _ = try fixture.file("already.txt", in: nested)
        _ = try fixture.file("new.txt")
        let result = try Scanner.scan(source: fixture.source, destination: nested, rules: SortingRule.defaults, recursive: true, policy: fixture.policy)
        XCTAssertEqual(result.proposals.map { $0.snapshot.url.lastPathComponent }, ["new.txt"])
    }

    func testDuplicatePlannedDestinationsAreFlagged() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file("same.txt", in: fixture.source.appendingPathComponent("One"))
        _ = try fixture.file("same.txt", in: fixture.source.appendingPathComponent("Two"))
        let proposals = try fixture.scan(recursive: true).proposals
        XCTAssertEqual(proposals.count, 2)
        XCTAssertTrue(proposals.allSatisfy { $0.issue != nil && !$0.isSelected })
    }

    func testMoveAndUndoPreserveBytesAndPersistHistory() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let expected = try Data(contentsOf: file)
        let organizer = try fixture.organizer()
        let result = await organizer.apply(try fixture.scan().proposals, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 1); XCTAssertTrue(result.errors.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let history = try await organizer.history()
        let entry = try XCTUnwrap(history.first)
        XCTAssertEqual(try Data(contentsOf: entry.destination), expected)
        let reopened = try fixture.organizer()
        let reopenedHistory = try await reopened.history()
        XCTAssertEqual(reopenedHistory.first?.id, entry.id)
        try await organizer.undo(id: entry.id)
        XCTAssertEqual(try Data(contentsOf: file), expected)
        let undoneHistory = try await organizer.history()
        XCTAssertEqual(undoneHistory.first?.status, .undone)
    }

    func testChangedFileAfterPreviewIsNotMoved() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let plan = try fixture.scan().proposals
        try Data("edited after preview".utf8).write(to: file)
        let result = await (try fixture.organizer()).apply(plan, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 0); XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testCollisionCreatedAfterPreviewNeverOverwrites() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        let plan = try fixture.scan().proposals
        let target = try fixture.file("note.txt", content: "existing target", in: fixture.destination.appendingPathComponent("Documents"))
        let result = await (try fixture.organizer()).apply(plan, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 0)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "existing target")
    }

    func testSymlinkInsertedIntoDestinationAfterPreviewIsRejected() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        let plan = try fixture.scan().proposals
        let outside = fixture.root.appendingPathComponent("Outside")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: fixture.destination.appendingPathComponent("Documents"), withDestinationURL: outside)
        let result = await (try fixture.organizer()).apply(plan, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }

    func testForgedOutOfScopeProposalCannotMove() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let external = try fixture.file("outside.txt", in: fixture.root.appendingPathComponent("Outside"))
        let forged = FileProposal(snapshot: try FileSnapshot.read(external), relativeDestination: "Documents", reason: "forged", origin: .rule)
        let result = await (try fixture.organizer()).apply([forged], sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: external.path))
    }

    func testProtectedDestinationFromRuleIsRejected() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        var plan = try fixture.scan().proposals
        plan[0].relativeDestination = "Library/Secrets"
        let result = await (try fixture.organizer()).apply(plan, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 0)
    }

    func testUndoDoesNotOverwriteNewSourceFile() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        let organizer = try fixture.organizer()
        _ = await organizer.apply(try fixture.scan().proposals, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        let history = try await organizer.history()
        let entry = try XCTUnwrap(history.first)
        let replacement = try fixture.file(content: "new contents")
        do { try await organizer.undo(id: entry.id); XCTFail("Undo must reject occupied source") } catch {}
        XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "new contents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.destination.path))
    }

    func testUndoRejectsContentChangeEvenWithRestoredSizeAndTimestamp() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file(content: "aaaa")
        let organizer = try fixture.organizer()
        _ = await organizer.apply(try fixture.scan().proposals, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        let history = try await organizer.history()
        let entry = try XCTUnwrap(history.first)
        let handle = try FileHandle(forWritingTo: entry.destination)
        try handle.write(contentsOf: Data("bbbb".utf8)); try handle.close()
        try FileManager.default.setAttributes([.modificationDate: entry.snapshot.modified], ofItemAtPath: entry.destination.path)
        do { try await organizer.undo(id: entry.id); XCTFail("Undo must reject changed bytes") } catch {}
        XCTAssertTrue(FileManager.default.fileExists(atPath: entry.destination.path))
    }

    func testRecoveryRecognizesCompletedMove() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let snapshot = try FileSnapshot.read(file)
        let target = fixture.destination.appendingPathComponent("note.txt")
        let operation = MoveOperation(source: file, destination: target, snapshot: snapshot, digest: try Organizer.digest(at: file))
        let database = try Database(url: fixture.root.appendingPathComponent("state.sqlite"))
        try database.save(operation)
        try FileManager.default.moveItem(at: file, to: target)
        let organizer = try fixture.organizer()
        let recovered = try await organizer.recoverInterruptedOperations()
        XCTAssertEqual(recovered, 1)
        let history = try await organizer.history()
        XCTAssertEqual(history.first?.status, .moved)
    }

    func testRecoveryDoesNotGuessWhenBothPathsExist() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let target = try fixture.file("note.txt", in: fixture.destination)
        let operation = MoveOperation(source: file, destination: target, snapshot: try FileSnapshot.read(file), digest: try Organizer.digest(at: file))
        let database = try Database(url: fixture.root.appendingPathComponent("state.sqlite"))
        try database.save(operation)
        let organizer = try fixture.organizer()
        _ = try await organizer.recoverInterruptedOperations()
        let history = try await organizer.history()
        XCTAssertEqual(history.first?.status, .needsReview)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
    }

    func testExclusiveRenameRefusesExistingTarget() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let source = try fixture.file("one.txt", content: "one")
        let target = try fixture.file("two.txt", content: "two")
        XCTAssertThrowsError(try Organizer.renameExclusively(from: source, to: target))
        XCTAssertEqual(try String(contentsOf: source, encoding: .utf8), "one")
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "two")
    }

    func testRescanKeepsAISuggestionsUnapproved() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        let fresh = try fixture.scan().proposals
        var ai = fresh[0]
        ai.origin = .appleAI; ai.relativeDestination = "Documents/Receipts"
        ai.reason = "Proof of purchase"; ai.isSelected = false
        let merged = ReviewPlan.merge(fresh: fresh, previous: [ai])
        XCTAssertEqual(merged[0].origin, .appleAI)
        XCTAssertEqual(merged[0].relativeDestination, "Documents/Receipts")
        XCTAssertFalse(merged[0].isSelected)
    }

    func testRescanPreservesManualDeselectionAndNewConflicts() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        let fresh = try fixture.scan().proposals
        var old = fresh[0]; old.isSelected = false
        XCTAssertFalse(ReviewPlan.merge(fresh: fresh, previous: [old])[0].isSelected)
        var conflicting = fresh[0]; conflicting.issue = "Destination exists"; conflicting.isSelected = false
        let merged = ReviewPlan.merge(fresh: [conflicting], previous: fresh)
        XCTAssertNotNil(merged[0].issue)
        XCTAssertFalse(merged[0].isSelected)
    }

    func testAIConflictCannotBecomeAnAutomaticRuleMoveOnRescan() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        var ai = try XCTUnwrap(fixture.scan().proposals.first)
        ai.origin = .appleAI; ai.relativeDestination = "Documents/Receipts"
        ai.issue = "Destination exists"; ai.isSelected = false
        _ = try fixture.file("note.txt", in: fixture.destination.appendingPathComponent("Documents/Receipts"))
        let organizer = try fixture.organizer()
        let rescan = try await organizer.scan(source: fixture.source, destination: fixture.destination, rules: SortingRule.defaults, recursive: false, previous: [ai])
        XCTAssertEqual(rescan.proposals[0].origin, .appleAI)
        XCTAssertEqual(rescan.proposals[0].relativeDestination, "Documents/Receipts")
        XCTAssertNotNil(rescan.proposals[0].issue)
        XCTAssertFalse(rescan.proposals[0].isSelected)
        let applied = await organizer.apply(rescan.proposals, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(applied.moved, 0)
    }

    func testResolvedAIConflictStillRequiresUserSelection() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        var ai = try XCTUnwrap(fixture.scan().proposals.first)
        ai.origin = .appleAI; ai.relativeDestination = "Documents/Receipts"
        ai.issue = "Old conflict"; ai.isSelected = false
        let rescan = try await (fixture.organizer()).scan(source: fixture.source, destination: fixture.destination, rules: SortingRule.defaults, recursive: false, previous: [ai])
        XCTAssertEqual(rescan.proposals[0].origin, .appleAI)
        XCTAssertNil(rescan.proposals[0].issue)
        XCTAssertFalse(rescan.proposals[0].isSelected)
    }

    func testLateAIConflictIsCheckedAtItsActualDestination() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file()
        var ai = try XCTUnwrap(fixture.scan().proposals.first)
        ai.origin = .appleAI; ai.relativeDestination = "Documents/Receipts"; ai.isSelected = true
        _ = try fixture.file("note.txt", in: fixture.destination.appendingPathComponent("Documents/Receipts"))
        let rescan = try await (fixture.organizer()).scan(source: fixture.source, destination: fixture.destination, rules: SortingRule.defaults, recursive: false, previous: [ai])
        XCTAssertEqual(rescan.proposals[0].origin, .appleAI)
        XCTAssertNotNil(rescan.proposals[0].issue)
        XCTAssertFalse(rescan.proposals[0].isSelected)
    }

    func testSelectingChildOfProtectedFolderIsRejected() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let parent = fixture.source.appendingPathComponent("Protected")
        let child = parent.appendingPathComponent("Nested")
        _ = try fixture.file("note.txt", in: child)
        _ = try fixture.file(".sortlane-protected", in: parent)
        XCTAssertThrowsError(try fixture.policy.validateSource(child))
    }

    func testAncestorProtectedAfterPreviewPreventsMove() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let parent = fixture.source.appendingPathComponent("Group")
        let child = parent.appendingPathComponent("Nested")
        let file = try fixture.file("note.txt", in: child)
        let plan = try fixture.scan(recursive: true).proposals
        XCTAssertEqual(plan.count, 1)
        _ = try fixture.file(".sortlane-protected", in: parent)
        let result = await (try fixture.organizer()).apply(plan, sourceRoot: fixture.source, destinationRoot: fixture.destination)
        XCTAssertEqual(result.moved, 0)
        XCTAssertEqual(result.errors.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testLegacyRulesDecodeWithNewFiltersUnset() throws {
        let rule = SortingRule.defaults[0]
        let data = try JSONEncoder().encode(rule)
        let decoded = try JSONDecoder().decode(SortingRule.self, from: data)
        XCTAssertNil(decoded.minimumAgeDays)
        XCTAssertNil(decoded.namePattern)
        XCTAssertEqual(decoded.destination, rule.destination)
    }

    func testFilenamePatternAndExclusionAreAnded() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file("Invoice-2026.txt")
        _ = try fixture.file("invoice-draft.txt")
        _ = try fixture.file("random.txt")
        let rule = SortingRule(name: "Invoices", extensions: ["txt"], destination: "Documents/Invoices", namePattern: "invoice-*.txt", excludedNameContains: "draft")
        let result = try fixture.scan(rules: [rule])
        XCTAssertEqual(result.proposals.filter { $0.origin == .rule }.map { $0.snapshot.url.lastPathComponent }, ["Invoice-2026.txt"])
    }

    func testWildcardMatchingIsWholeNameAndUnicodeSafe() {
        XCTAssertTrue(RuleMatcher.glob("résumé-1.pdf", pattern: "RÉSUMÉ-?.pdf"))
        XCTAssertFalse(RuleMatcher.glob("prefix-invoice.pdf", pattern: "invoice*"))
        XCTAssertFalse(RuleMatcher.glob("invoice12.pdf", pattern: "invoice?.pdf"))
        XCTAssertTrue(RuleMatcher.glob("file.txt", pattern: "*"))
        XCTAssertTrue(RuleMatcher.glob("", pattern: "*"))
    }

    func testAgeRangeMatchesModificationTime() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-5 * 86_400)], ofItemAtPath: file.path)
        var rule = SortingRule(name: "Archive", extensions: [], destination: "Archives", minimumAgeDays: 3, maximumAgeDays: 7)
        XCTAssertEqual(try fixture.scan(rules: [rule]).proposals[0].origin, .rule)
        rule.minimumAgeDays = 6
        XCTAssertEqual(try fixture.scan(rules: [rule]).proposals[0].origin, .unmatched)
    }

    func testDateFoldersExpandBeforePlanning() throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 6, day: 15, hour: 12)))
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: file.path)
        let rule = SortingRule(name: "By date", extensions: [], destination: "Documents/{year}/{month}")
        XCTAssertEqual(try fixture.scan(rules: [rule]).proposals[0].relativeDestination, "Documents/2020/06")
    }

    func testInvalidRuleIntervalsAndTemplatesAreRejected() throws {
        var rule = SortingRule(name: "Bad", extensions: [], destination: "Documents", minimumAgeDays: 7, maximumAgeDays: 3)
        XCTAssertThrowsError(try rule.validate())
        rule.minimumAgeDays = nil; rule.maximumAgeDays = .infinity
        XCTAssertThrowsError(try rule.validate())
        rule.maximumAgeDays = nil; rule.destination = "Documents/{unknown}"
        XCTAssertThrowsError(try rule.validate())
        rule.destination = "../{year}"
        XCTAssertThrowsError(try rule.validate())
    }

    func testManualDestinationAndInspectorIdentitySurviveRescan() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        _ = try fixture.file("unknown.blob")
        var manual = try XCTUnwrap(fixture.scan().proposals.first)
        manual.origin = .manual; manual.relativeDestination = "Documents/Custom"; manual.isSelected = false
        let plan = try await (fixture.organizer()).scan(source: fixture.source, destination: fixture.destination, rules: SortingRule.defaults, recursive: false, previous: [manual])
        XCTAssertEqual(plan.proposals[0].id, manual.id)
        XCTAssertEqual(plan.proposals[0].origin, .manual)
        XCTAssertEqual(plan.proposals[0].relativeDestination, "Documents/Custom")
        XCTAssertFalse(plan.proposals[0].isSelected)
    }

    func testCancelledScanDoesNotMoveFiles() async throws {
        let fixture = try Fixture(); defer { fixture.cleanup() }
        let file = try fixture.file()
        let task = Task { () -> Bool in
            withUnsafeCurrentTask { $0?.cancel() }
            do { _ = try fixture.scan(); return false } catch is CancellationError { return true } catch { return false }
        }
        let cancelled = await task.value
        XCTAssertTrue(cancelled)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }
}
