import AppKit
import SwiftUI

/// État local d'une vue. Remplace `@State`, qui est une macro dans le SDK macOS 27
/// et dont le plugin n'est fourni qu'avec Xcode (pas avec les Command Line Tools).
final class ViewState<Value>: ObservableObject {
    @Published var value: Value

    init(_ value: Value) {
        self.value = value
    }
}

struct ModuleHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    var tint: Color = .accentColor

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: icon, tint: tint, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 24, weight: .semibold, design: .rounded))
                Text(subtitle).foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 24)
        .padding(.top, 30)
        .padding(.bottom, 16)
    }
}

extension ModuleHeader {
    init(module: Module) {
        self.init(title: module.title, subtitle: module.info.tagline, icon: module.icon, tint: module.info.accent)
    }
}

struct StartPrompt: View {
    let text: LocalizedStringKey
    var buttonTitle: LocalizedStringKey = "Analyser"
    let action: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Text(text)
                .font(.title3)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            Button(buttonTitle, action: action)
                .buttonStyle(PrimaryButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ProgressPrompt: View {
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
            Text(text)
                .foregroundColor(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct DonePrompt: View {
    let freed: Int64
    let failures: [URL]
    let again: () -> Void
    @AppStorage(Stats.totalFreedKey) private var totalFreed = 0
    @EnvironmentObject private var navigation: AppNavigation

    var body: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 54))
                .foregroundColor(Theme.mint)
                .shadow(color: Theme.mint.opacity(0.5), radius: 20)
            Text("\(freed.formattedBytes) libérés").font(.system(size: 30, weight: .semibold, design: .rounded))
            HStack(spacing: 12) {
                GainTile(icon: "sparkles", value: freed.formattedGain, label: "Libéré maintenant", tint: Theme.mint)
                GainTile(
                    icon: "internaldrive", value: DiskInfo.current()?.free.formattedBytes ?? "—",
                    label: "Disque disponible", tint: Theme.sky
                )
                GainTile(icon: "chart.line.uptrend.xyaxis", value: Int64(totalFreed).formattedGain, label: "Total avec TidyMyMac", tint: Theme.lavender)
            }
            .frame(maxWidth: 680)
            .padding(.vertical, 6)
            if !failures.isEmpty {
                Text("\(failures.count) élément(s) n'ont pas pu être supprimés. Vérifiez l'accès complet au disque dans les réglages.")
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            HStack(spacing: 12) {
                Button("Analyser à nouveau", action: again)
                Button("Voir le détail dans l'historique") { navigation.selection = .history }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

struct ActionBar: View {
    let summary: LocalizedStringKey
    let actionTitle: LocalizedStringKey
    var disabled = false
    let action: () -> Void

    var body: some View {
        HStack {
            Text(summary).foregroundColor(.secondary).monospacedDigit()
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(PrimaryButtonStyle())
                .disabled(disabled)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.18))
    }
}

struct FileRow: View {
    let url: URL
    let size: Int64
    @Binding var selected: Bool
    var detail: String? = nil

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $selected).toggleStyle(.checkbox).labelsHidden()
            Image(nsImage: FS.icon(for: url))
                .resizable()
                .frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(url.lastPathComponent).lineLimit(1)
                Text(detail ?? url.deletingLastPathComponent().path.abbreviatingHome)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(size.formattedBytes).monospacedDigit().foregroundColor(.secondary)
            Button { FS.reveal(url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Afficher dans le Finder")
        }
    }
}

/// Une valeur gagnée (espace, mémoire…) mise en avant après une action.
struct GainTile: View {
    let icon: String
    let value: String
    let label: LocalizedStringKey
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            IconTile(symbol: icon, tint: tint, size: 38)
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(label).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
