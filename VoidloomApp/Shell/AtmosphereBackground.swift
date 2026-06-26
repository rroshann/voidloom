import SwiftUI

struct AtmosphereBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.05, blue: 0.07),
                    Color(red: 0.08, green: 0.08, blue: 0.11),
                    Color(red: 0.02, green: 0.09, blue: 0.11)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color(red: 0.92, green: 0.42, blue: 0.18).opacity(0.28),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 620
            )

            RadialGradient(
                colors: [
                    Color(red: 0.11, green: 0.68, blue: 0.67).opacity(0.24),
                    .clear
                ],
                center: .bottomLeading,
                startRadius: 20,
                endRadius: 700
            )
        }
        .ignoresSafeArea()
    }
}
