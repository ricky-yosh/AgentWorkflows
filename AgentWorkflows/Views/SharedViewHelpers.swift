import SwiftUI

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
