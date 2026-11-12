import SwiftUI
import AppKit
import SortlaneCore

@main
struct SortlaneApp: App {
    @StateObject private var model: AppModel
    private let demo: Bool

    init() {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--check-ai") {
            let result = AppleClassifier.availabilityDescription()
            print(result.description)
            exit(result.available ? 0 : 2)
        }
        let directory: URL
        if let index = arguments.firstIndex(of: "--data-dir"), arguments.indices.contains(index + 1) {
            directory = URL(fileURLWithPath: arguments[index + 1], isDirectory: true).resolvingSymlinksInPath()
        } else {
            directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Sortlane", isDirectory: true)
        }
        demo = arguments.contains("--demo")
        _model = StateObject(wrappedValue: AppModel(dataDirectory: directory))
    }
    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 1_040, minHeight: 720)
                .task { if !model.initialized { await model.start(demo: demo) } }
        }
        .defaultSize(width: 1_220, height: 820)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Organize") {
                Button("Scan folder") { Task { await model.scan() } }.keyboardShortcut("r").disabled(!model.canScan)
                Button("Choose source folder…") { model.chooseFolder(isSource: true) }.disabled(model.busy)
                Button("Choose destination…") { model.chooseFolder(isSource: false) }.disabled(model.busy)
            }
        }
    }
}
