import AppKit
import SwiftUI

/// Emblème de TidyMyMac : un balai qui balaie, et deux étincelles, dessinés à la main
/// (les SF Symbols d'Apple ne peuvent pas servir d'icône d'app ni de logo).
struct BrandGlyph: View {
    var color: Color

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            ZStack {
                Broom()
                    .fill(color)
                    .frame(width: side * 0.86, height: side * 0.86)
                    .rotationEffect(.degrees(34))
                    .position(x: side * 0.54, y: side * 0.50)
                Sparkle()
                    .fill(color)
                    .frame(width: side * 0.28, height: side * 0.28)
                    .position(x: side * 0.22, y: side * 0.24)
                Sparkle()
                    .fill(color)
                    .frame(width: side * 0.14, height: side * 0.14)
                    .position(x: side * 0.86, y: side * 0.80)
            }
            .frame(width: side, height: side)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Balai droit dans son cadre : manche, bague et paille évasée.
struct Broom: Shape {
    func path(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * width, y: rect.minY + y * height)
        }
        var path = Path()
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 0.465 * width, y: rect.minY + 0.04 * height, width: 0.07 * width, height: 0.50 * height),
            cornerSize: CGSize(width: 0.035 * width, height: 0.035 * width)
        )
        path.addRoundedRect(
            in: CGRect(x: rect.minX + 0.38 * width, y: rect.minY + 0.52 * height, width: 0.24 * width, height: 0.09 * height),
            cornerSize: CGSize(width: 0.03 * width, height: 0.03 * width)
        )
        path.move(to: point(0.39, 0.64))
        path.addLine(to: point(0.61, 0.64))
        path.addLine(to: point(0.75, 0.93))
        path.addQuadCurve(to: point(0.25, 0.93), control: point(0.50, 0.99))
        path.closeSubpath()
        return path
    }
}

/// Étoile à quatre branches incurvées.
struct Sparkle: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.midY), control: center)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.maxY), control: center)
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY), control: center)
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: center)
        path.closeSubpath()
        return path
    }
}

/// Icône de l'app pour le Dock et le Finder (grille macOS : carré arrondi de 824 points sur 1024).
/// Exportée par `TidyMyMac --app-icon <fichier.png>`, puis convertie en .icns par scripts/make-icon.sh.
struct AppIconArt: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.11, green: 0.33, blue: 0.31), Theme.backgroundBottom],
                    startPoint: .top, endPoint: .bottom
                ))
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .fill(RadialGradient(colors: [Theme.mint.opacity(0.30), .clear], center: .topTrailing, startRadius: 0, endRadius: 650))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 185, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.14), lineWidth: 4)
                )
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.35), radius: 24, y: 14)
            Circle()
                .fill(LinearGradient(colors: [Theme.mint, Theme.mint.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                        .padding(26)
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 5))
                .frame(width: 540, height: 540)
                .shadow(color: Theme.mint.opacity(0.45), radius: 60)
            BrandGlyph(color: Theme.backgroundBottom)
                .frame(width: 360, height: 360)
        }
        .frame(width: 1024, height: 1024)
    }
}

enum MenuBarIcon {
    /// Emblème en image « modèle » : macOS l'adapte au thème clair ou sombre de la barre des menus.
    @MainActor
    static let image: NSImage = {
        let renderer = ImageRenderer(content: BrandGlyph(color: .black).frame(width: 18, height: 18))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }()
}
