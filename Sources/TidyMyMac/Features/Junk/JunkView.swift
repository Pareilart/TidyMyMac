import SwiftUI

struct JunkView: View {
    @EnvironmentObject var model: JunkModel
    @StateObject private var showPlan = ViewState(false)

    var body: some View {
        if model.phase == .idle {
            ModuleIntro(module: .junk) { Task { await model.scan() } }
        } else {
            VStack(spacing: 0) {
                ModuleHeader(module: .junk)
                Divider()
                content
            }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .scanning:
            ProgressPrompt(text: "Analyse : \(model.progressLabel)")
        case .cleaning:
            ProgressPrompt(text: "Nettoyage en cours…")
        case .done(let freed):
            DonePrompt(freed: freed, failures: model.failures, entryID: model.lastEntryID) {
                Task { await model.scan() }
            }
        case .ready:
            if model.results.isEmpty {
                StartPrompt(text: "Rien à nettoyer : votre Mac est propre.", buttonTitle: "Analyser à nouveau") {
                    Task { await model.scan() }
                }
            } else {
                results
            }
        }
    }

    private var results: some View {
        VStack(spacing: 0) {
            List {
                ForEach($model.results) { $result in
                    JunkCategoryRow(result: $result)
                }
            }
            Divider()
            ActionBar(
                summary: "\(model.selectedSize.formattedBytes) sélectionnés sur \(model.totalSize.formattedBytes)",
                actionTitle: "Nettoyer…",
                disabled: model.selectedSize == 0
            ) {
                showPlan.value = true
            }
        }
        .sheet(isPresented: $showPlan.value) {
            CleanupPlanSheet(model: model) { Task { await model.clean() } }
        }
    }
}

struct JunkCategoryRow: View {
    @Binding var result: JunkResult
    @StateObject private var expanded = ViewState(false)

    var body: some View {
        DisclosureGroup(isExpanded: $expanded.value) {
            ForEach($result.items) { $item in
                FileRow(url: item.url, size: item.size, selected: $item.selected)
            }
        } label: {
            HStack(spacing: 10) {
                Toggle("", isOn: Binding(
                    get: { result.allSelected },
                    set: { value in
                        for index in result.items.indices {
                            result.items[index].selected = value
                        }
                    }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                Image(systemName: result.rule.icon)
                    .foregroundColor(.accentColor)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(result.rule.title).font(.headline)
                    Text(result.rule.detail).font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                RiskBadge(risk: result.rule.effectiveRisk)
                sizeLabel
                RuleInfoButton(rule: result.rule)
            }
            .padding(.vertical, 4)
        }
    }

    /// Taille totale si tout est coché, « x sur y » si une partie l'est, total estompé si rien ne l'est.
    @ViewBuilder private var sizeLabel: some View {
        let selected = result.items.selectedSize
        let total = result.items.totalSize
        Group {
            if selected == total {
                Text(total.formattedBytes).foregroundColor(.secondary)
            } else if selected == 0 {
                Text(total.formattedBytes).foregroundColor(.secondary.opacity(0.5))
            } else {
                Text("\(selected.formattedBytes) sur \(total.formattedBytes)").foregroundColor(.secondary)
            }
        }
        .monospacedDigit()
    }
}
