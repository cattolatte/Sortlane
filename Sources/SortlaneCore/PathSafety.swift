import Foundation

public enum PathSafety {
    public static func isInside(_ child: URL, root: URL) -> Bool {
        let rootPath = root.standardizedFileURL.path
        let childPath = child.standardizedFileURL.path
        return childPath == rootPath || childPath.hasPrefix(rootPath == "/" ? "/" : rootPath + "/")
    }

    public static func validateRelativeFolder(_ path: String) throws {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".") && !$0.contains(":") }) else {
            throw SortlaneError.unsafeFile("Use a relative folder such as Documents/Receipts, without hidden folders or '..'.")
        }
    }

    public static func rejectSymlinkComponents(_ url: URL) throws {
        var component = URL(fileURLWithPath: "/")
        for part in url.standardizedFileURL.pathComponents.dropFirst() {
            component.appendPathComponent(part)
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: component.path)
                if attributes[.type] as? FileAttributeType == .typeSymbolicLink {
                    throw SortlaneError.unsafeFile("Symbolic links are excluded: \(component.lastPathComponent).")
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
                return
            }
        }
    }

    public static func destination(root: URL, folder: String, filename: String) throws -> URL {
        try validateRelativeFolder(folder)
        guard !filename.isEmpty, !filename.contains("/"), filename != ".", filename != ".." else {
            throw SortlaneError.unsafeFile("Invalid filename.")
        }
        let target = root.appendingPathComponent(folder, isDirectory: true).appendingPathComponent(filename).standardizedFileURL
        guard isInside(target, root: root) else { throw SortlaneError.unsafeFile("Destination is outside the selected folder.") }
        try rejectSymlinkComponents(target)
        return target
    }
}
