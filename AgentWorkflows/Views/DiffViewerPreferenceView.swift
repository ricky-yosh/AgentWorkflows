import SwiftUI

// MARK: - Editor Preference

struct EditorPreferenceView: View {

    @Binding var editorCommand: String
    @State private var selection: EditorOption = .xcode

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("App", selection: $selection) {
                ForEach(EditorOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: selection) { _, newValue in
                if newValue != .custom {
                    editorCommand = newValue.shellCommand
                }
            }

            if selection == .custom {
                TextField("Shell command", text: $editorCommand, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Text("Use `{path}` as the session's Working Directory placeholder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(editorCommand)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            selection = EditorOption.allCases.first { $0.shellCommand == editorCommand } ?? .custom
        }
    }
}

enum EditorOption: String, CaseIterable, Identifiable {
    case xcode
    case vscode
    case cursor
    case zed
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .xcode:   "Xcode"
        case .vscode:  "VS Code"
        case .cursor:  "Cursor"
        case .zed:     "Zed"
        case .custom:  "Custom…"
        }
    }

    var shellCommand: String {
        switch self {
        case .xcode:   "xed {path}"
        case .vscode:  #"open -a "Visual Studio Code" {path}"#
        case .cursor:  #"open -a "Cursor" {path}"#
        case .zed:     #"open -a "Zed" {path}"#
        case .custom:  ""
        }
    }
}

// MARK: - Terminal Preference

struct TerminalPreferenceView: View {

    @Binding var terminalCommand: String
    @State private var selection: TerminalOption = .terminal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("App", selection: $selection) {
                ForEach(TerminalOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: selection) { _, newValue in
                if newValue != .custom {
                    terminalCommand = newValue.shellCommand
                }
            }

            if selection == .custom {
                TextField("Shell command", text: $terminalCommand, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Text("Use `{path}` as the session's Working Directory placeholder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(terminalCommand)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            selection = TerminalOption.allCases.first { $0.shellCommand == terminalCommand } ?? .custom
        }
    }
}

enum TerminalOption: String, CaseIterable, Identifiable {
    case terminal
    case ghostty
    case iterm
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .terminal: "Terminal"
        case .ghostty:  "Ghostty"
        case .iterm:    "iTerm"
        case .custom:   "Custom…"
        }
    }

    var shellCommand: String {
        switch self {
        case .terminal: #"open -a Terminal {path}"#
        case .ghostty:  #"open -a Ghostty {path}"#
        case .iterm:    #"open -a iTerm {path}"#
        case .custom:   ""
        }
    }
}

// MARK: - Diff Viewer Preference

struct DiffViewerPreferenceView: View {

    @Binding var diffViewerCommand: String
    @State private var selection: DiffViewerOption = .sourcetree

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("App", selection: $selection) {
                ForEach(DiffViewerOption.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .onChange(of: selection) { _, newValue in
                if newValue != .custom {
                    diffViewerCommand = newValue.shellCommand
                }
            }

            if selection == .custom {
                TextField("Shell command", text: $diffViewerCommand, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)
                Text("Use `{path}` as the session's Working Directory placeholder.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(diffViewerCommand)
                    .font(.system(.callout, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear {
            selection = DiffViewerOption.allCases.first { $0.shellCommand == diffViewerCommand } ?? .custom
        }
    }
}

// MARK: - Excavation CLI Preference

struct ExcavationCLIPreference: View {

    @Binding var excavationCLI: CLIPreset

    static let sectionTitle = "Excavation CLI"
    static let detailText = "Runs ExcavationAgent in a dedicated terminal after symbol extraction."

    var body: some View {
        Section(Self.sectionTitle) {
            cliPresetRow("Target", binding: $excavationCLI)
            Text(Self.detailText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cliPresetRow(_ label: String, binding: Binding<CLIPreset>) -> some View {
        LabeledContent(label) {
            Menu {
                Button("claude") { binding.wrappedValue = .claude }
                Divider()
                Button("codex") { binding.wrappedValue = .codex }
                Button("pi") { binding.wrappedValue = .pi }
                Button("openCode") { binding.wrappedValue = .openCode }
            } label: {
                Text(binding.wrappedValue.rawValue.capitalized)
            }
            .fixedSize()
        }
    }
}

// MARK: - Excavation CLI Preference

struct ExcavationCLIPreference: View {

    @Binding var excavationCLI: CLIPreset

    static let sectionTitle = "Excavation CLI"
    static let detailText = "Runs ExcavationAgent in a dedicated terminal after symbol extraction."

    var body: some View {
        Section(Self.sectionTitle) {
            cliPresetRow("Target", binding: $excavationCLI)
            Text(Self.detailText)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func cliPresetRow(_ label: String, binding: Binding<CLIPreset>) -> some View {
        LabeledContent(label) {
            Menu {
                Button("claude") { binding.wrappedValue = .claude }
                Divider()
                Button("codex") { binding.wrappedValue = .codex }
                Button("pi") { binding.wrappedValue = .pi }
                Button("openCode") { binding.wrappedValue = .openCode }
            } label: {
                Text(binding.wrappedValue.rawValue.capitalized)
            }
            .fixedSize()
        }
    }
}

enum DiffViewerOption: String, CaseIterable, Identifiable {
    case sourcetree
    case tower
    case fork
    case custom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sourcetree: "Sourcetree"
        case .tower: "Tower"
        case .fork: "Fork"
        case .custom: "Custom…"
        }
    }

    var shellCommand: String {
        switch self {
        case .sourcetree: #"open -a "Sourcetree" {path}"#
        case .tower:      #"open -a "Tower" {path}"#
        case .fork:       #"open -a "Fork" {path}"#
        case .custom:     ""
        }
    }
}
