import SemanticSearch
import SwiftUI

/// Choix du modèle open source utilisé par la Recherche IA.
struct ModelPickerSheet: View {
    @EnvironmentObject var model: SmartSearchModel

    private var accent: Color { Module.search.info.accent }

    /// Première activation : aucun modèle n'est encore installé.
    private var activating: Bool { !model.isInstalled(model.selectedModel) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(activating ? localized("Choisissez votre modèle") : "Modèle de recherche")
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                    if activating {
                        Text("Le modèle recommandé convient à la plupart des usages, en particulier pour des documents en français.")
                            .font(.callout)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Button(activating ? localized("Annuler") : localized("Fermer")) { model.showingModelPicker = false }
                    .keyboardShortcut(.cancelAction)
            }
            Label(
                "Tous ces modèles sont open source et s'exécutent sur ce Mac : vos documents ne sont jamais envoyés. Changer de modèle demande de réindexer vos documents.",
                systemImage: "lock.shield.fill"
            )
            .font(.caption)
            .foregroundColor(.secondary)
            .fixedSize(horizontal: false, vertical: true)

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    sectionTitle(localized("Recommandé"))
                    ModelRow(descriptor: ModelStore.defaultModel, accent: accent)
                    sectionTitle(localized("Autres modèles open source"))
                    ForEach(Array(ModelStore.catalog.dropFirst())) { descriptor in
                        ModelRow(descriptor: descriptor, accent: accent)
                    }
                    if !model.customModels.isEmpty {
                        sectionTitle(localized("Ajoutés depuis Hugging Face"))
                        ForEach(model.customModels) { descriptor in
                            ModelRow(descriptor: descriptor, accent: accent)
                        }
                    }
                }
            }
            .frame(height: 380)

            customModelSection
        }
        .padding(24)
        .frame(width: 640)
        .background(AppBackground(accent: accent))
        .preferredColorScheme(.dark)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundColor(.secondary)
            .padding(.top, 4)
    }

    private var customModelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Autre modèle Hugging Face").font(.system(.headline, design: .rounded))
            HStack {
                TextField("propriétaire/modèle", text: $model.customRepository)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await model.addCustomModel() } }
                if model.resolvingCustomModel {
                    ProgressView().controlSize(.small)
                }
                Button("Vérifier et ajouter") { Task { await model.addCustomModel() } }
                    .buttonStyle(PrimaryButtonStyle(tint: accent, compact: true))
                    .disabled(model.customRepository.trimmingCharacters(in: .whitespaces).isEmpty || model.resolvingCustomModel)
            }
            if let error = model.customModelError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundColor(Theme.coral)
            }
            Text("Compatible : modèles d'embeddings BERT, RoBERTa, XLM-RoBERTa ou CamemBERT au format safetensors, avec un tokenizer Unigram ou WordPiece. La compatibilité est vérifiée avant tout téléchargement.")
                .font(.caption)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

private struct ModelRow: View {
    let descriptor: ModelDescriptor
    let accent: Color
    @EnvironmentObject var model: SmartSearchModel

    var body: some View {
        let selected = descriptor.id == model.selectedModel.id
        let installed = model.isInstalled(descriptor)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                .font(.title3)
                .foregroundColor(selected ? accent : .secondary)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(descriptor.name).font(.system(.headline, design: .rounded))
                    if descriptor.id == ModelStore.defaultModel.id { tag(localized("Recommandé"), Theme.mint) }
                    if descriptor.isCustom { tag(localized("Personnalisé"), Theme.lavender) }
                    if installed { tag(localized("Installé"), Theme.sky) }
                }
                Text(descriptor.summary).font(.callout).foregroundColor(.secondary)
                Text("\(descriptor.languages) · \(descriptor.downloadSize.formattedBytes) · licence \(descriptor.license)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(descriptor.repository).font(.caption2.monospaced()).foregroundColor(.secondary)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if selected && installed {
                    Text("Utilisé").font(.caption.bold()).foregroundColor(accent)
                } else {
                    let recommended = descriptor.id == ModelStore.defaultModel.id
                    Button(installed ? localized("Utiliser") : localized("Télécharger \(descriptor.downloadSize.formattedBytes)")) { use(installed: installed) }
                        .buttonStyle(PrimaryButtonStyle(tint: recommended ? Theme.mint : accent, compact: true))
                }
                if installed || descriptor.isCustom {
                    Button("Supprimer", role: .destructive) { model.deleteModel(descriptor) }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
                if let page = descriptor.pageURL {
                    Link("Fiche du modèle", destination: page).font(.caption)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(selected ? accent.opacity(0.10) : Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? accent.opacity(0.45) : Theme.cardBorder))
    }

    private func use(installed: Bool) {
        model.select(descriptor)
        model.showingModelPicker = false
        if !installed {
            Task { await model.downloadModel() }
        }
    }

    private func tag(_ text: String, _ tint: Color) -> some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
