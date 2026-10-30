import SwiftUI

/// Fond de la fenêtre : dégradé vert d'eau et halo teinté par le module courant.
struct AppBackground: View {
    let accent: Color

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [accent.opacity(0.22), .clear], center: .topTrailing, startRadius: 40, endRadius: 700)
            RadialGradient(colors: [accent.opacity(0.10), .clear], center: .bottomLeading, startRadius: 20, endRadius: 500)
        }
        .animation(.easeInOut(duration: 0.5), value: accent)
    }
}

/// Illustration d'accueil : un globe lumineux, des orbites et des satellites qui tournent lentement.
struct HeroIllustration: View {
    let symbol: String
    let tint: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [tint.opacity(0.32), .clear], center: .center, startRadius: 10, endRadius: 190))
                .frame(width: 380, height: 380)
            ForEach(0..<3) { ring in
                Circle()
                    .strokeBorder(tint.opacity(0.20 - Double(ring) * 0.05), style: StrokeStyle(lineWidth: 1, dash: ring == 1 ? [4, 6] : []))
                    .frame(width: 210 + CGFloat(ring) * 64, height: 210 + CGFloat(ring) * 64)
            }
            TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                let turn = context.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 60) / 60 * 360
                ZStack {
                    Circle().fill(tint).frame(width: 11, height: 11).offset(x: 137)
                    Circle().fill(Color.white.opacity(0.8)).frame(width: 6, height: 6).offset(y: -169)
                }
                .rotationEffect(.degrees(turn))
                .overlay(
                    Circle().fill(tint.opacity(0.6)).frame(width: 8, height: 8).offset(x: -105)
                        .rotationEffect(.degrees(-turn * 1.6))
                )
            }
            Circle()
                .fill(LinearGradient(colors: [tint, tint.opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(
                    Circle()
                        .fill(LinearGradient(colors: [Color.white.opacity(0.45), .clear], startPoint: .top, endPoint: .center))
                        .padding(12)
                )
                .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1.5))
                .frame(width: 170, height: 170)
                .shadow(color: tint.opacity(0.55), radius: 40)
            Image(systemName: symbol)
                .font(.system(size: 66, weight: .semibold))
                .foregroundColor(Theme.backgroundBottom.opacity(0.85))
        }
        .frame(width: 380, height: 380)
    }
}

/// Gros bouton rond en bas des pages d'accueil.
struct ScanButton: View {
    let title: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundColor(Theme.backgroundBottom)
                .frame(width: 108, height: 108)
                .background(Circle().fill(LinearGradient(colors: [tint, tint.opacity(0.7)], startPoint: .top, endPoint: .bottom)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.45), lineWidth: 1))
                .overlay(Circle().strokeBorder(tint.opacity(0.35), lineWidth: 8).padding(-10))
                .shadow(color: tint.opacity(0.6), radius: 26)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
    }
}

/// Page d'accueil d'un module : illustration, titre, points clés et bouton d'action.
struct ModuleIntro<Accessory: View>: View {
    let module: Module
    let action: () -> Void
    @ViewBuilder let accessory: Accessory

    var body: some View {
        let info = module.info
        VStack(spacing: 0) {
            HStack(spacing: 36) {
                HeroIllustration(symbol: info.heroSymbol, tint: info.accent)
                    .scaleEffect(0.82)
                    .frame(width: 312, height: 312)
                VStack(alignment: .leading, spacing: 16) {
                    Text(module.title)
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                    Text(info.tagline)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(info.features, id: \.self) { feature in
                            HStack(spacing: 12) {
                                IconTile(symbol: feature.icon, tint: info.accent)
                                Text(feature.text).font(.system(.headline, design: .rounded))
                            }
                        }
                    }
                    .padding(.top, 6)
                    accessory
                }
                .frame(maxWidth: 400, alignment: .leading)
            }
            .padding(.horizontal, 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            ScanButton(title: info.actionTitle, tint: info.accent, action: action)
                .padding(.bottom, 34)
        }
    }
}

extension ModuleIntro where Accessory == EmptyView {
    init(module: Module, action: @escaping () -> Void) {
        self.init(module: module, action: action, accessory: { EmptyView() })
    }
}
