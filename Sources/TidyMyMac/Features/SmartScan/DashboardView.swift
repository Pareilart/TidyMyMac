import SwiftUI

@MainActor
final class DashboardState: ObservableObject {
    @Published var disk = DiskInfo.current()
    @Published var running = false
    @Published var hasRun = false
}

struct DashboardView: View {
    @Binding var selection: Module?
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var junk: JunkModel
    @EnvironmentObject var launchItems: LaunchItemsModel
    @StateObject private var state = DashboardState()
    @StateObject private var showPlan = ViewState(false)

    private func openPerformance(_ route: PerformanceRoute) {
        navigation.performanceRoute = route
        selection = .performance
    }

    var body: some View {
        if !state.running && !state.hasRun {
            ModuleIntro(module: .smartScan) { runSmartScan() }
        } else {
            VStack(spacing: 0) {
                ModuleHeader(module: .smartScan)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        diskCard
                        if state.running {
                            Card {
                                HStack(spacing: 12) {
                                    ProgressView().controlSize(.small)
                                    Text("Analyse en cours : \(junk.progressLabel)").foregroundColor(.secondary)
                                }
                            }
                        } else {
                            summary
                        }
                    }
                    .padding(24)
                }
            }
        }
    }

    private var diskCard: some View {
        Card {
            HStack(spacing: 16) {
                RingGauge(value: state.disk?.usedFraction ?? 0, tint: Theme.level(state.disk?.usedFraction ?? 0))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Disque de démarrage").font(.system(.headline, design: .rounded))
                    if let disk = state.disk {
                        Text("\(disk.free.formattedBytes) disponibles sur \(disk.total.formattedBytes)")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    } else {
                        Text("Informations indisponibles").foregroundColor(.secondary)
                    }
                }
            }
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            Card {
                SummaryRow(
                    icon: "trash", tint: Theme.aqua,
                    title: "Fichiers inutiles",
                    value: junk.phase == .ready ? "\(junk.selectedSize.formattedBytes) à nettoyer" : "Nettoyage terminé",
                    buttonTitle: "Détails"
                ) { selection = .junk }
            }
            Card {
                SummaryRow(
                    icon: "power", tint: Theme.lavender,
                    title: "Éléments de démarrage",
                    value: launchItems.brokenCount > 0
                        ? "\(launchItems.brokenCount) élément(s) cassé(s) sur \(launchItems.items.count)"
                        : "\(launchItems.items.count) élément(s), aucun cassé",
                    buttonTitle: "Voir"
                ) { openPerformance(.backgroundItems) }
            }
            Card {
                SummaryRow(
                    icon: "wrench.and.screwdriver", tint: Theme.lime,
                    title: "Maintenance",
                    value: "Vider le cache DNS et libérer la mémoire vive",
                    buttonTitle: "Ouvrir"
                ) { openPerformance(.overview) }
            }
            HStack {
                Button("Relancer l'analyse") { runSmartScan() }
                Spacer()
                if case .done(let freed) = junk.phase {
                    Text("\(freed.formattedBytes) libérés").font(.system(.headline, design: .rounded)).foregroundColor(Theme.mint)
                }
                if junk.phase == .ready && junk.selectedSize > 0 {
                    Button("Nettoyer \(junk.selectedSize.formattedBytes)…") { showPlan.value = true }
                        .buttonStyle(PrimaryButtonStyle())
                }
            }
            .padding(.top, 4)
        }
        .sheet(isPresented: $showPlan.value) {
            CleanupPlanSheet(model: junk) { cleanFromPlan() }
        }
    }

    private func cleanFromPlan() {
        Task {
            await junk.clean()
            state.disk = DiskInfo.current()
        }
    }

    private func runSmartScan() {
        state.running = true
        Task {
            await junk.scan()
            await launchItems.load()
            state.disk = DiskInfo.current()
            state.running = false
            state.hasRun = true
        }
    }
}

private struct SummaryRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let buttonTitle: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            IconTile(symbol: icon, tint: tint, size: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(.headline, design: .rounded))
                Text(value).foregroundColor(.secondary).monospacedDigit()
            }
            Spacer()
            Button(buttonTitle, action: action)
        }
    }
}
