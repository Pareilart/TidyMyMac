import SwiftUI

extension RuleProfile {
    var color: Color {
        switch tint {
        case "aqua": return Theme.aqua
        case "sky": return Theme.sky
        case "lavender": return Theme.lavender
        case "rose": return Theme.rose
        case "lime": return Theme.lime
        case "peach": return Theme.peach
        case "amber": return Theme.amber
        case "coral": return Theme.coral
        default: return Theme.mint
        }
    }
}

/// Écran « Règles et profils » : ce que l'analyse des fichiers inutiles prend en compte.
struct RulesView: View {
    @EnvironmentObject var rules: RulesModel
    @StateObject private var editing = ViewState<RuleDraft?>(nil)
    @StateObject private var editingIsNew = ViewState(true)
    @StateObject private var pendingDeletion = ViewState<CleanupRule?>(nil)

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .rules)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    profiles
                    customRules
                    builtInRules
                }
                .padding(24)
            }
        }
        .sheet(item: $editing.value) { draft in
            RuleEditor(draft: draft, isNew: editingIsNew.value) { rules.save($0) }
        }
        .confirmationDialog(
            localized("Supprimer la règle « \(pendingTitle) » ?"),
            isPresented: Binding(get: { pendingDeletion.value != nil }, set: { if !$0 { pendingDeletion.value = nil } })
        ) {
            Button("Supprimer la règle", role: .destructive) {
                if let rule = pendingDeletion.value { rules.delete(rule) }
            }
        } message: {
            Text("Seule la règle est supprimée : aucun fichier n'est touché.")
        }
        .onAppear { rules.reload() }
    }

    private var pendingTitle: String { pendingDeletion.value?.title ?? "" }

    // MARK: Profils

    private var profiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Profils",
                subtitle: "Activez ceux qui correspondent à votre travail : leurs règles s'ajoutent à l'analyse des fichiers inutiles."
            )
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 250), spacing: 14)], spacing: 14) {
                ForEach(rules.contents.profiles) { profile in
                    ProfileCard(
                        profile: profile,
                        ruleCount: rules.contents.rules(of: profile.id).count,
                        enabled: Binding(get: { rules.isEnabled(profile) }, set: { rules.setEnabled($0, profile: profile) })
                    )
                }
            }
        }
    }

    // MARK: Règles personnelles

    private var customRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom) {
                SectionTitle(
                    title: "Mes règles",
                    subtitle: "Nettoyez un dossier que TidyMyMac ne connaît pas. Vos règles ne peuvent ni imposer une suppression définitive, ni viser un dossier système."
                )
                Spacer()
                Button {
                    editingIsNew.value = true
                    editing.value = RuleDraft()
                } label: {
                    Label("Nouvelle règle", systemImage: "plus")
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.peach, compact: true))
            }
            if let error = rules.saveError {
                Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(Theme.coral)
            }
            ForEach(rules.contents.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle").font(.caption).foregroundColor(Theme.amber)
            }
            if rules.contents.custom.isEmpty {
                Text("Aucune règle personnelle. Par exemple : les fichiers du dossier Téléchargements qui n'ont pas changé depuis 60 jours.")
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
            } else {
                RuleList(rules: rules.contents.custom) { rule in
                    Button {
                        editingIsNew.value = false
                        editing.value = RuleDraft(rule: rule)
                    } label: { Image(systemName: "pencil") }
                        .buttonStyle(.borderless)
                        .help("Modifier")
                    Button { pendingDeletion.value = rule } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .help("Supprimer la règle")
                }
            }
        }
    }

    // MARK: Règles intégrées

    private var builtInRules: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle(
                title: "Règles intégrées",
                subtitle: "Désactivez une règle pour que l'analyse l'ignore. Le bouton ⓘ explique ce qu'elle supprime."
            )
            RuleGroup(title: localized("Général"), icon: "sparkles", tint: Theme.mint, rules: rules.contents.rules(of: nil))
            ForEach(rules.contents.profiles.filter(rules.isEnabled)) { profile in
                RuleGroup(title: profile.title, icon: profile.icon, tint: profile.color, rules: rules.contents.rules(of: profile.id))
            }
            if let url = RuleBook.documentationURL {
                Link(destination: url) {
                    Label("Proposer une règle intégrée sur GitHub", systemImage: "arrow.up.right.square")
                }
                .font(.callout)
            }
        }
    }
}

private struct SectionTitle: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(.title3, design: .rounded).weight(.semibold))
            Text(subtitle).font(.callout).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ProfileCard: View {
    let profile: RuleProfile
    let ruleCount: Int
    @Binding var enabled: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconTile(symbol: profile.icon, tint: profile.color, size: 40)
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.title).font(.headline)
                Text(profile.detail)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(localized("\(ruleCount) règles")).font(.caption2).foregroundColor(.secondary)
                if profile.isDetected {
                    Label("Détecté sur ce Mac", systemImage: "checkmark.circle")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(profile.color)
                }
            }
            Spacer(minLength: 0)
            Toggle("", isOn: $enabled).toggleStyle(.switch).labelsHidden()
        }
        .padding(14)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(enabled ? profile.color.opacity(0.10) : Theme.card))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(enabled ? profile.color.opacity(0.45) : Theme.cardBorder)
        )
    }
}

private struct RuleGroup: View {
    let title: String
    let icon: String
    let tint: Color
    let rules: [CleanupRule]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(tint)
            RuleList(rules: rules) { _ in EmptyView() }
        }
    }
}

/// Liste de règles avec un interrupteur chacune et des actions facultatives.
private struct RuleList<Actions: View>: View {
    @EnvironmentObject var model: RulesModel
    let rules: [CleanupRule]
    @ViewBuilder let actions: (CleanupRule) -> Actions

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                if index > 0 { Divider().opacity(0.4) }
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(get: { model.isEnabled(rule) }, set: { model.setEnabled($0, rule: rule) }))
                        .toggleStyle(.switch)
                        .controlSize(.small)
                        .labelsHidden()
                    Image(systemName: rule.icon).foregroundColor(.accentColor).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(rule.title).font(.body.weight(.medium))
                        Text(rule.detail).font(.caption).foregroundColor(.secondary).lineLimit(2)
                    }
                    .opacity(model.isEnabled(rule) ? 1 : 0.5)
                    Spacer()
                    RiskBadge(risk: rule.effectiveRisk)
                    RuleInfoButton(rule: rule)
                    actions(rule)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
        }
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}
