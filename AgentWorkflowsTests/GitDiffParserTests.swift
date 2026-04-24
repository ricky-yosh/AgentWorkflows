import XCTest
@testable import AgentWorkflows

final class GitDiffParserTests: XCTestCase {
    // Minimal unified diff with one file, one hunk
    let sampleDiff = """
    diff --git a/AgentWorkflows/Engine/WorkflowEngine.swift b/AgentWorkflows/Engine/WorkflowEngine.swift
    index abc123..def456 100644
    --- a/AgentWorkflows/Engine/WorkflowEngine.swift
    +++ b/AgentWorkflows/Engine/WorkflowEngine.swift
    @@ -45,8 +45,12 @@ func prepareDish() {
         let dish = fetchDish()
    -    scheduleDishAssignment(dish)
    +    if !dish {
    +        scheduleDishAssignment(dish)
    +    }
     }
    """

    func test_parse_one_file() {
        let result = GitDiffParser.parse(sampleDiff)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].filePath, "AgentWorkflows/Engine/WorkflowEngine.swift")
    }

    func test_parse_hunk_context_line() {
        let result = GitDiffParser.parse(sampleDiff)
        XCTAssertEqual(result[0].hunks[0].contextLine, "func prepareDish() {")
    }

    func test_parse_added_and_removed_line_counts() {
        let result = GitDiffParser.parse(sampleDiff)
        let lines = result[0].hunks[0].lines
        XCTAssertEqual(lines.filter { $0.kind == .removed }.count, 1)
        XCTAssertEqual(lines.filter { $0.kind == .added }.count, 3)
    }

    func test_parse_empty_string_returns_empty() {
        XCTAssertTrue(GitDiffParser.parse("").isEmpty)
    }

    func test_parse_two_files() {
        let twoFiles = sampleDiff + "\n" + sampleDiff.replacingOccurrences(
            of: "WorkflowEngine", with: "SessionStore")
        let result = GitDiffParser.parse(twoFiles)
        XCTAssertEqual(result.count, 2)
    }
}
