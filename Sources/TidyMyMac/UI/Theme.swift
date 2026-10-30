import SwiftUI

/// Palette propre à TidyMyMac : fond vert d'eau profond, accent menthe, une couleur par module.
enum Theme {
    static let backgroundTop = Color(red: 0.07, green: 0.22, blue: 0.21)
    static let backgroundBottom = Color(red: 0.03, green: 0.09, blue: 0.12)
    static let mint = Color(red: 0.40, green: 0.91, blue: 0.73)
    static let aqua = Color(red: 0.33, green: 0.82, blue: 0.95)
    static let sky = Color(red: 0.47, green: 0.68, blue: 1.00)
    static let lavender = Color(red: 0.70, green: 0.64, blue: 1.00)
    static let rose = Color(red: 1.00, green: 0.56, blue: 0.72)
    static let lime = Color(red: 0.72, green: 0.94, blue: 0.40)
    static let peach = Color(red: 1.00, green: 0.68, blue: 0.52)
    static let amber = Color(red: 1.00, green: 0.75, blue: 0.32)
    static let coral = Color(red: 1.00, green: 0.45, blue: 0.42)
    static let card = Color.white.opacity(0.06)
    static let cardBorder = Color.white.opacity(0.09)

    static func level(_ fraction: Double) -> Color {
        fraction < 0.7 ? mint : fraction < 0.9 ? amber : coral
    }
}

/// Bouton principal : capsule colorée, texte sombre.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.mint
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        PrimaryButtonBody(configuration: configuration, tint: tint, compact: compact)
    }
}

private struct PrimaryButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let tint: Color
    let compact: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .font(.system(compact ? .caption : .body, design: .rounded).bold())
            .foregroundColor(Theme.backgroundBottom)
            .padding(.horizontal, compact ? 12 : 18)
            .padding(.vertical, compact ? 5 : 8)
            .background(Capsule().fill(tint.opacity(configuration.isPressed ? 0.75 : 1)))
            .opacity(isEnabled ? 1 : 0.4)
    }
}

/// Bouton secondaire : capsule translucide.
struct SecondaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(.body, design: .rounded).weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.16 : 0.08)))
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.18)))
    }
}

struct IconTile: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 34

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundColor(tint)
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(tint.opacity(0.16)))
            .overlay(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).strokeBorder(tint.opacity(0.25)))
    }
}

/// Logo de TidyMyMac : pastille menthe et souffle de vent.
struct BrandMark: View {
    var size: CGFloat = 42

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [Theme.mint, Theme.mint.opacity(0.45)], startPoint: .top, endPoint: .bottom))
            BrandGlyph(color: Theme.backgroundBottom)
                .frame(width: size * 0.66, height: size * 0.66)
        }
        .frame(width: size, height: size)
    }
}
