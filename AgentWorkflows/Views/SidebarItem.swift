import Foundation

enum SidebarItem: Hashable {
    case home
    case session(UUID)
}

extension SidebarItem: RawRepresentable {
    typealias RawValue = String

    init?(rawValue: String) {
        if rawValue == "home" {
            self = .home
        } else if rawValue.hasPrefix("session:"),
                  let uuid = UUID(uuidString: String(rawValue.dropFirst("session:".count))) {
            self = .session(uuid)
        } else {
            return nil
        }
    }

    var rawValue: String {
        switch self {
        case .home: return "home"
        case .session(let id): return "session:\(id.uuidString)"
        }
    }
}
