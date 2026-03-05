import SwiftUI

/// Generates a shareable UIImage from a session's result card.
@MainActor
struct ShareCardGenerator {
    /// Render the session result card to a UIImage at 3x scale.
    static func generateImage(for session: Session) -> UIImage? {
        let view = SessionResultCard(session: session, showBranding: true)
            .padding(24)
            .background(TCColor.background)
            .frame(width: 360)
            .preferredColorScheme(.dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
