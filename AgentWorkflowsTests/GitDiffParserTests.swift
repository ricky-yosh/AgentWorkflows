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

    func test_context_lines_have_both_line_numbers() {
        let result = GitDiffParser.parse(sampleDiff)
        let contextLines = result[0].hunks[0].lines.filter { $0.kind == .context }
        XCTAssertFalse(contextLines.isEmpty)
        for line in contextLines {
            XCTAssertNotNil(line.oldLineNumber)
            XCTAssertNotNil(line.newLineNumber)
        }
    }

    func test_added_lines_have_only_new_line_number() {
        let result = GitDiffParser.parse(sampleDiff)
        let addedLines = result[0].hunks[0].lines.filter { $0.kind == .added }
        XCTAssertFalse(addedLines.isEmpty)
        for line in addedLines {
            XCTAssertNil(line.oldLineNumber)
            XCTAssertNotNil(line.newLineNumber)
        }
    }

    func test_removed_lines_have_only_old_line_number() {
        let result = GitDiffParser.parse(sampleDiff)
        let removedLines = result[0].hunks[0].lines.filter { $0.kind == .removed }
        XCTAssertFalse(removedLines.isEmpty)
        for line in removedLines {
            XCTAssertNotNil(line.oldLineNumber)
            XCTAssertNil(line.newLineNumber)
        }
    }

    func test_line_numbers_start_from_hunk_header() {
        // Hunk header: @@ -45,8 +45,12 @@
        // First context line "    let dish = fetchDish()" should be line 45 old, 45 new
        let result = GitDiffParser.parse(sampleDiff)
        let firstContext = result[0].hunks[0].lines.first { $0.kind == .context }
        XCTAssertEqual(firstContext?.oldLineNumber, 45)
        XCTAssertEqual(firstContext?.newLineNumber, 45)
    }

    func test_line_numbers_increment_correctly() {
        // A simpler diff to test number tracking precisely
        let diff = """
        diff --git a/test.swift b/test.swift
        @@ -10,3 +10,4 @@
         keep
        -removed
         keep2
        +added
         keep3
        """
        let result = GitDiffParser.parse(diff)
        let lines = result[0].hunks[0].lines
        // context "keep" -> old:10, new:10
        XCTAssertEqual(lines[0].oldLineNumber, 10)
        XCTAssertEqual(lines[0].newLineNumber, 10)
        // removed "removed" -> old:11, new:nil
        XCTAssertEqual(lines[1].oldLineNumber, 11)
        XCTAssertNil(lines[1].newLineNumber)
        // context "keep2" -> old:12, new:11
        XCTAssertEqual(lines[2].oldLineNumber, 12)
        XCTAssertEqual(lines[2].newLineNumber, 11)
        // added "added" -> old:nil, new:12
        XCTAssertNil(lines[3].oldLineNumber)
        XCTAssertEqual(lines[3].newLineNumber, 12)
        // context "keep3" -> old:13, new:13
        XCTAssertEqual(lines[4].oldLineNumber, 13)
        XCTAssertEqual(lines[4].newLineNumber, 13)
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
