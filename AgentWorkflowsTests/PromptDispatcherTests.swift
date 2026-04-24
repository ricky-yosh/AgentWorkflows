import Testing
import Foundation
@testable import AgentWorkflows

@Suite("PromptDispatcher")
struct PromptDispatcherTests {

    // MARK: - Fakes

    final class FakeWatcher: SignalWatcher {
        var onFired: (() -> Void)?
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var lastWatchedPath: String?

        func startWatching(signalFilePath: String) {
            startCount += 1
            lastWatchedPath = signalFilePath
        }

        func stopWatching() {
            stopCount += 1
        }

        func fire() { onFired?() }
    }

    // MARK: - dispatch

    @Test func dispatchRecordsLastPrompt() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")

        #expect(dispatcher.lastPrompt == "hello\n")
    }

    @Test func dispatchInjectsIntoEngine() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")

        #expect(engine.injectedPrompts == ["hello\n"])
    }

    @Test func dispatchStartsWatcher() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")

        #expect(watcher.startCount == 1)
        #expect(watcher.lastWatchedPath == "/tmp/sig")
    }

    @Test func dispatchCancelsPriorWatchBeforeStartingNew() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("first\n", to: engine, signalFilePath: "/tmp/sig")
        // After first dispatch: cancelWatcher() was called once (before startWatching), startCount == 1
        let stopAfterFirst = watcher.stopCount  // == 1
        dispatcher.dispatch("second\n", to: engine, signalFilePath: "/tmp/sig")
        // After second dispatch: cancelWatcher() called again, startCount == 2

        #expect(watcher.stopCount == stopAfterFirst + 1)
        #expect(watcher.startCount == 2)
    }

    @Test func dispatchOverwritesLastPrompt() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("first\n", to: engine, signalFilePath: "/tmp/sig")
        dispatcher.dispatch("second\n", to: engine, signalFilePath: "/tmp/sig")

        #expect(dispatcher.lastPrompt == "second\n")
    }

    // MARK: - resend

    @Test func resendReInjectsSamePrompt() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")
        dispatcher.resend()

        #expect(engine.injectedPrompts == ["hello\n", "hello\n"])
    }

    @Test func resendDoesNotChangeLastPrompt() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")
        dispatcher.resend()

        #expect(dispatcher.lastPrompt == "hello\n")
    }

    @Test func resendIsNoOpWhenNoPriorDispatch() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.resend()

        #expect(engine.injectedPrompts.isEmpty)
    }

    @Test func resendDoesNotTouchWatcher() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")
        let stopCountBefore = watcher.stopCount
        dispatcher.resend()

        #expect(watcher.stopCount == stopCountBefore)
        #expect(watcher.startCount == 1)
    }

    // MARK: - cancelWatcher

    @Test func cancelWatcherStopsWatcher() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")
        let stopCountBeforeExplicitCancel = watcher.stopCount
        dispatcher.cancelWatcher()

        #expect(watcher.stopCount == stopCountBeforeExplicitCancel + 1)
    }

    @Test func cancelWatcherIsIdempotent() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)

        dispatcher.cancelWatcher()
        dispatcher.cancelWatcher()

        #expect(watcher.stopCount == 2)
    }

    // MARK: - onSignalFired

    @Test func signalFireTriggersOnSignalFired() {
        let engine = MockAgentEngine()
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)
        var fired = false
        dispatcher.onSignalFired = { fired = true }

        dispatcher.dispatch("hello\n", to: engine, signalFilePath: "/tmp/sig")
        watcher.fire()

        #expect(fired)
    }

    @Test func signalFireWithoutDispatchDoesNotCrash() {
        let watcher = FakeWatcher()
        let dispatcher = PromptDispatcher(watcher: watcher)
        var fired = false
        dispatcher.onSignalFired = { fired = true }

        watcher.fire()

        #expect(fired)
    }
}
