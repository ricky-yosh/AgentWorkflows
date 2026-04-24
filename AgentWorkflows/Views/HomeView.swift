import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var sessionStore
    @Environment(WindowManager.self) private var windowManager
    @Binding var selection: SidebarItem?
    @Binding var showingNewSession: Bool

    private var recentSessionsWithMtime: [(session: Session, mtime: Date)] {
        sessionStore.sessions
            .map { session -> (Session, Date) in
                let dir = URL(fileURLWithPath: session.workingDirectory)
                let sessionDir = SessionDirectoryLayout.sessionDirectory(workingDirectory: dir, sessionID: session.id)
                let mtime = (try? sessionDir.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return (session, mtime)
            }
            .sorted { $0.1 > $1.1 }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                quickstartCTA
                if !recentSessionsWithMtime.isEmpty {
                    recentSessionsGrid
                }
            }
            .padding(24)
        }
    }

    private var quickstartCTA: some View {
        VStack(spacing: 12) {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Welcome to AW")
                .font(.title2)
                .fontWeight(.semibold)
            Text("Create a session to start orchestrating agentic workflows.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Cmd+T / Cmd+N are owned by the File menu's New Session command.
            // Attaching .keyboardShortcut here would shadow the menu command.
            Button {
                showingNewSession = true
            } label: {
                Label("New Session", systemImage: "plus.circle.fill")
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
            }
            .controlSize(.large)

            Text("or press \(Image(systemName: "command")) T")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var recentSessionsGrid: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Recent Sessions")
                .font(.headline)
                .padding(.horizontal, 4)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200))], spacing: 12) {
                ForEach(recentSessionsWithMtime, id: \.session.id) { item in
                    RecentSessionCard(session: item.session, mtime: item.mtime) {
                        if !windowManager.focusWindow(for: item.session.id) {
                            selection = .session(item.session.id)
                        }
                    }
                }
            }
        }
    }
}

private struct RecentSessionCard: View {
    let session: Session
    let mtime: Date
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(session.name)
                        .font(.body)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    StatusBadgeView(sessionState: session.state)
                }
                Text((session.workingDirectory as NSString).abbreviatingWithTildeInPath)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(mtime, format: .relative(presentation: .named))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
