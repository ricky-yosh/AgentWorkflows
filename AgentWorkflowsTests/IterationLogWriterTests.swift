import Testing
import Foundation
@testable import AgentWorkflows

@Suite("IterationLogWriter")
struct IterationLogWriterTests {

    private func makeProgressDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "IterationLogWriterTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test func subdirectoryCreatedOnOpen() throws {
        let progressDir = try makeProgressDir()
        let writer = IterationLogWriter(progressDirectory: progressDir)
        try writer.open(iteration: 1)
        writer.close()
        let logsDir = progressDir.appending(path: "ralph-logs")
        #expect(FileManager.default.fileExists(atPath: logsDir.path))
    }

    @Test func subdirectoryCreationIsIdempotent() throws {
        let progressDir = try makeProgressDir()
        let writer = IterationLogWriter(progressDirectory: progressDir)
        try writer.open(iteration: 1)
        writer.close()
        // Second open must not throw even though ralph-logs/ already exists.
        try writer.open(iteration: 2)
        writer.close()
    }

    @Test func linesWrittenToCorrectIterationFiles() throws {
        let progressDir = try makeProgressDir()
        let writer = IterationLogWriter(progressDirectory: progressDir)

        try writer.open(iteration: 1)
        writer.append("line-a")
        writer.append("line-b")
        writer.close()

        try writer.open(iteration: 2)
        writer.append("line-c")
        writer.close()

        let logsDir = progressDir.appending(path: "ralph-logs")
        let iter1 = try String(contentsOf: logsDir.appending(path: "iter-1.log"), encoding: .utf8)
        let iter2 = try String(contentsOf: logsDir.appending(path: "iter-2.log"), encoding: .utf8)

        #expect(iter1 == "line-a\nline-b\n")
        #expect(iter2 == "line-c\n")
    }

    @Test func eachOpenTruncatesPriorContent() throws {
        let progressDir = try makeProgressDir()
        let writer = IterationLogWriter(progressDirectory: progressDir)

        try writer.open(iteration: 1)
        writer.append("first-run")
        writer.close()

        try writer.open(iteration: 1)
        writer.append("second-run")
        writer.close()

        let logURL = progressDir.appending(path: "ralph-logs/iter-1.log")
        let content = try String(contentsOf: logURL, encoding: .utf8)
        #expect(content == "second-run\n")
    }
}
