import SwiftUI
import VoidloomCore

/// Full-bleed Space background: the existing gradient, a solid color, or an
/// imported image, with a dimming scrim so glassy cards stay legible. Honors
/// Reduce Transparency by leaning on the scrim.
struct SpaceBackgroundView: View {
    let background: SpaceBackground
    let dimming: Double
    let backgroundsDirectory: URL

    var body: some View {
        ZStack {
            switch background {
            case .atmosphere:
                AtmosphereBackground()
            case .solid(let hex):
                (Color(hex: hex) ?? .black).ignoresSafeArea()
            case .image(let fileName):
                imageView(fileName: fileName)
            }

            if shouldDim {
                Color.black.opacity(dimming).ignoresSafeArea()
            }
        }
    }

    private var shouldDim: Bool {
        if case .atmosphere = background { return false }   // gradient already dark
        return dimming > 0
    }

    @ViewBuilder
    private func imageView(fileName: String) -> some View {
        let url = backgroundsDirectory.appendingPathComponent(fileName)
        if let nsImage = NSImage(contentsOf: url) {
            Image(nsImage: nsImage)
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
        } else {
            AtmosphereBackground()   // graceful fallback if the file is missing
        }
    }
}

private extension Color {
    /// Parses "#RRGGBB" or "#RRGGBBAA". Returns nil on malformed input.
    init?(hex: String) {
        var s = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        if s.count == 6 { s += "FF" }
        guard s.count == 8, let value = UInt64(s, radix: 16) else { return nil }
        self = Color(
            .sRGB,
            red: Double((value >> 24) & 0xFF) / 255,
            green: Double((value >> 16) & 0xFF) / 255,
            blue: Double((value >> 8) & 0xFF) / 255,
            opacity: Double(value & 0xFF) / 255
        )
    }
}
