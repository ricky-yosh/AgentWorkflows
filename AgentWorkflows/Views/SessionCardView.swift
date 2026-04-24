import SwiftUI

struct SessionCardView: View {
    let session: Session
    @Environment(EngineManager.self) private var engineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(session.name)
                .font(.body)
                .lineLimit(1)
            SessionCardStatus(
                status: engineManager.runStatus(for: session.id),
                session: session,
                workflow: .ralph
            )
        }
    }
}
