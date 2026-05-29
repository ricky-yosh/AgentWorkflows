import SwiftUI

struct TerminalDivider: View {
    let state: TerminalDividerState
    let windowWidth: CGFloat

    @State private var isHovered = false
    @State private var dragStartWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(isHovered ? Color.accentColor : Color(nsColor: .separatorColor))
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay(alignment: .center) {
                collapseButton
                    .opacity(isHovered ? 1 : 0)
            }
            .onHover { isHovered = $0 }
            .gesture(dragGesture)
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    state.toggle()
                }
            }
            .frame(width: 12)
            .background(Color.clear)
            .contentShape(Rectangle())
            .onAppear {
                state.clampWidth(to: windowWidth)
            }
            .onChange(of: windowWidth) { _, newWidth in
                state.clampWidth(to: newWidth)
            }
    }

    @ViewBuilder
    private var collapseButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                state.toggle()
            }
        } label: {
            Image(systemName: state.collapsed ? "chevron.right" : "chevron.left")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 12, height: 24)
        }
        .buttonStyle(.plain)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                if dragStartWidth == 0 {
                    dragStartWidth = state.collapsed ? state.previousWidth : state.width
                }
                let target = dragStartWidth + value.translation.width
                state.setWidth(target, windowWidth: windowWidth)
            }
            .onEnded { _ in
                dragStartWidth = 0
            }
    }
}
