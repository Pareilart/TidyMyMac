import AppKit
import SwiftUI

/// Écran affiché dans le module Performances : la vue d'ensemble ou l'un des gestionnaires détaillés.
enum PerformanceRoute: Equatable {
    case overview, maintenance, loginItems, backgroundItems
}

struct PerformanceView: View {
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var launchItems: LaunchItemsModel

    var body: some View {
        if !launchItems.loaded {
            ModuleIntro(module: .performance) { Task { await analyze() } }
        } else {
            switch navigation.performanceRoute {
            case .overview: PerformanceOverview { Task { await analyze() } }
            case .maintenance: MaintenanceManager()
            case .loginItems: LoginItemsManager()
            case .backgroundItems: BackgroundItemsManager()
            }
        }
    }

    private func analyze() async {
        await launchItems.load()
        await launchItems.loadLoginItems()
    }
}

// MARK: - Vue d'ensemble

private struct PerformanceOverview: View {
    let rescan: () -> Void
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var maintenance: MaintenanceModel
    @EnvironmentObject var launchItems: LaunchItemsModel

    private let cardTitle = Font.system(size: 20, weight: .semibold, design: .rounded)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: rescan) { Label("Relancer l'analyse", systemImage: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                Spacer()
            }
            .overlay(Text("Performances").font(.system(.headline, design: .rounded)).foregroundColor(.secondary))
            .padding(.horizontal, 24)
            .padding(.top, 34)
            .padding(.bottom, 8)

            ScrollView {
                VStack(spacing: 26) {
                    VStack(spacing: 10) {
                        Text("Ce qui pèse vraiment sur votre Mac")
                            .font(.system(size: 30, weight: .semibold, design: .rounded))
                        Text("Commencez par les apps au démarrage et les éléments d'arrière-plan. L'entretien sert quand un problème se présente.")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Button("Toutes les tâches") { navigation.performanceRoute = .maintenance }
                            .buttonStyle(SecondaryButtonStyle())
                            .padding(.top, 6)
                    }
                    .multilineTextAlignment(.center)

                    HStack(alignment: .top, spacing: 16) {
                        maintenanceCard
                        VStack(spacing: 16) {
                            loginItemsCard
                            backgroundCard
                        }
                    }
                }
                .padding(.horizontal, 28)
                .padding(.vertical, 20)
            }
        }
        .task {
            if !launchItems.loginItemsLoaded { await launchItems.loadLoginItems() }
        }
    }

    private var maintenanceCard: some View {
        let recommended = maintenance.recommendedTasks
        let tasks = recommended.isEmpty ? MaintenanceTask.all : recommended
        return PerformanceCard(tint: Theme.lime) {
            VStack(alignment: .leading, spacing: 10) {
                Text(recommended.isEmpty ? localized("Rien à faire pour l'instant") : localized("\(recommended.count) tâche(s) utile(s) en ce moment"))
                    .font(cardTitle)
                Text(maintenanceMessage).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 20)
                HStack(spacing: -12) {
                    ForEach(Array(tasks.prefix(4))) { task in
                        IconTile(symbol: task.icon, tint: Theme.lime, size: 64)
                            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.backgroundBottom))
                    }
                }
                .frame(maxWidth: .infinity)
                Spacer(minLength: 20)
                if let gains = maintenance.lastGains, !maintenance.running {
                    Label(gainSummary(gains), systemImage: "checkmark.seal.fill")
                        .font(.caption.bold())
                        .foregroundColor(Theme.mint)
                }
                HStack {
                    Spacer()
                    Button("Examiner") { navigation.performanceRoute = .maintenance }
                        .buttonStyle(SecondaryButtonStyle())
                    if !recommended.isEmpty {
                        Button(maintenance.running ? localized("En cours…") : localized("Lancer les tâches")) {
                            Task { await maintenance.run(recommended) }
                        }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.lime))
                        .disabled(maintenance.running)
                    }
                }
            }
        }
        .frame(minHeight: 400)
    }

    /// Pas de routine hebdomadaire : on ne conseille une tâche que si une mesure la justifie.
    private var maintenanceMessage: String {
        if !maintenance.recommendedTasks.isEmpty {
            return localized("macOS signale une mémoire sous tension : la libérer peut aider le temps de finir ce que vous faites.")
        }
        return localized("macOS gère seul la mémoire et le cache DNS. Ces outils servent quand un problème se présente : un site qui ne charge plus, Spotlight qui ne trouve rien, des doublons dans « Ouvrir avec ».")
    }

    private func gainSummary(_ gains: MaintenanceGains) -> String {
        var parts = [localized("\(gains.succeeded)/\(gains.total) tâche(s) réussie(s)")]
        if gains.memoryFreed > 0 { parts.append(localized("\(gains.memoryFreed.formattedBytes) de mémoire libérés")) }
        let disk = gains.diskRecovered + gains.mailCompacted
        if disk > 0 { parts.append(localized("\(disk.formattedBytes) récupérés")) }
        return parts.joined(separator: " · ")
    }

    private var loginItemsCard: some View {
        let items = launchItems.loginItems
        let title: String
        let message: String
        if !launchItems.loginItemsReadable {
            title = localized("Apps au démarrage")
            message = localized("Autorisez TidyMyMac à utiliser « Événements système » (Réglages › Confidentialité › Automatisation) pour les afficher.")
        } else if items.isEmpty {
            title = localized("Aucune app au démarrage")
            message = localized("Votre session s'ouvre sans lancer d'application : rien à faire ici.")
        } else {
            title = localized("\(items.count) app(s) au démarrage")
            message = localized("Elles s'ouvrent à chaque ouverture de session et rallongent le démarrage. Gardez seulement celles qui vous servent tout de suite.")
        }
        return PerformanceCard(tint: Theme.sky) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title).font(cardTitle)
                        Text(message).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if items.isEmpty {
                        IconTile(symbol: "person.crop.circle.badge.checkmark", tint: Theme.sky, size: 52)
                    } else {
                        HStack(spacing: -14) {
                            ForEach(items.prefix(3)) { item in
                                AppIcon(path: item.path, fallback: "app.fill", tint: Theme.sky, size: 48)
                            }
                        }
                    }
                }
                Spacer(minLength: 8)
                HStack {
                    Spacer()
                    Button("Examiner") { navigation.performanceRoute = .loginItems }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }

    private var backgroundCard: some View {
        let broken = launchItems.brokenCount
        return PerformanceCard(tint: Theme.lavender) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("\(launchItems.items.count) élément(s) d'arrière-plan").font(cardTitle)
                        Text(broken > 0
                             ? localized("Dont \(broken) qui pointe(nt) vers un programme disparu : vous pouvez les supprimer sans risque.")
                             : localized("Agents et services lancés en coulisses par vos apps. Vérifiez qu'ils vous servent encore."))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    IconTile(symbol: "gearshape.2.fill", tint: broken > 0 ? Theme.amber : Theme.lavender, size: 52)
                }
                Spacer(minLength: 8)
                HStack {
                    Spacer()
                    Button("Examiner") { navigation.performanceRoute = .backgroundItems }
                        .buttonStyle(SecondaryButtonStyle())
                }
            }
        }
    }
}

private struct PerformanceCard<Content: View>: View {
    let tint: Color
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(22)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LinearGradient(colors: [tint.opacity(0.16), Theme.card], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

/// Icône de l'app à `path`, ou une tuile de repli.
private struct AppIcon: View {
    let path: String?
    let fallback: String
    let tint: Color
    var size: CGFloat = 32

    var body: some View {
        if let path, FileManager.default.fileExists(atPath: path) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                .resizable()
                .frame(width: size, height: size)
        } else {
            IconTile(symbol: fallback, tint: tint, size: size)
        }
    }
}

// MARK: - Gestionnaires

private final class ManagerState<ID: Hashable>: ObservableObject {
    @Published var search = ""
    @Published var sortByName = true
    @Published var selection: Set<ID> = []
    @Published var confirming = false

    func toggle(_ id: ID) {
        if selection.contains(id) {
            selection.remove(id)
        } else {
            selection.insert(id)
        }
    }
}

private struct ManagerHeader: View {
    let heading: String
    let description: String
    let onBack: () -> Void
    var search: Binding<String>?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Button(action: onBack) { Label("Retour", systemImage: "chevron.left") }
                    .buttonStyle(.borderless)
                Spacer()
                if let search {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass").foregroundColor(.secondary)
                        TextField("Rechercher", text: search).textFieldStyle(.plain)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .frame(width: 200)
                    .background(Capsule().fill(Theme.card))
                    .overlay(Capsule().strokeBorder(Theme.cardBorder))
                }
            }
            .overlay(Text("Performances").font(.system(.headline, design: .rounded)).foregroundColor(.secondary))
            .padding(.top, 34)
            .padding(.bottom, 18)
            Text(heading).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(description)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 4)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 12)
    }
}

/// Barre du bas : nombre d'éléments sélectionnés au centre, action à droite.
private struct SelectionFooter: View {
    let count: Int
    let message: String?
    let actionTitle: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        HStack {
            if let message {
                Label(message, systemImage: "checkmark.seal.fill")
                    .font(.caption.bold())
                    .foregroundColor(Theme.mint)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(PrimaryButtonStyle(tint: tint))
                .disabled(count == 0)
        }
        .overlay(Text(count == 0 ? localized("Aucun élément sélectionné") : localized("\(count) élément(s) sélectionné(s)")).foregroundColor(.secondary))
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.18))
    }
}

private struct BackgroundItemsManager: View {
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var model: LaunchItemsModel
    @StateObject private var state = ManagerState<URL>()

    private var visibleItems: [LaunchItem] {
        let query = state.search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? model.items : model.items.filter {
            $0.displayName.localizedCaseInsensitiveContains(query) || $0.label.localizedCaseInsensitiveContains(query)
        }
        if state.sortByName {
            return filtered.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        }
        return filtered.sorted { ($0.isBroken ? 0 : 1, $0.scope.order, $0.displayName) < ($1.isBroken ? 0 : 1, $1.scope.order, $1.displayName) }
    }

    private var selectedItems: [LaunchItem] { model.items.filter { state.selection.contains($0.url) } }

    var body: some View {
        VStack(spacing: 0) {
            ManagerHeader(
                heading: localized("Éléments d'arrière-plan"),
                description: localized("Agents et services que vos apps lancent en coulisses. Ceux qui pointent vers un programme disparu peuvent être supprimés sans risque."),
                onBack: { navigation.performanceRoute = .overview },
                search: $state.search
            )
            HStack {
                Menu("Sélectionner") {
                    Button("Les éléments cassés") { state.selection = Set(model.items.filter(\.isBroken).map(\.url)) }
                    Button("Tout") { state.selection = Set(visibleItems.map(\.url)) }
                    Button("Aucun") { state.selection = [] }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Picker("Trier par", selection: $state.sortByName) {
                    Text("Nom").tag(true)
                    Text("État et type").tag(false)
                }
                .pickerStyle(.menu)
                .fixedSize()
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 6)
            List(visibleItems) { item in
                row(item)
            }
            SelectionFooter(count: state.selection.count, message: model.lastActionMessage, actionTitle: localized("Supprimer…"), tint: Theme.coral) {
                state.confirming = true
            }
        }
        .confirmationDialog("Supprimer \(state.selection.count) élément(s) d'arrière-plan ?", isPresented: $state.confirming) {
            Button("Supprimer", role: .destructive) {
                let targets = selectedItems
                state.selection = []
                Task { await model.remove(targets) }
            }
        } message: {
            Text("Ils sont arrêtés et leur fichier de configuration est supprimé. Les éléments globaux et système demandent le mot de passe administrateur.")
        }
    }

    private func row(_ item: LaunchItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(get: { state.selection.contains(item.url) }, set: { _ in state.toggle(item.url) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
            AppIcon(path: item.appURL?.path, fallback: "gearshape.fill", tint: Theme.lavender, size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.displayName).font(.system(.body, design: .rounded).weight(.medium)).lineLimit(1)
                Text(item.label).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if item.isBroken {
                Badge(text: "Programme introuvable", tint: Theme.amber)
            }
            Badge(text: item.scope.title, tint: Color(white: 0.7))
            Button { FS.reveal(item.url) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help("Afficher dans le Finder")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { state.toggle(item.url) }
    }
}

private struct LoginItemsManager: View {
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var model: LaunchItemsModel
    @StateObject private var state = ManagerState<String>()

    private var visibleItems: [LoginItem] {
        let query = state.search.trimmingCharacters(in: .whitespaces)
        let filtered = query.isEmpty ? model.loginItems : model.loginItems.filter { $0.name.localizedCaseInsensitiveContains(query) }
        return filtered.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(spacing: 0) {
            ManagerHeader(
                heading: localized("Apps au démarrage"),
                description: localized("Ces apps s'ouvrent automatiquement à chaque ouverture de session. Les retirer ne les désinstalle pas : vous pourrez toujours les lancer vous-même."),
                onBack: { navigation.performanceRoute = .overview },
                search: $state.search
            )
            HStack {
                Menu("Sélectionner") {
                    Button("Tout") { state.selection = Set(visibleItems.map(\.id)) }
                    Button("Aucun") { state.selection = [] }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Spacer()
                Button("Réglages Système…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 6)
            if !model.loginItemsReadable {
                StartPrompt(
                    text: "macOS n'autorise pas encore TidyMyMac à lire cette liste. Activez « Événements système » pour TidyMyMac dans Réglages › Confidentialité et sécurité › Automatisation.",
                    buttonTitle: "Ouvrir les réglages"
                ) {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
                        NSWorkspace.shared.open(url)
                    }
                }
            } else if model.loginItems.isEmpty {
                StartPrompt(text: "Aucune app ne s'ouvre au démarrage.", buttonTitle: "Actualiser") {
                    Task { await model.loadLoginItems() }
                }
            } else {
                List(visibleItems) { item in
                    HStack(spacing: 12) {
                        Toggle("", isOn: Binding(get: { state.selection.contains(item.id) }, set: { _ in state.toggle(item.id) }))
                            .toggleStyle(.checkbox)
                            .labelsHidden()
                        AppIcon(path: item.path, fallback: "app.fill", tint: Theme.sky, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(.system(.body, design: .rounded).weight(.medium))
                            if let path = item.path {
                                Text(path.abbreviatingHome).font(.caption).foregroundColor(.secondary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                    .onTapGesture { state.toggle(item.id) }
                }
            }
            SelectionFooter(count: state.selection.count, message: model.lastActionMessage, actionTitle: localized("Retirer du démarrage"), tint: Theme.sky) {
                let targets = model.loginItems.filter { state.selection.contains($0.id) }
                state.selection = []
                Task { await model.removeLoginItems(targets) }
            }
        }
    }
}

private struct MaintenanceManager: View {
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var model: MaintenanceModel

    var body: some View {
        VStack(spacing: 0) {
            ManagerHeader(
                heading: localized("Tâches d'entretien"),
                description: localized("Cochez les tâches à lancer. Celles marquées d'un cadenas demandent le mot de passe administrateur, une seule fois pour toutes."),
                onBack: { navigation.performanceRoute = .overview }
            )
            if let gains = model.lastGains {
                HStack(spacing: 12) {
                    GainTile(icon: "memorychip", value: gains.memoryFreed.formattedGain, label: "Mémoire libérée", tint: Theme.lime)
                    GainTile(
                        icon: "internaldrive", value: (gains.diskRecovered + gains.mailCompacted).formattedGain,
                        label: "Espace disque récupéré", tint: Theme.sky
                    )
                    GainTile(
                        icon: "checkmark.circle", value: localized("\(gains.succeeded)/\(gains.total)"),
                        label: "Tâches réussies", tint: gains.succeeded == gains.total ? Theme.mint : Theme.amber
                    )
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 12)
            }
            List(MaintenanceTask.all) { task in
                HStack(spacing: 12) {
                    Toggle("", isOn: Binding(
                        get: { model.selected.contains(task.id) },
                        set: { isOn in
                            if isOn { model.selected.insert(task.id) } else { model.selected.remove(task.id) }
                        }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    IconTile(symbol: task.icon, tint: Theme.lime, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 6) {
                            Text(task.title).font(.system(.body, design: .rounded).weight(.medium))
                            if task.needsAdmin {
                                Image(systemName: "lock.fill").font(.caption).foregroundColor(.secondary)
                                    .help("Demande le mot de passe administrateur")
                            }
                        }
                        Text(task.detail).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    status(for: task)
                }
                .padding(.vertical, 5)
            }
            SelectionFooter(
                count: model.selected.count,
                message: nil,
                actionTitle: model.running ? localized("En cours…") : localized("Lancer les tâches"),
                tint: Theme.lime
            ) {
                Task { await model.run() }
            }
            .disabled(model.running)
        }
    }

    @ViewBuilder private func status(for task: MaintenanceTask) -> some View {
        if model.runningTasks.contains(task.id) {
            ProgressView().controlSize(.small)
        } else if let outcome = model.outcomes[task.id] {
            HStack(spacing: 6) {
                Text(outcome.message)
                    .font(.system(.caption, design: .rounded).bold())
                    .foregroundColor(outcome.succeeded ? Theme.mint : Theme.coral)
                Image(systemName: outcome.succeeded ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .foregroundColor(outcome.succeeded ? Theme.mint : Theme.coral)
            }
        }
    }
}

private struct Badge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption2.bold())
            .foregroundColor(tint)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(tint.opacity(0.15)))
    }
}
