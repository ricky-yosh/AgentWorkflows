import Foundation
import SwiftUI
import AppKit

struct WorkbenchView: View {
    let session: Session
    let canvasFileStore: CanvasFileStore
    let canvasLayoutStore: CanvasLayoutStore
    let isExcavationRunning: Bool
    let onRunExcavate: () -> Void

    @State private var isExcavationDrawerPresented = true

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                PatternPaletteView()
                    .frame(width: 276)

                Divider()

                WorkbenchCanvasView(
                    session: session,
                    canvasFileStore: canvasFileStore,
                    canvasLayoutStore: canvasLayoutStore,
                    isDrawerPresented: isExcavationDrawerPresented,
                    isExcavationRunning: isExcavationRunning,
                    onRunExcavate: onRunExcavate
                )
            }

            Divider()

            ExcavationChatView(
                session: session,
                isPresented: $isExcavationDrawerPresented
            )
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct WorkbenchNoticeCard: View {
    let notice: WorkbenchNotice

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: notice.symbolName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(notice.tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title)
                    .font(.callout.weight(.semibold))
                Text(notice.message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(notice.tint.opacity(0.25), lineWidth: 1)
        )
    }
}

enum WorkbenchNotice: Identifiable, Equatable {
    case warning(String)
    case emptyExcavation

    var id: String {
        switch self {
        case .warning(let message):
            return "warning:\(message)"
        case .emptyExcavation:
            return "empty-excavation"
        }
    }

    var title: String {
        switch self {
        case .warning:
            return "Canvas Warning"
        case .emptyExcavation:
            return "Empty Excavation"
        }
    }

    var message: String {
        switch self {
        case .warning(let message):
            return message
        case .emptyExcavation:
            return "Excavation found no relevant components. Try describing the feature in more detail, or ask a question in the excavation terminal below."
        }
    }

    var symbolName: String {
        switch self {
        case .warning:
            return "exclamationmark.triangle.fill"
        case .emptyExcavation:
            return "sparkles"
        }
    }

    var tint: Color {
        switch self {
        case .warning:
            return .orange
        case .emptyExcavation:
            return .secondary
        }
    }
}

enum WorkbenchNoticeResolver {
    static func notices(for model: WorkbenchModel, warningPayload: String?) -> [WorkbenchNotice] {
        var notices: [WorkbenchNotice] = []

        if let warningPayload, !warningPayload.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            notices.append(.warning(warningPayload))
        }

        if model.outskirts.isEmpty {
            notices.append(.emptyExcavation)
        }

        return notices
    }
}
