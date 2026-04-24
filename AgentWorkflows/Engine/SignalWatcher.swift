import Foundation

/// Injectable seam for Signal File observation. The production implementation
/// wraps a kqueue DispatchSource; tests fire the callback synchronously.
protocol SignalWatcher: AnyObject {
    var onFired: (() -> Void)? { get set }
    func startWatching(signalFilePath: String)
    func stopWatching()
}

/// Production `SignalWatcher` that watches the parent directory of the Signal
/// File via a kqueue DispatchSource. Injected into `PromptDispatcher` from the app;
/// tests use a fake.
final class DispatchSourceSignalWatcher: SignalWatcher {

    var onFired: (() -> Void)?
    private var source: DispatchSourceFileSystemObject?
    private var fd: Int32 = -1

    func startWatching(signalFilePath: String) {
        stopWatching()
        let dir = (signalFilePath as NSString).deletingLastPathComponent
        let newFd = open(dir, O_EVTONLY)
        guard newFd >= 0 else { return }
        fd = newFd

        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: newFd,
            eventMask: .write,
            queue: .global()
        )
        src.setEventHandler { [weak self, signalFilePath] in
            guard FileManager.default.fileExists(atPath: signalFilePath) else { return }
            try? FileManager.default.removeItem(atPath: signalFilePath)
            DispatchQueue.main.async { self?.onFired?() }
        }
        source = src
        src.resume()
    }

    func stopWatching() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd); fd = -1 }
    }

    deinit { stopWatching() }
}
