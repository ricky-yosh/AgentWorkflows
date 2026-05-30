import Foundation

struct FileDiff: Equatable {
    let filePath: String
    let hunks: [DiffHunk]
}

struct DiffHunk: Equatable {
    let contextLine: String
    let lines: [DiffLine]
}

struct DiffLine: Equatable {
    enum Kind { case added, removed, context }
    let kind: Kind
    let text: String
    let oldLineNumber: Int?
    let newLineNumber: Int?
}
