import Foundation
import Darwin

/// A second boundary beyond macOS sandbox permissions. Models never control these roots.
public struct FolderPolicy: Sendable {
    public let roots: [URL]
    public static var userHome: URL {
        if let entry = getpwuid(getuid()), let path = entry.pointee.pw_dir {
            return URL(fileURLWithPath: String(cString: path), isDirectory: true).resolvingSymlinksInPath()
        }
        return FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath()
    }
    public init(roots: [URL] = [FolderPolicy.userHome]) { self.roots = roots.map(\.standardizedFileURL) }

    public func validateFolder(_ url: URL) throws {
        let url = url.standardizedFileURL
        let allowed = roots.contains { root in
            guard url != root, PathSafety.isInside(url, root: root) else { return false }
            let parts = Array(url.pathComponents.dropFirst(root.pathComponents.count))
            guard !parts.isEmpty else { return false }
            return !parts.contains { part in
                part.hasPrefix(".") || ["library", "applications", "node_modules", "vendor"].contains(part.lowercased()) ||
                    ["app", "photoslibrary", "musiclibrary", "bundle", "framework", "xcodeproj", "xcworkspace"].contains(URL(fileURLWithPath: part).pathExtension.lowercased())
            }
        }
        guard allowed else {
            throw SortlaneError.unsafeFile("Choose a regular folder inside your home folder, such as Downloads or Documents. System locations, the home folder itself, Library, hidden folders, and app libraries are protected.")
        }
        try PathSafety.rejectSymlinkComponents(url)
    }

    public func validateSource(_ url: URL) throws {
        try validateFolder(url)
        let markers = [".git", "Package.swift", "package.json", "Cargo.toml", "pyproject.toml", "go.mod", ".sortlane-protected"]
        guard let boundary = roots.filter({ PathSafety.isInside(url, root: $0) }).max(by: { $0.pathComponents.count < $1.pathComponents.count }) else {
            throw SortlaneError.unsafeFile("This folder is outside the authorized boundary.")
        }
        var current = url.standardizedFileURL
        while PathSafety.isInside(current, root: boundary) {
            if markers.contains(where: { FileManager.default.fileExists(atPath: current.appendingPathComponent($0).path) }) {
                throw SortlaneError.unsafeFile("This folder or one of its parents is a project or protected folder. Choose a dedicated inbox instead. A .sortlane-protected file excludes a folder and its descendants from sorting.")
            }
            if current == boundary { break }
            current.deleteLastPathComponent()
        }
    }
}
