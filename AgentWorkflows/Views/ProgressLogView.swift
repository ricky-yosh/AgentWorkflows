import SwiftUI

struct ProgressLogView: View {
    let fileURL: URL

    @State private var content: String = ""
    @State private var loadError: String?
    @State private var watcher: FileWatcher?

    var body: some View {
        Group {
            if let loadError {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text(loadError)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    Text(content)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .task(id: fileURL) {
            reload()
            watcher = FileWatcher(url: fileURL) { reload() }
        }
        .onDisappear {
            watcher = nil
        }
    }

    private func reload() {
        if let text = try? String(contentsOf: fileURL, encoding: .utf8) {
            content = text
            loadError = nil
        } else {
            content = ""
            loadError = "Could not read \(fileURL.lastPathComponent)."
        }
    }
}

final class FileWatcher {
    private let source: DispatchSourceFileSystemObject?
    private let fd: Int32

    init(url: URL, onChange: @escaping () -> Void) {
        let fd = open(url.path, O_EVTONLY)
        self.fd = fd
        guard fd >= 0 else {
            self.source = nil
            return
        }
        let src = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )
        src.setEventHandler(handler: onChange)
        src.setCancelHandler { [fd] in close(fd) }
        src.resume()
        self.source = src
    }

    deinit {
        source?.cancel()
    }
}
