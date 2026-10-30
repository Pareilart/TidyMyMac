import AppKit
import SemanticSearch
import SwiftUI

struct SmartSearchView: View {
    @EnvironmentObject var model: SmartSearchModel

    private var accent: Color { Module.search.info.accent }

    var body: some View {
        Group {
            switch model.modelState {
            case .missing:
                // « Activer » ouvre d'abord le choix du modèle, le recommandé en tête.
                ModuleIntro(module: .search, action: { model.showingModelPicker = true }) {
                    VStack(alignment: .leading, spacing: 8) {
                        PrivacyNote()
                        Text("À l'étape suivante, choisissez le modèle open source à télécharger depuis Hugging Face : un seul téléchargement, ensuite tout se passe sur votre Mac.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, 8)
                }
            case .downloading(let fraction):
                downloadProgress(fraction)
            case .loading:
                ProgressPrompt(text: "Chargement du modèle \(model.selectedModel.name)…")
            case .failed(let message):
                VStack(spacing: 14) {
                    Spacer()
                    Text(message)
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    HStack {
                        Button("Réessayer") { Task { await model.downloadModel() } }
                            .buttonStyle(PrimaryButtonStyle(tint: accent))
                        Button("Choisir un autre modèle…") { model.showingModelPicker = true }
                    }
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            case .ready:
                searchScreen
            }
        }
        .task { await model.prepare() }
        .sheet(isPresented: $model.showingModelPicker) {
            ModelPickerSheet().environmentObject(model)
        }
    }

    // MARK: - Téléchargement

    private func downloadProgress(_ fraction: Double) -> some View {
        VStack(spacing: 16) {
            Spacer()
            HeroIllustration(symbol: "arrow.down", tint: accent)
                .scaleEffect(0.6)
                .frame(width: 230, height: 230)
            Text("Téléchargement du modèle").font(.system(size: 22, weight: .semibold, design: .rounded))
            ProgressView(value: fraction)
                .tint(accent)
                .frame(width: 320)
            Text("\(Int64(Double(model.selectedModel.downloadSize) * fraction).formattedBytes) sur \(model.selectedModel.downloadSize.formattedBytes) · \(model.selectedModel.repository)")
                .font(.caption)
                .foregroundColor(.secondary)
                .monospacedDigit()
            Label("Seul le modèle est téléchargé. Aucune de vos données n'est envoyée.", systemImage: "lock.shield.fill")
                .font(.caption)
                .foregroundColor(Theme.mint)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Recherche

    private var searchScreen: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .search)
            searchField
            PrivacyNote()
                .padding(.horizontal, 24)
                .padding(.bottom, 14)
            Divider()
            content
            footer
        }
    }

    private var searchField: some View {
        HStack(spacing: 12) {
            Image(systemName: "text.magnifyingglass")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(accent)
            TextField("Décrivez le fichier, par exemple « mon assurance responsabilité civile »", text: $model.query)
                .textFieldStyle(.plain)
                .font(.system(size: 16, design: .rounded))
                .onSubmit { Task { await model.search() } }
            if model.searching {
                ProgressView().controlSize(.small)
            }
            Button("Rechercher") { Task { await model.search() } }
                .buttonStyle(PrimaryButtonStyle(tint: accent, compact: true))
                .disabled(model.query.trimmingCharacters(in: .whitespaces).isEmpty || !model.hasIndex)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(accent.opacity(0.35)))
        .padding(.horizontal, 24)
        .padding(.bottom, 16)
    }

    @ViewBuilder private var content: some View {
        if !model.hasIndex, let progress = model.indexing {
            VStack(spacing: 14) {
                Spacer()
                Text("Indexation de vos documents").font(.system(size: 20, weight: .semibold, design: .rounded))
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(accent)
                    .frame(width: 320)
                Text(progress.total == 0
                     ? localized("Recherche des documents…")
                     : localized("\(progress.done) sur \(progress.total) · \(progress.current)"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
                Text("Documents, Téléchargements et Bureau sont lus une fois. Seuls les fichiers modifiés seront relus ensuite.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Label("L'indexation se fait entièrement sur ce Mac : aucun fichier n'est envoyé à un serveur.", systemImage: "lock.shield.fill")
                    .font(.caption)
                    .foregroundColor(Theme.mint)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !model.hasIndex {
            StartPrompt(text: "Indexez vos documents pour pouvoir les rechercher.", buttonTitle: "Indexer mes documents") {
                model.reindex()
            }
        } else if let searched = model.searchedQuery {
            if model.results.isEmpty {
                StartPrompt(text: "Aucun document ne correspond à « \(searched) ».", buttonTitle: "Réindexer") {
                    model.reindex()
                }
            } else {
                List(model.results) { hit in
                    SearchResultRow(hit: hit, accent: accent)
                }
            }
        } else {
            examples
        }
    }

    private var examples: some View {
        VStack(spacing: 14) {
            Spacer()
            Text("Essayez par exemple").font(.system(.headline, design: .rounded)).foregroundColor(.secondary)
            VStack(spacing: 8) {
                ForEach(SmartSearchModel.examples, id: \.self) { example in
                    Button { Task { await model.search(example: example) } } label: {
                        Label(example, systemImage: "sparkle")
                            .font(.system(.body, design: .rounded))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Capsule().fill(accent.opacity(0.12)))
                            .overlay(Capsule().strokeBorder(accent.opacity(0.3)))
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if let progress = model.indexing {
                ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1)))
                    .tint(accent)
                    .frame(width: 140)
                Text("Indexation \(progress.done)/\(progress.total) · \(progress.current)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button("Arrêter") { model.cancelIndexing() }
            } else {
                Image(systemName: "lock.shield").foregroundColor(Theme.mint)
                Text(indexSummary).font(.caption).foregroundColor(.secondary)
                Spacer()
                Toggle("Lire les scans et images (OCR)", isOn: $model.useOCR)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                Button("Réindexer") { model.reindex() }
                Menu {
                    Button("Changer de modèle…") { model.showingModelPicker = true }
                    Divider()
                    Button("Supprimer les modèles et les index", role: .destructive) { model.removeAll() }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 32)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
    }

    private var indexSummary: String {
        var text = localized("\(model.documentCount) documents indexés avec \(model.selectedModel.name)")
        if let date = model.indexDate {
            text += localized(" · mis à jour \(date.relativeDescription)")
        }
        return text + localized(" · traitement entièrement local")
    }
}

/// Rappel visible de la confidentialité : l'indexation et la recherche se font sur le Mac, sans aucun envoi.
private struct PrivacyNote: View {
    @StateObject private var expanded = ViewState(false)

    private static var details: [String] { [
        localized("Le texte de vos documents est lu et analysé sur ce Mac, y compris la reconnaissance de texte des scans (Vision, sur l'appareil)."),
        localized("Le modèle d'IA s'exécute sur le processeur de ce Mac : aucune requête n'est envoyée à un service en ligne."),
        localized("L'index reste dans ~/Library/Application Support/TidyMyMac/Search et peut être supprimé à tout moment."),
        localized("Vos recherches ne sont ni envoyées, ni enregistrées."),
        localized("Le seul accès réseau est le téléchargement initial du modèle depuis Hugging Face ; il ne transmet aucune de vos données."),
    ] }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock.shield.fill").foregroundColor(Theme.mint)
                Text("Tout reste sur ce Mac : vos fichiers, l'index et vos recherches ne sont envoyés à aucun serveur.")
                    .font(.system(.callout, design: .rounded).weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(expanded.value ? localized("Masquer") : localized("Détails")) {
                    withAnimation(.easeInOut(duration: 0.2)) { expanded.value.toggle() }
                }
                .buttonStyle(.borderless)
            }
            if expanded.value {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Self.details, id: \.self) { line in
                        Label(line, systemImage: "checkmark")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.leading, 26)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.mint.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.mint.opacity(0.3)))
    }
}

private struct SearchResultRow: View {
    let hit: SearchHit
    let accent: Color

    private var relevance: Double { hit.relevance }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(nsImage: FS.icon(for: hit.url))
                .resizable()
                .frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(hit.url.lastPathComponent)
                        .font(.system(.headline, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    relevanceBadge
                }
                Text("\(hit.url.deletingLastPathComponent().path.abbreviatingHome) · modifié \(hit.modified.relativeDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet)
                        .font(.callout)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: 8)
            Button("Ouvrir") { NSWorkspace.shared.open(hit.url) }
            Button { FS.reveal(hit.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Afficher dans le Finder")
        }
        .padding(.vertical, 6)
        .opacity(relevance < 0.15 ? 0.55 : 1)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { NSWorkspace.shared.open(hit.url) }
    }

    private var relevanceBadge: some View {
        let (label, color): (String, Color) = relevance >= 0.7
            ? (localized("Très pertinent"), Theme.mint)
            : relevance >= 0.35
                ? (localized("Pertinent"), accent)
                : (localized("Peu pertinent"), Color(white: 0.6))
        return Text(label)
            .font(.caption2.bold())
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}
