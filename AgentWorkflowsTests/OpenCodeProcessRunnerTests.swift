import Foundation
import Testing
@testable import AgentWorkflows

@Suite("OpenCodeProcessRunner")
struct OpenCodeProcessRunnerTests {

    final class FakeProcessHandle: ProcessHandle {
        func terminate() {}
        func killImmediately() {}
    }

    @Test func runUsesExactOpenCodeArgumentsAndDropsModelAndEffortFlags() {
        var capturedArguments: [String] = []
        var capturedWorkingDirectory: URL?
        var launchHook: (() -> Void)?

        let fakeHandle = FakeProcessHandle()
        let runner = OpenCodeProcessRunner(
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
            effort: .low,
            onEvent: { _ in },
            onRawLine: { rawLines.append($0) },
            onExit: { _ in }
        )

        #expect(returnedHandle as AnyObject === fakeHandle)
        #expect(capturedWorkingDirectory?.path == "/tmp/project")
        #expect(capturedArguments == [
            "opencode", "run",
            "--format", "json",
            "--dangerously-skip-permissions",
            "/ralph /tmp/project/.aw-cache/session"
        ])
        #expect(capturedArguments.contains("--model") == false)
        #expect(capturedArguments.contains("--effort") == false)
        #expect(capturedArguments.contains("low") == false)

        launchHook?()
        #expect(rawLines == ["[effort] low"])
    }
}
