import SwiftUI

/// Wraps SessionResultCard for share preview contexts.
struct ShareCardView: View {
    let session: Session

    var body: some View {
        VStack {
            SessionResultCard(session: session, showBranding: true)
                .padding(TCSpacing.md)
        }
        .background(TCColor.background)
        .clipShape(RoundedRectangle(cornerRadius: TCRadius.lg))
    }
}
