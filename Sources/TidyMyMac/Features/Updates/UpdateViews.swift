import SwiftUI

/// Fenêtre « Nouvelle version disponible » avec les notes de version.
struct UpdateSheet: View {
    @EnvironmentObject var updates: UpdateChecker

    var body: some View {
        Group {
            if let release = updates.availableRelease {
                content(for: release)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill").font(.system(size: 40)).foregroundColor(Theme.mint)
                    Text("TidyMyMac est à jour").font(.system(.title3, design: .rounded).bold())
                    Button("Fermer") { updates.showDetails = false }
                        .buttonStyle(PrimaryButtonStyle())
                }
                .padding(30)
            }
        }
        .frame(width: 520)
        .background(AppBackground(accent: Theme.mint))
        .preferredColorScheme(.dark)
    }

    private func content(for release: Release) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                BrandMark(size: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text("TidyMyMac \(release.version.raw) est disponible")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text(subtitle(for: release)).font(.callout).foregroundColor(.secondary)
                }
            }
            Text("Nouveautés").font(.system(.headline, design: .rounded))
            ScrollView {
                Text(notes(release.notes))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                    .padding(14)
            }
            .frame(height: 220)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder))
            HStack {
                Button("Ignorer cette version") { updates.skip(release) }
                Spacer()
                Button("Plus tard") { updates.showDetails = false }
                    .keyboardShortcut(.cancelAction)
                Button(release.downloadURL == nil ? localized("Voir la version") : localized("Télécharger")) { updates.download(release) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
    }

    private func subtitle(for release: Release) -> String {
        var text = localized("Vous avez la version \(updates.current.raw)")
        if let date = release.publishedAt {
            text += localized(" · publiée \(date.relativeDescription)")
        }
        return text
    }

    /// Les notes GitHub sont en Markdown : on garde la mise en forme en ligne et les retours à la ligne.
    private func notes(_ markdown: String) -> AttributedString {
        let text = markdown.isEmpty ? localized("Pas de notes pour cette version.") : markdown
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Carte affichée dans la barre latérale quand une version plus récente existe.
struct UpdateCard: View {
    @EnvironmentObject var updates: UpdateChecker

    var body: some View {
        if let release = updates.availableRelease {
            Button { updates.showDetails = true } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(Theme.mint)
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Version \(release.version.raw) disponible")
                            .font(.system(.caption, design: .rounded).bold())
                        Text("Voir les nouveautés").font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.mint.opacity(0.10)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.mint.opacity(0.35)))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}
