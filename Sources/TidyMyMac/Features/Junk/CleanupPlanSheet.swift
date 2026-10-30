import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum PlanSort: String, CaseIterable, Identifiable {
    case size, oldest, name

    var id: String { rawValue }

    var title: String {
        switch self {
        case .size: return localized("Plus gros d'abord")
        case .oldest: return localized("Plus anciens d'abord")
        case .name: return localized("Par nom")
        }
    }
}

/// Seuils du filtre de taille, en octets.
private let sizeThresholds: [Int64] = [0, 10_000_000, 100_000_000, 1_000_000_000]

/// Revue avant suppression : exactement ce qui va partir, d'où vient chaque proposition et où ira chaque élément.
struct CleanupPlanSheet: View {
    @ObservedObject var model: JunkModel
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss
    @StateObject private var plan: ViewState<CleanupPlan>
    @StateObject private var search = ViewState("")
    @StateObject private var risk = ViewState<RiskLevel?>(nil)
    @StateObject private var rule = ViewState<String?>(nil)
    @StateObject private var minSize = ViewState<Int64>(0)
    @StateObject private var sort = ViewState(PlanSort.size)

    init(model: JunkModel, onConfirm: @escaping () -> Void) {
        _model = ObservedObject(wrappedValue: model)
        _plan = StateObject(wrappedValue: ViewState(CleanupPlan(results: model.results)))
        self.onConfirm = onConfirm
    }

    private var visibleItems: [PlanItem] {
        let query = search.value.trimmingCharacters(in: .whitespaces)
        let filtered = plan.value.items.filter { item in
            (risk.value == nil || item.risk == risk.value)
                && (rule.value == nil || item.ruleID == rule.value)
                && item.size >= minSize.value
                && (query.isEmpty || item.path.localizedCaseInsensitiveContains(query))
        }
        switch sort.value {
        case .size: return filtered.sorted { $0.size > $1.size }
        case .oldest: return filtered.sorted { ($0.modified ?? .distantFuture) < ($1.modified ?? .distantFuture) }
        case .name: return filtered.sorted { $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending }
        }
    }

    /// Règles présentes dans le plan, pour le filtre.
    private var rules: [(id: String, title: String)] {
        var seen = Set<String>()
        return plan.value.items.compactMap { item in seen.insert(item.ruleID).inserted ? (item.ruleID, item.rule) : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            filters.padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            list
            Divider()
            footer
        }
        .frame(width: 920, height: 640)
        .background(AppBackground(accent: Theme.aqua).ignoresSafeArea())
        .preferredColorScheme(.dark)
        .tint(Theme.mint)
    }

    // MARK: En-tête

    private var header: some View {
        HStack(spacing: 14) {
            IconTile(symbol: "list.bullet.clipboard", tint: Theme.aqua, size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("Plan de nettoyage").font(.system(.title2, design: .rounded).weight(.semibold))
                Text("Voici exactement ce qui sera supprimé. Rien ne bouge tant que vous n'avez pas confirmé.")
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(plan.value.totalSize.formattedBytes)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Text(localized("\(plan.value.items.count) élément(s)")).font(.caption).foregroundColor(.secondary)
            }
        }
        .padding(20)
    }

    // MARK: Filtres

    private var filters: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                TextField("Rechercher un nom ou un chemin", text: $search.value).textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Theme.card))
            .frame(maxWidth: 260)
            Picker("Risque", selection: $risk.value) {
                Text("Tous les risques").tag(RiskLevel?.none)
                ForEach(RiskLevel.allCases, id: \.self) { level in
                    Text(level.title).tag(RiskLevel?.some(level))
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Règle", selection: $rule.value) {
                Text("Toutes les règles").tag(String?.none)
                ForEach(rules, id: \.id) { rule in
                    Text(rule.title).tag(String?.some(rule.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            Picker("Taille", selection: $minSize.value) {
                ForEach(sizeThresholds, id: \.self) { threshold in
                    Text(threshold == 0 ? localized("Toutes les tailles") : localized("\(threshold.formattedBytes) et plus"))
                        .tag(threshold)
                }
            }
            .labelsHidden()
            .fixedSize()
            Picker("Tri", selection: $sort.value) {
                ForEach(PlanSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .fixedSize()
            Spacer(minLength: 0)
            Menu {
                Button("Exporter en CSV…") { export(as: .commaSeparatedText) }
                Button("Exporter en JSON…") { export(as: .json) }
            } label: {
                Label("Exporter le plan", systemImage: "square.and.arrow.up")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    // MARK: Liste

    private var list: some View {
        let items = visibleItems
        return ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(items) { item in
                    PlanRow(item: item) { remove(item) }
                    Divider().opacity(0.3)
                }
                if items.isEmpty {
                    Text(plan.value.items.isEmpty
                        ? localized("Le plan est vide : rien ne sera supprimé.")
                        : localized("Aucun élément ne correspond aux filtres."))
                        .foregroundColor(.secondary)
                        .padding(40)
                }
            }
            .padding(.horizontal, 20)
        }
    }

    // MARK: Pied

    private var footer: some View {
        let shownCount = visibleItems.count
        let total = plan.value.items.count
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                if shownCount < total {
                    Label(localized("Affichage : \(shownCount) sur \(total). Le nettoyage porte sur tout le plan."), systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption)
                        .foregroundColor(Theme.amber)
                }
                Text(destinationSummary).font(.caption).foregroundColor(.secondary)
            }
            Spacer()
            Button("Annuler") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(localized("Nettoyer \(total) élément(s) · \(plan.value.totalSize.formattedBytes)")) {
                dismiss()
                onConfirm()
            }
            .buttonStyle(PrimaryButtonStyle(compact: true))
            .keyboardShortcut(.defaultAction)
            .disabled(total == 0)
        }
        .padding(16)
    }

    private var destinationSummary: String {
        let permanentCount = plan.value.permanentCount
        let trashCount = plan.value.items.count - permanentCount
        if permanentCount == 0 {
            return localized("Tout va dans la Corbeille : vous pourrez annuler tant qu'elle n'est pas vidée.")
        }
        return localized("\(trashCount) vers la Corbeille, \(permanentCount) supprimé(s) définitivement, sans retour possible.")
    }

    /// Retire l'élément du plan et le décoche dans l'analyse.
    private func remove(_ item: PlanItem) {
        plan.value.items.removeAll { $0.id == item.id }
        for resultIndex in model.results.indices {
            for itemIndex in model.results[resultIndex].items.indices
                where model.results[resultIndex].items[itemIndex].url.path == item.path {
                model.results[resultIndex].items[itemIndex].selected = false
            }
        }
    }

    private func export(as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "TidyMyMac-" + localized("Plan de nettoyage") + (type == .json ? ".json" : ".csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = type == .json ? try? plan.value.json() : plan.value.csv().data(using: .utf8)
        try? data?.write(to: url, options: .atomic)
    }
}

private struct PlanRow: View {
    let item: PlanItem
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: FS.icon(for: item.url)).resizable().frame(width: 20, height: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1)
                Text("\(item.rule) · \(item.url.deletingLastPathComponent().path.abbreviatingHome)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if let modified = item.modified {
                Text(localized("modifié \(modified.relativeDescription)"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 150, alignment: .trailing)
            }
            Text(item.size.formattedBytes)
                .font(.callout)
                .monospacedDigit()
                .frame(width: 80, alignment: .trailing)
            RiskBadge(risk: item.risk)
            Image(systemName: item.permanent ? "xmark.bin" : "trash")
                .foregroundColor(item.permanent ? Theme.coral : Theme.sky)
                .frame(width: 18)
                .help(item.permanent ? localized("Supprimé définitivement") : localized("Placé dans la Corbeille"))
            Button { FS.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Afficher dans le Finder")
            Button(action: remove) { Image(systemName: "minus.circle") }
                .buttonStyle(.borderless)
                .help("Retirer du plan")
        }
        .padding(.vertical, 7)
    }
}
