import SwiftUI

// MARK: - Color + Hex

extension Color {
    /// Initialize a Color from a hex string like "#RRGGBB" or "RRGGBB".
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard let int = UInt32(hex, radix: 16) else {
            self.init(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
            return
        }
        let r = Double((int >> 16) & 0xFF) / 255.0
        let g = Double((int >> 8) & 0xFF) / 255.0
        let b = Double(int & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Renders an SF Symbol with hierarchical symbol rendering mode and a
/// caller-supplied colour. Used by inspector rows, phase section labels,
/// and the inspector status strip to keep the icon style consistent.
struct StatusSymbolImage: View {
    let symbolName: String
    let color: Color

    var body: some View {
        Image(systemName: symbolName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
    }
}
