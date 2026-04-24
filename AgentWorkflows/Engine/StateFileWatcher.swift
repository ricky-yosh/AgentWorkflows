import Foundation

/// Injectable seam for watching writes to a session's state.json. The production
/// implementation wraps a kqueue DispatchSource; tests use a fake.
protocol StateFileWatcher: AnyObject {
    var onChange: (() -> Void)? { get set }
    func start(watching fileURL: URL)
    func stop()
}

/// Production `StateFileWatcher` that monitors a specific file via a kqueue
/// DispatchSource using NOTE_WRITE. The watched file must already exist when
/// `start(watching:)` is called; `SessionStore` satisfies this because state.json
/// is written before any watcher is attached.
final class DispatchSourceStateFileWatcher: StateFileWatcher {

    var onChange: (() -> Void)?
    private var source: DispatchSourceFileSystemObject?

    func start(watching fileURL: URL) {
        stop()
        let newFd = Darwin.open(fileURL.path, O_EVTONLY)
        guard newFd >= 0 else { return }

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: newFd,
            eventMask: .write,
            queue: DispatchQueue.global(qos: .utility)
        )
        src.setEventHandler { [weak self] in
            DispatchQueue.main.async { self?.onChange?() }
        }
        src.setCancelHandler { Darwin.close(newFd) }
        source = src
        src.resume()
    }

    func stop() {
        source?.cancel()
        source = nil  // cancel handler owns Darwin.close
    }

    deinit { stop() }
}
