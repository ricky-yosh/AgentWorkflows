import Foundation

struct CLIToolDefinition: Codable, Equatable, Identifiable {
    var id: String { name }
    var name: String
    var command: String
    var defaultArgs: [String]?

    enum CodingKeys: String, CodingKey {
        case name, command
        case defaultArgs = "default_args"
    }
}
