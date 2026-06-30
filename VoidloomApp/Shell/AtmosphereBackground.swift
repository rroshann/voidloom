import SwiftUI

struct AtmosphereBackground: View {
    @Environment(\.theme) private var theme

    var body: some View {
        let glowScale: Double = theme.isDark ? 1.0 : 0.5

        ZStack {
            LinearGradient(
                colors: theme.atmosphereStops,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.92, green: 0.42, blue: 0.18).opacity(0.28 * glowScale),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 0.11, green: 0.68, blue: 0.67).opacity(0.24 * glowScale),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 700
            )

            if theme.showVignette {
                RadialGradient(
                    colors: [.clear, theme.vignetteColor.opacity(0.35)],
                    center: .center,
                    startRadius: 0,
                    endRadius: 900
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)
            }
        }
        .ignoresSafeArea()
    }
}
