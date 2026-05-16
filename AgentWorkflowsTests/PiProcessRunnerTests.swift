import Foundation
import Testing
@testable import AgentWorkflows

@Suite("PiProcessRunner")
struct PiProcessRunnerTests {

    final class FakeProcessHandle: ProcessHandle {
        func terminate() {}
        func killImmediately() {}
    }

    @Test func runUsesExactPiArgumentsAndDropsEffortFlag() {
        var capturedArguments: [String] = []
        var capturedWorkingDirectory: URL?
        var launchHook: (() -> Void)?

        let fakeHandle = FakeProcessHandle()
        let runner = PiProcessRunner(
            runSubprocess: { arguments, workingDirectory, _, onLaunch, _, _, _ in
                capturedArguments = arguments
                capturedWorkingDirectory = workingDirectory
                launchHook = onLaunch
                return fakeHandle
            }
        )

        var rawLines: [String] = []
        let returnedHandle = runner.run(
            workingDirectory: URL(fileURLWithPath: "/tmp/project"),
            progressDirectory: URL(fileURLWithPath: "/tmp/project/.aw-cache/session"),
            effort: .high,
            onEvent: { _ in },
            onRawLine: { rawLines.append($0) },
            onExit: { _ in }
        )

        #expect(returnedHandle as AnyObject === fakeHandle)
        #expect(capturedWorkingDirectory?.path == "/tmp/project")
        #expect(capturedArguments == [
            "pi", "-p",
            "--mode", "json",
            "/skill:ralph /tmp/project/.aw-cache/session"
        ])
        #expect(capturedArguments.contains("--effort") == false)
        #expect(capturedArguments.contains("high") == false)

        launchHook?()
        #expect(rawLines == ["[effort] high"])
    }
}
