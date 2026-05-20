import SwiftUI
import SwiftTerm

struct TerminalViewWrapper: NSViewRepresentable {
    let terminalView: LocalProcessTerminalView

    func makeCoordinator() -> Coordinator {
        Coordinator(terminalView: terminalView)
    }

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {}

    final class Coordinator {
        private var monitor: Any?
        private weak var terminalView: LocalProcessTerminalView?

        init(terminalView: LocalProcessTerminalView) {
            self.terminalView = terminalView
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                self?.handle(event) ?? event
            }
        }

        deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        private func handle(_ event: NSEvent) -> NSEvent? {
            guard
                event.keyCode == 36,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .shift,
                let view = terminalView,
                (view.window?.firstResponder as? NSView).map { $0 === view || $0.isDescendant(of: view) } == true
            else { return event }
            // Send a bare newline so the running CLI inserts a line break
            // without submitting.  Bracketed paste markers would require
            // the application to have bracketed-paste mode active, which
            // isn't guaranteed for CLI agents like claude-code.
            view.process?.send(data: ArraySlice([0x0A]))
            return nil
        }
    }
}
