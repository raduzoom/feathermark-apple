import SwiftUI

/// The soft peach window with blurred mint and peach glows that the glass panels sit on.
struct GlassBackground: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Theme.windowBackground
                Circle()
                    .fill(Theme.glowMint)
                    .frame(width: proxy.size.width * 1.1)
                    .offset(x: -proxy.size.width * 0.35, y: -proxy.size.height * 0.35)
                    .blur(radius: 80)
                Circle()
                    .fill(Theme.glowPeach)
                    .frame(width: proxy.size.width * 0.9)
                    .offset(x: proxy.size.width * 0.4, y: proxy.size.height * 0.1)
                    .blur(radius: 90)
            }
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}
