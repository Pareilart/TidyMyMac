import SwiftUI

extension RiskLevel {
    var tint: Color {
        switch self {
        case .safe: return Theme.mint
        case .review: return Theme.amber
        case .irreversible: return Theme.coral
        }
    }
}

/// Pastille « Sans danger », « À vérifier » ou « Irréversible ».
struct RiskBadge: View {
    let risk: RiskLevel

    var body: some View {
        Label(risk.title, systemImage: risk.icon)
            .font(.caption2.weight(.semibold))
            .foregroundColor(risk.tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(risk.tint.opacity(0.14)))
            .fixedSize()
            .help(risk.explanation)
    }
}

/// Bouton ⓘ qui ouvre la fiche d'une règle.
struct RuleInfoButton: View {
    let rule: CleanupRule
    @StateObject private var shown = ViewState(false)

    var body: some View {
        Button { shown.value.toggle() } label: { Image(systemName: "info.circle") }
            .buttonStyle(.borderless)
            .help("Ce que fait cette règle")
            .popover(isPresented: $shown.value, arrowEdge: .trailing) {
                RuleDetails(rule: rule)
            }
    }
}

/// Ce que la règle supprime, ce qui se passe ensuite et comment revenir en arrière.
struct RuleDetails: View {
    let rule: CleanupRule

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                IconTile(symbol: rule.icon, tint: rule.effectiveRisk.tint, size: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(rule.title).font(.headline)
                    if rule.isCustom {
                        Text("Règle personnelle").font(.caption).foregroundColor(.secondary)
                    }
                }
                Spacer()
                RiskBadge(risk: rule.effectiveRisk)
            }
            Text(rule.detail).fixedSize(horizontal: false, vertical: true)
            if let afterRemoval = rule.afterRemoval {
                section("Après suppression", afterRemoval)
            }
            section("Niveau de risque", rule.effectiveRisk.explanation)
            section("Corbeille", trashNote)
            if !filters.isEmpty {
                section("Filtres", filters.joined(separator: "\n"))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Emplacements").font(.caption.weight(.semibold)).foregroundColor(.secondary)
                ForEach(rule.locations, id: \.self) { location in
                    Text(location)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var filters: [String] {
        var lines: [String] = []
        if rule.target == .search {
            let names = rule.names.joined(separator: ", ")
            lines.append(localized("Éléments nommés \(names), jusqu'à \(rule.maxDepth) niveaux"))
        }
        if !rule.extensions.isEmpty {
            let extensions = rule.extensions.joined(separator: ", ")
            lines.append(localized("Extensions : \(extensions)"))
        }
        if let days = rule.olderThanDays {
            lines.append(localized("Inchangés depuis \(days) jours"))
        }
        if !rule.exclude.isEmpty {
            let spared = rule.exclude.joined(separator: ", ")
            lines.append(localized("Épargnés : \(spared)"))
        }
        return lines
    }

    private var trashNote: String {
        if rule.permanent {
            return localized("Cette règle supprime toujours définitivement.")
        }
        if Remover.deletePermanently {
            return localized("Le réglage « Supprimer définitivement les fichiers inutiles » est activé : rien ne passe par la Corbeille.")
        }
        return localized("Les éléments vont dans la Corbeille : vous pouvez les remettre en place tant qu'elle n'est pas vidée.")
    }

    private func section(_ title: LocalizedStringKey, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption.weight(.semibold)).foregroundColor(.secondary)
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
        }
    }
}
