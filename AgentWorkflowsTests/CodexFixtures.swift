// Real JSONL lines captured from `codex exec --json` against a trivial prompt.
// These constants make CodexEventDecoderTests runnable without a live codex binary.
enum CodexFixtures {

    // MARK: - Thread / Turn lifecycle

    static let threadStarted = #"{"type":"thread.started","thread_id":"019db813-020c-7613-b8e6-1cf640f5365b"}"#

    static let turnStarted = #"{"type":"turn.started"}"#

    static let turnCompleted = #"{"type":"turn.completed","usage":{"input_tokens":54639,"cached_input_tokens":50944,"output_tokens":211}}"#

    // MARK: - Agent message

    static let agentMessageCompleted = #"{"type":"item.completed","item":{"id":"item_0","type":"agent_message","text":"I'm executing the three requested shell actions in order, then I'll confirm completion."}}"#

    // MARK: - Command execution (success path)

    static let commandStarted = #"{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'echo hello'","aggregated_output":"","exit_code":null,"status":"in_progress"}}"#

    static let commandCompletedSuccess = #"{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/zsh -lc 'echo hello'","aggregated_output":"hello\n","exit_code":0,"status":"completed"}}"#

    // MARK: - Command execution (failure path)

    static let commandCompletedFailure = #"{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"/bin/zsh -lc false","aggregated_output":"","exit_code":1,"status":"failed"}}"#

    // MARK: - File change

    static let fileChangeStarted = #"{"type":"item.started","item":{"id":"item_1","type":"file_change","changes":[{"path":"/tmp/codex_filechange_demo.txt","kind":"add"}],"status":"in_progress"}}"#

    static let fileChangeCompleted = #"{"type":"item.completed","item":{"id":"item_1","type":"file_change","changes":[{"path":"/tmp/codex_filechange_demo.txt","kind":"add"}],"status":"completed"}}"#
}
