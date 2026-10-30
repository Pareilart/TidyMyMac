import AppKit
import SwiftUI

/// Règle en cours d'édition, sous une forme facile à lier à un formulaire.
struct RuleDraft: Identifiable {
    let id: String
    var title = ""
    var detail = ""
    var afterRemoval = ""
    var icon = "folder"
    var locations: [String] = []
    var target: CleanupRule.Target = .contents
    var names = ""
    var maxDepth = 4
    var extensions = ""
    var exclude = ""
    var limitAge = false
    var olderThanDays = 30
    var includeHidden = false
    var risk: RiskLevel = .review
    var selectedByDefault = false

    static let icons = [
        "folder", "doc", "archivebox", "arrow.down.circle", "photo", "film", "music.note", "hammer",
        "terminal", "shippingbox", "clock.arrow.circlepath", "trash",
    ]

    /// Nouvelle règle, ou copie modifiable d'une règle existante.
    init(rule: CleanupRule? = nil) {
        guard let rule else {
            id = "custom-" + UUID().uuidString.prefix(8).lowercased()
            return
        }
        id = rule.id
        title = rule.title
        detail = rule.detail
        afterRemoval = rule.afterRemoval ?? ""
        icon = rule.icon
        locations = rule.locations
        target = rule.target
        names = rule.names.joined(separator: ", ")
        maxDepth = rule.maxDepth
        extensions = rule.extensions.joined(separator: ", ")
        exclude = rule.exclude.joined(separator: ", ")
        limitAge = rule.olderThanDays != nil
        olderThanDays = rule.olderThanDays ?? 30
        includeHidden = rule.includeHidden
        risk = rule.risk == .safe ? .safe : .review
        selectedByDefault = rule.selectedByDefault
    }

    private static func list(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var rule: CleanupRule {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let trimmedDetail = detail.trimmingCharacters(in: .whitespaces)
        let trimmedAfter = afterRemoval.trimmingCharacters(in: .whitespaces)
        return CleanupRule(
            id: id, icon: icon, risk: risk, selectedByDefault: selectedByDefault, locations: locations, target: target,
            names: target == .search ? Self.list(names) : [], maxDepth: maxDepth, includeHidden: includeHidden,
            extensions: Self.list(extensions).map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 },
            exclude: Self.list(exclude), olderThanDays: limitAge ? olderThanDays : nil, title: trimmedTitle,
            detail: trimmedDetail.isEmpty ? summary : trimmedDetail, afterRemoval: trimmedAfter.isEmpty ? nil : trimmedAfter
        )
    }

    /// Description générée quand l'utilisateur n'en écrit pas.
    private var summary: String {
        var parts = [locations.joined(separator: ", ")]
        let searched = Self.list(names).joined(separator: ", ")
        if target == .search, !searched.isEmpty {
            parts.append(localized("noms : \(searched)"))
        }
        if !Self.list(extensions).isEmpty {
            parts.append(Self.list(extensions).joined(separator: ", "))
        }
        if limitAge {
            parts.append(localized("inchangés depuis \(olderThanDays) jours"))
        }
        return parts.joined(separator: " · ")
    }

    /// Ce qui empêche d'enregistrer, ou `nil`.
    var problem: String? {
        if title.trimmingCharacters(in: .whitespaces).isEmpty { return localized("Donnez un nom à la règle.") }
        if locations.isEmpty { return localized("Ajoutez au moins un dossier.") }
        return RuleSafety.problem(with: rule)
    }
}

/// Résultat du bouton « Tester » : ce que la règle trouverait maintenant.
private struct RulePreview {
    let items: [URL]
    let size: Int64
}

struct RuleEditor: View {
    let onSave: (CleanupRule) -> Void
    @StateObject private var draft: ViewState<RuleDraft>
    @StateObject private var preview = ViewState<RulePreview?>(nil)
    @StateObject private var testing = ViewState(false)
    @Environment(\.dismiss) private var dismiss
    private let isNew: Bool

    init(draft: RuleDraft, isNew: Bool, onSave: @escaping (CleanupRule) -> Void) {
        _draft = StateObject(wrappedValue: ViewState(draft))
        self.isNew = isNew
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                IconTile(symbol: draft.value.icon, tint: draft.value.risk.tint, size: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(isNew ? localized("Nouvelle règle") : localized("Modifier la règle"))
                        .font(.system(.title3, design: .rounded).weight(.semibold))
                    Text("Elle s'ajoute à l'analyse des fichiers inutiles. Rien n'est supprimé sans votre accord.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    identity
                    folders
                    filters
                    risk
                    previewSection
                }
                .padding(20)
            }
            Divider()
            footer
        }
        .frame(width: 600, height: 680)
        .background(AppBackground(accent: Theme.peach).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.mint)
    }

    private var identity: some View {
        EditorSection(title: "Nom") {
            HStack(spacing: 10) {
                Picker("Icône", selection: $draft.value.icon) {
                    ForEach(RuleDraft.icons, id: \.self) { symbol in
                        Image(systemName: symbol).tag(symbol)
                    }
                }
                .labelsHidden()
                .fixedSize()
                TextField("Par exemple : Vieux téléchargements", text: $draft.value.title)
                    .textFieldStyle(.roundedBorder)
            }
            TextField("Description (facultatif)", text: $draft.value.detail)
                .textFieldStyle(.roundedBorder)
        }
    }

    private var folders: some View {
        EditorSection(title: "Où chercher") {
            ForEach(draft.value.locations, id: \.self) { location in
                HStack {
                    Image(systemName: "folder").foregroundColor(.secondary)
                    Text(location).font(.system(.callout, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    Button { draft.value.locations.removeAll { $0 == location } } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.borderless)
                    .help("Retirer ce dossier")
                }
            }
            Button("Ajouter un dossier…") { chooseFolders() }
            Picker("Ce qui est supprimé", selection: $draft.value.target) {
                Text("Le contenu des dossiers").tag(CleanupRule.Target.contents)
                Text("Les dossiers eux-mêmes").tag(CleanupRule.Target.location)
                Text("Les éléments portant un nom précis").tag(CleanupRule.Target.search)
            }
            .pickerStyle(.radioGroup)
            if draft.value.target == .search {
                TextField("Noms cherchés, séparés par des virgules (ex. : node_modules, *.tmp)", text: $draft.value.names)
                    .textFieldStyle(.roundedBorder)
                Stepper(value: $draft.value.maxDepth, in: 1...10) {
                    Text(localized("Jusqu'à \(draft.value.maxDepth) niveaux de sous-dossiers"))
                }
            }
        }
    }

    private var filters: some View {
        EditorSection(title: "Filtres") {
            TextField("Extensions, séparées par des virgules (ex. : dmg, zip)", text: $draft.value.extensions)
                .textFieldStyle(.roundedBorder)
            HStack {
                Toggle("Seulement s'ils n'ont pas changé depuis", isOn: $draft.value.limitAge)
                Stepper(value: $draft.value.olderThanDays, in: 1...3650, step: draft.value.olderThanDays < 30 ? 1 : 15) {
                    Text(localized("\(draft.value.olderThanDays) jours")).monospacedDigit()
                }
                .disabled(!draft.value.limitAge)
            }
            TextField("Noms à épargner, séparés par des virgules", text: $draft.value.exclude)
                .textFieldStyle(.roundedBorder)
            Toggle("Inclure les éléments masqués", isOn: $draft.value.includeHidden)
        }
    }

    private var risk: some View {
        EditorSection(title: "Niveau de risque") {
            Picker("Niveau de risque", selection: $draft.value.risk) {
                Text(RiskLevel.safe.title).tag(RiskLevel.safe)
                Text(RiskLevel.review.title).tag(RiskLevel.review)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            Text(draft.value.risk.explanation).font(.caption).foregroundColor(.secondary)
            TextField("Après suppression : ce qui se passe, comment récupérer (facultatif)", text: $draft.value.afterRemoval)
                .textFieldStyle(.roundedBorder)
            Toggle("Cocher par défaut dans Fichiers inutiles", isOn: $draft.value.selectedByDefault)
        }
    }

    private var previewSection: some View {
        EditorSection(title: "Aperçu") {
            HStack(spacing: 10) {
                Button(testing.value ? localized("Recherche…") : localized("Tester la règle")) { runPreview() }
                    .disabled(testing.value || draft.value.problem != nil)
                if let result = preview.value {
                    Text(localized("\(result.items.count) élément(s) · \(result.size.formattedBytes)"))
                        .font(.callout.weight(.semibold))
                        .monospacedDigit()
                }
            }
            if let result = preview.value {
                ForEach(result.items.prefix(6), id: \.self) { url in
                    Text(url.path.abbreviatingHome)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                if result.items.count > 6 {
                    Text(localized("… et \(result.items.dropFirst(6).count) autres")).font(.caption).foregroundColor(.secondary)
                }
            }
            Text("Le test ne supprime rien : il montre ce que la règle trouverait maintenant.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if let problem = draft.value.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundColor(Theme.amber)
                    .lineLimit(2)
            }
            Spacer()
            Button("Annuler") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Enregistrer") {
                onSave(draft.value.rule)
                dismiss()
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .keyboardShortcut(.defaultAction)
            .disabled(draft.value.problem != nil)
        }
        .padding(16)
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = localized("Ajouter")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            let path = url.path.abbreviatingHome
            if !draft.value.locations.contains(path) {
                draft.value.locations.append(path)
            }
        }
        preview.value = nil
    }

    private func runPreview() {
        let rule = draft.value.rule
        testing.value = true
        Task {
            let result = await Task.detached(priority: .userInitiated) {
                let items = rule.locate()
                return RulePreview(items: items, size: items.reduce(Int64(0)) { $0 + FS.size(of: $1) })
            }.value
            preview.value = result
            testing.value = false
        }
    }
}

private struct EditorSection<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(.headline, design: .rounded))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
