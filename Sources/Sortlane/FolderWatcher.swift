import Foundation
import CoreServices

@MainActor
final class FolderWatcher {
    private var stream: FSEventStreamRef?
    private var timer: Timer?
    private var debounce: Task<Void, Never>?
    private var onChange: (@MainActor () -> Void)?

    func start(url: URL, onChange: @escaping @MainActor () -> Void) {
        stop()
        self.onChange = onChange
        var context = FSEventStreamContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(), retain: nil, release: nil, copyDescription: nil)
        stream = FSEventStreamCreate(nil, { _, info, _, _, _, _ in
            guard let info else { return }
            // The stream is delivered on the main queue; all events trigger a full source rescan.
            MainActor.assumeIsolated {
                Unmanaged<FolderWatcher>.fromOpaque(info).takeUnretainedValue().schedule()
            }
        }, &context, [url.path] as CFArray, FSEventStreamEventId(kFSEventStreamEventIdSinceNow), 2,
        FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot))
        if let stream {
            FSEventStreamSetDispatchQueue(stream, .main)
            if !FSEventStreamStart(stream) { FSEventStreamInvalidate(stream); FSEventStreamRelease(stream); self.stream = nil }
        }
        // Reconciliation also catches files that were too new at the last scan.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.schedule() }
        }
    }
    private func schedule() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            self?.onChange?()
        }
    }
    func stop() {
        debounce?.cancel(); debounce = nil
        timer?.invalidate(); timer = nil
        if let stream {
            FSEventStreamStop(stream); FSEventStreamInvalidate(stream); FSEventStreamRelease(stream)
        }
        stream = nil; onChange = nil
    }
}
