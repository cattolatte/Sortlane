// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sortlane",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Sortlane", targets: ["Sortlane"]), .library(name: "SortlaneCore", targets: ["SortlaneCore"])],
    targets: [
        .systemLibrary(name: "CSQLite"),
        .target(name: "SortlaneCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "Sortlane", dependencies: ["SortlaneCore"]),
        .testTarget(name: "SortlaneCoreTests", dependencies: ["SortlaneCore"])
    ],
    swiftLanguageModes: [.v6]
)
