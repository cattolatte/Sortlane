import Foundation

public enum FileCategory: String, Codable, CaseIterable, Sendable, Identifiable {
    case documents = "Documents", images = "Images", videos = "Videos"
    case audio = "Audio", archives = "Archives", installers = "Installers"
    public var id: String { rawValue }
    public var symbol: String {
        switch self {
        case .documents: "doc.text"
        case .images: "photo"
        case .videos: "film"
        case .audio: "waveform"
        case .archives: "archivebox"
        case .installers: "shippingbox"
        }
    }
}

public struct SortingRule: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var extensions: [String]
    public var nameContains: String
    public var minimumBytes: Int64?
    public var maximumBytes: Int64?
    public var destination: String
    public var isEnabled: Bool
    public var namePattern: String?
    public var excludedNameContains: String?
    public var minimumAgeDays: Double?
    public var maximumAgeDays: Double?

    public init(id: UUID = UUID(), name: String, extensions: [String], nameContains: String = "", minimumBytes: Int64? = nil, maximumBytes: Int64? = nil, destination: String, isEnabled: Bool = true, namePattern: String? = nil, excludedNameContains: String? = nil, minimumAgeDays: Double? = nil, maximumAgeDays: Double? = nil) {
        self.id = id; self.name = name; self.extensions = extensions
        self.nameContains = nameContains; self.minimumBytes = minimumBytes
        self.maximumBytes = maximumBytes; self.destination = destination; self.isEnabled = isEnabled
        self.namePattern = namePattern; self.excludedNameContains = excludedNameContains
        self.minimumAgeDays = minimumAgeDays; self.maximumAgeDays = maximumAgeDays
    }

    public func matches(_ file: FileSnapshot) -> Bool {
        RuleMatcher(self).matches(file, now: Date())
    }

    public static var defaults: [Self] { [
        .init(name: "Documents", extensions: ["pdf", "txt", "md", "rtf", "doc", "docx", "xls", "xlsx", "csv", "ppt", "pptx", "pages", "numbers", "key"], destination: "Documents"),
        .init(name: "Images", extensions: ["jpg", "jpeg", "png", "gif", "heic", "webp", "tiff", "svg", "avif", "raw"], destination: "Images"),
        .init(name: "Videos", extensions: ["mp4", "mov", "mkv", "avi", "webm", "m4v"], destination: "Videos"),
        .init(name: "Audio", extensions: ["mp3", "wav", "m4a", "flac", "aac", "aiff", "ogg"], destination: "Audio"),
        .init(name: "Archives", extensions: ["zip", "rar", "7z", "tar", "gz", "bz2"], destination: "Archives"),
        .init(name: "Installers", extensions: ["dmg", "pkg", "iso"], destination: "Installers")
    ] }
}

public struct FileSnapshot: Codable, Equatable, Sendable {
    public let url: URL
    public let size: Int64
    public let modified: Date
    public let fileID: UInt64
    public let volumeID: UInt64

    public static func read(_ url: URL) throws -> Self {
        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attrs[.type] as? FileAttributeType == .typeRegular else { throw SortlaneError.unsafeFile("Only regular files can be organized.") }
        guard let size = attrs[.size] as? NSNumber, let modified = attrs[.modificationDate] as? Date,
              let fileID = attrs[.systemFileNumber] as? NSNumber, let volumeID = attrs[.systemNumber] as? NSNumber else {
            throw SortlaneError.unsafeFile("File identity could not be verified. The file was left in place.")
        }
        return Self(url: url.standardizedFileURL, size: size.int64Value, modified: modified,
                    fileID: fileID.uint64Value, volumeID: volumeID.uint64Value)
    }

    public func hasSameIdentity(as other: Self) -> Bool {
        size == other.size && modified == other.modified && fileID == other.fileID && volumeID == other.volumeID
    }
}

public enum ProposalOrigin: String, Codable, Sendable { case rule, appleAI, manual, unmatched }

public struct FileProposal: Identifiable, Sendable {
    public var id: UUID
    public let snapshot: FileSnapshot
    public var relativeDestination: String?
    public var reason: String
    public var origin: ProposalOrigin
    public var issue: String?
    public var isSelected: Bool
    public init(snapshot: FileSnapshot, relativeDestination: String?, reason: String, origin: ProposalOrigin, issue: String? = nil) {
        id = UUID(); self.snapshot = snapshot; self.relativeDestination = relativeDestination
        self.reason = reason; self.origin = origin; self.issue = issue
        isSelected = relativeDestination != nil && issue == nil && origin == .rule
    }
}

public enum OperationStatus: String, Codable, Sendable { case prepared, moved, undoPrepared, undone, failed, needsReview }

public struct MoveOperation: Codable, Identifiable, Sendable {
    public let id: UUID
    public let source: URL
    public let destination: URL
    public let snapshot: FileSnapshot
    public let digest: String
    public let createdAt: Date
    public var status: OperationStatus
    public var message: String?
    public init(source: URL, destination: URL, snapshot: FileSnapshot, digest: String) {
        id = UUID(); self.source = source; self.destination = destination
        self.snapshot = snapshot; self.digest = digest; createdAt = Date(); status = .prepared
    }
}

public struct ScanResult: Sendable {
    public var proposals: [FileProposal]
    public var skipped: Int
    public var warnings: [String]
}

public enum SortlaneError: LocalizedError, Sendable {
    case unsafeFile(String), conflict(String), changed(String), database(String), unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .unsafeFile(let s), .conflict(let s), .changed(let s), .database(let s), .unavailable(let s): s
        }
    }
}
