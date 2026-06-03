import CoreServices
import Foundation

/// Watches a directory tree recursively using FSEvents.
/// FSEvents provides its own latency-based debounce; the callback fires on the main thread.
final class WorkingDirectoryWatcher {
    var onChange: (() -> Void)?

    private var streamRef: FSEventStreamRef?

    func start(watching directory: URL) {
        stop()
        let paths = [directory.path] as CFArray
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            let watcher = Unmanaged<WorkingDirectoryWatcher>.fromOpaque(info!).takeUnretainedValue()
            watcher.onChange?()
        }
        guard let stream = FSEventStreamCreate(
            nil,
            callback,
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.3,    // seconds of latency — natural debounce
            FSEventStreamCreateFlags(kFSEventStreamCreateFlagNoDefer)
        ) else { return }
        streamRef = stream
        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    func stop() {
        guard let stream = streamRef else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        streamRef = nil
    }

    deinit { stop() }
}
