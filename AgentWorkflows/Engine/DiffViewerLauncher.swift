import Foundation
import AppKit

/// Launches the user-configured diff viewer, editor, or terminal for a given working directory.
/// The command template is a shell command with an optional `{path}` placeholder.
/// Custom templates may also use URL schemes — those are handed to NSWorkspace directly.
/// Failures are silently swallowed — no crash on misconfiguration.
enum DiffViewerLauncher {

    static let defaultCommand = #"open -a "Sourcetree" {path}"#

    static func launch(commandTemplate: String, workingDirectory: String) {
        let template = commandTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        let effectiveTemplate = template.isEmpty ? defaultCommand : template

        // If the template is a custom URL scheme, percent-encode the path and
        // hand it to NSWorkspace. Built-in presets all use shell commands instead.
        let probe = effectiveTemplate.replacingOccurrences(of: "{path}", with: "probe")
        if let url = URL(string: probe), let scheme = url.scheme,
           !scheme.isEmpty, scheme != "file", scheme != "http", scheme != "https" {
            var encoded = workingDirectory
                .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? workingDirectory
            // Avoid double-slash when template ends with "/" before "{path}"
            if let phRange = effectiveTemplate.range(of: "{path}"),
               phRange.lowerBound > effectiveTemplate.startIndex {
                let preceding = effectiveTemplate[effectiveTemplate.index(before: phRange.lowerBound)]
                if preceding == "/" && encoded.hasPrefix("/") {
                    encoded = String(encoded.dropFirst())
                }
            }
            let expanded = effectiveTemplate.replacingOccurrences(of: "{path}", with: encoded)
            if let finalURL = URL(string: expanded) {
                NSWorkspace.shared.open(finalURL)
                return
            }
        }

        // Shell command path.
        let quotedPath = shellQuote(workingDirectory)
        let command = effectiveTemplate.contains("{path}")
            ? effectiveTemplate.replacingOccurrences(of: "{path}", with: quotedPath)
            : "\(effectiveTemplate) \(quotedPath)"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        do {
            try process.run()
        } catch {
            NSLog("DiffViewerLauncher: launch failed: \(error)")
        }
    }

    private static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
