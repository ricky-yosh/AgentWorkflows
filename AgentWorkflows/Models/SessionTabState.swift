import SwiftUI

enum SessionTab: Hashable {
    case workbench, terminal, iterations, files, diff, log
}

@Observable
final class SessionTabState {
    private var tabs: [UUID: SessionTab] = [:]

    func selectedTab(for sessionID: UUID) -> SessionTab {
        tabs[sessionID] ?? .terminal
    }

    func setSelectedTab(_ tab: SessionTab, for sessionID: UUID) {
        tabs[sessionID] = tab
    }
}
