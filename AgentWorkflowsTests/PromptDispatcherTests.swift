import Testing
import Foundation
@testable import AgentWorkflows

@Suite("PromptDispatcher")
struct PromptDispatcherTests {

    // MARK: - dispatch

    @Test func dispatchRecordsLastPrompt() {
        let engine = MockAgentEngine()
        let dispatcher = PromptDispatcher()

        dispatcher.dispatch("hello\n", to: engine)

        #expect(dispatcher.lastPrompt == "hello\n")
    }

    @Test func dispatchInjectsIntoEngine() {
        let engine = MockAgentEngine()
        let dispatcher = PromptDispatcher()

        dispatcher.dispatch("hello\n", to: engine)

        #expect(engine.injectedPrompts == ["hello\n"])
    }

    @Test func dispatchOverwritesLastPrompt() {
        let engine = MockAgentEngine()
        let dispatcher = PromptDispatcher()

        dispatcher.dispatch("first\n", to: engine)
        dispatcher.dispatch("second\n", to: engine)

        #expect(dispatcher.lastPrompt == "second\n")
    }

    // MARK: - resend

    @Test func resendReInjectsSamePrompt() {
        let engine = MockAgentEngine()
        let dispatcher = PromptDispatcher()

        dispatcher.dispatch("hello\n", to: engine)
        dispatcher.resend()

        #expect(engine.injectedPrompts == ["hello\n", "hello\n"])
    }

    @Test func resendDoesNotChangeLastPrompt() {
        let engine = MockAgentEngine()
        let dispatcher = PromptDispatcher()

        dispatcher.dispatch("hello\n", to: engine)
        dispatcher.resend()

        #expect(dispatcher.lastPrompt == "hello\n")
    }

    @Test func resendIsNoOpWhenNoPriorDispatch() {
        let engine = MockAgentEngine()
        let dispatcher = PromptDispatcher()

        dispatcher.resend()

        #expect(engine.injectedPrompts.isEmpty)
    }

    // MARK: - cancelWatcher

    @Test func cancelWatcherIsNoOp() {
        let dispatcher = PromptDispatcher()
        dispatcher.cancelWatcher()
        dispatcher.cancelWatcher()
        // No crash — cancelWatcher is a no-op after signal-file removal
    }
}
