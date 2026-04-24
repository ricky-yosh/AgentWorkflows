import Foundation

enum Reachability: Equatable {
    case reachable
    case missing
}

/// Classifies a SessionRegistryEntry as reachable or missing by probing
/// whether its workingDirectory exists on disk as a directory.
nonisolated struct SessionReachability {

    /// Returns true when the given path exists and is a directory.
    let isDirectory: (String) -> Bool

    static let live = SessionReachability { path in
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
        return exists && isDir.boolValue
    }

    init(isDirectory: @escaping (String) -> Bool) {
        self.isDirectory = isDirectory
    }

    func classify(entry: SessionRegistryEntry) -> Reachability {
        isDirectory(entry.workingDirectory) ? .reachable : .missing
    }
}
