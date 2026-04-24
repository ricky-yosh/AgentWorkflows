import Testing
import Foundation
@testable import AgentWorkflows

@Suite("StateFileWatcher")
struct StateFileWatcherTests {

    private func makeTempDir() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory
            .appending(path: "StateFileWatcherTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        return tmp
    }

    @Test func callbackFiresOnWrite() throws {
        let dir = try makeTempDir()
        let stateFile = dir.appending(path: "state.json")
        try Data("{}".utf8).write(to: stateFile)

        let watcher = DispatchSourceStateFileWatcher()
        let sem = DispatchSemaphore(value: 0)
        watcher.onChange = { sem.signal() }
        watcher.start(watching: stateFile)

        try Data("{\"v\":2}".utf8).write(to: stateFile)

        let fired = sem.wait(timeout: .now() + 3)
        #expect(fired == .success)
        watcher.stop()
    }

    @Test func callbackFiresOnMultipleWrites() throws {
        let dir = try makeTempDir()
        let stateFile = dir.appending(path: "state.json")
        try Data("{}".utf8).write(to: stateFile)

        let watcher = DispatchSourceStateFileWatcher()
        var count = 0
        let sem = DispatchSemaphore(value: 0)
        watcher.onChange = {
            count += 1
            if count >= 2 { sem.signal() }
        }
        watcher.start(watching: stateFile)

        try Data("{\"v\":1}".utf8).write(to: stateFile)
        try Data("{\"v\":2}".utf8).write(to: stateFile)

        let fired = sem.wait(timeout: .now() + 3)
        #expect(fired == .success)
        #expect(count >= 2)
        watcher.stop()
    }

    @Test func stopPreventsCallback() throws {
        let dir = try makeTempDir()
        let stateFile = dir.appending(path: "state.json")
        try Data("{}".utf8).write(to: stateFile)

        let watcher = DispatchSourceStateFileWatcher()
        var callbackFired = false
        watcher.onChange = { callbackFired = true }
        watcher.start(watching: stateFile)
        watcher.stop()

        try Data("{\"v\":2}".utf8).write(to: stateFile)
        Thread.sleep(forTimeInterval: 0.5)
        #expect(!callbackFired)
    }
}
