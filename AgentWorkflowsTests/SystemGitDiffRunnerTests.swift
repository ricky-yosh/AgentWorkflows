import XCTest
@testable import AgentWorkflows

final class SystemGitDiffRunnerTests: XCTestCase {
    private var repoURL: URL!

    override func setUp() async throws {
        try await super.setUp()
        repoURL = try makeRepoWithMainBranch()
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: repoURL)
        try await super.tearDown()
    }

    // MARK: - Happy path (main branch)

    func test_fullSession_mainBranch_surfacesDivergentCommits() throws {
        let result = SystemGitDiffRunner().run(scope: .fullSession, workingDirectory: repoURL)
        switch result {
        case .success(let output):
            XCTAssertFalse(output.isEmpty, "Expected non-empty diff output for divergent branch")
            XCTAssertTrue(output.contains("diff --git"), "Expected git diff header in output")
        case .failure(let error):
            XCTFail("Runner returned failure: \(error.message)")
        }
    }

    func test_lastCommit_surfacesLastCommitChanges() throws {
        let result = SystemGitDiffRunner().run(scope: .lastCommit, workingDirectory: repoURL)
        switch result {
        case .success(let output):
            XCTAssertFalse(output.isEmpty, "Expected non-empty diff for last commit")
            XCTAssertTrue(output.contains("diff --git"))
        case .failure(let error):
            XCTFail("Runner returned failure: \(error.message)")
        }
    }

    // MARK: - Repo with master instead of main

    func test_fullSession_masterOnlyBranch_surfacesDivergentCommits() throws {
        let masterRepo = try makeRepoWithMasterBranch()
        defer { try? FileManager.default.removeItem(at: masterRepo) }

        let result = SystemGitDiffRunner().run(scope: .fullSession, workingDirectory: masterRepo)
        switch result {
        case .success(let output):
            XCTAssertFalse(output.isEmpty, "Expected non-empty diff for divergent branch even when default is 'master'")
            XCTAssertTrue(output.contains("diff --git"))
        case .failure(let error):
            XCTFail("Runner returned failure for master-only repo: \(error.message)")
        }
    }

    // MARK: - Helpers

    private func makeRepoWithMainBranch() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        try shell("/usr/bin/git", args: ["init", "-b", "main"], in: tmp)
        try shell("/usr/bin/git", args: ["config", "user.email", "test@example.com"], in: tmp)
        try shell("/usr/bin/git", args: ["config", "user.name", "Test"], in: tmp)

        let file = tmp.appendingPathComponent("README.md")
        try "initial content\n".write(to: file, atomically: true, encoding: .utf8)
        try shell("/usr/bin/git", args: ["add", "README.md"], in: tmp)
        try shell("/usr/bin/git", args: ["commit", "-m", "initial commit"], in: tmp)

        try shell("/usr/bin/git", args: ["checkout", "-b", "feature"], in: tmp)
        try "initial content\nadded line\n".write(to: file, atomically: true, encoding: .utf8)
        try shell("/usr/bin/git", args: ["add", "README.md"], in: tmp)
        try shell("/usr/bin/git", args: ["commit", "-m", "add line on feature branch"], in: tmp)

        return tmp
    }

    private func makeRepoWithMasterBranch() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("aw-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

        try shell("/usr/bin/git", args: ["init", "-b", "master"], in: tmp)
        try shell("/usr/bin/git", args: ["config", "user.email", "test@example.com"], in: tmp)
        try shell("/usr/bin/git", args: ["config", "user.name", "Test"], in: tmp)

        let file = tmp.appendingPathComponent("README.md")
        try "initial content\n".write(to: file, atomically: true, encoding: .utf8)
        try shell("/usr/bin/git", args: ["add", "README.md"], in: tmp)
        try shell("/usr/bin/git", args: ["commit", "-m", "initial commit"], in: tmp)

        try shell("/usr/bin/git", args: ["checkout", "-b", "feature"], in: tmp)
        try "initial content\nadded line\n".write(to: file, atomically: true, encoding: .utf8)
        try shell("/usr/bin/git", args: ["add", "README.md"], in: tmp)
        try shell("/usr/bin/git", args: ["commit", "-m", "add line on feature branch"], in: tmp)

        return tmp
    }

    private func shell(_ executable: String, args: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        process.currentDirectoryURL = directory
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "shell", code: Int(process.terminationStatus))
        }
    }
}
