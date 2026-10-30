import SwiftUI

/// Options de lancement : `--list-rules` (rapport des règles de nettoyage, sans rien supprimer) et
/// `--screenshots <dossier>` (captures du README).
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--list-rules") {
            RuleBook.printReport()
            exit(0)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if ScreenshotStudio.isActive {
            ScreenshotStudio.run()
        }
    }
}

@main
struct TidyMyMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var junk = JunkModel()
    @StateObject private var rules = RulesModel()
    @StateObject private var apps = AppsModel()
    @StateObject private var largeFiles = LargeFilesModel()
    @StateObject private var duplicates = DuplicatesModel()
    @StateObject private var spaceExplorer = SpaceExplorerModel()
    @StateObject private var maintenance = MaintenanceModel()
    @StateObject private var launchItems = LaunchItemsModel()
    @StateObject private var smartSearch = SmartSearchModel()
    @StateObject private var navigation = AppNavigation()
    @StateObject private var monitor = SystemMonitor()
    @StateObject private var updates = UpdateChecker()
    @ObservedObject private var localization = AppLocalization.shared
    @AppStorage("showMenuBarExtra") private var showMenuBarExtra = true

    var body: some Scene {
        // Fenêtre unique : rouvrir depuis la barre des menus la ramène au premier plan.
        Window("TidyMyMac", id: "main") {
            ContentView()
                .environmentObject(navigation)
                .environmentObject(junk)
                .environmentObject(rules)
                .environmentObject(apps)
                .environmentObject(largeFiles)
                .environmentObject(duplicates)
                .environmentObject(spaceExplorer)
                .environmentObject(maintenance)
                .environmentObject(launchItems)
                .environmentObject(smartSearch)
                .environmentObject(updates)
                .followsAppLanguage(localization)
                .frame(minWidth: 1020, minHeight: 640)
                .task { updates.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1120, height: 720)
        Settings {
            SettingsView()
                .environmentObject(updates)
                .followsAppLanguage(localization)
        }
        MenuBarExtra(isInserted: $showMenuBarExtra) {
            StatusPanel()
                .environmentObject(monitor)
                .environmentObject(navigation)
                .environmentObject(updates)
                .environmentObject(smartSearch)
                .followsAppLanguage(localization)
        } label: {
            Image(nsImage: MenuBarIcon.image)
                .accessibilityLabel("TidyMyMac")
        }
        .menuBarExtraStyle(.window)
    }
}

extension View {
    /// Redessine la vue dans la langue choisie dès qu'elle change (les modèles, eux, sont conservés).
    func followsAppLanguage(_ localization: AppLocalization) -> some View {
        environment(\.locale, AppLocalization.locale)
            .id(localization.language)
    }
}

/// Module affiché dans la fenêtre principale, partagé avec le panneau de la barre des menus.
@MainActor
final class AppNavigation: ObservableObject {
    @Published var selection: Module? = .smartScan
    @Published var performanceRoute: PerformanceRoute = .overview
}

enum Module: String, CaseIterable, Identifiable {
    case smartScan, search, junk, rules, largeFiles, duplicates, spaceExplorer, uninstaller, performance, history

    var id: String { rawValue }

    var title: String {
        switch self {
        case .smartScan: return localized("Analyse intelligente")
        case .search: return localized("Recherche IA")
        case .junk: return localized("Fichiers inutiles")
        case .rules: return localized("Règles et profils")
        case .largeFiles: return localized("Gros fichiers")
        case .duplicates: return localized("Doublons")
        case .spaceExplorer: return localized("Explorateur d'espace")
        case .uninstaller: return localized("Désinstallateur")
        case .performance: return localized("Performances")
        case .history: return localized("Historique")
        }
    }

    var icon: String {
        switch self {
        case .smartScan: return "sparkles"
        case .search: return "text.magnifyingglass"
        case .junk: return "trash"
        case .rules: return "slider.horizontal.3"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .duplicates: return "doc.on.doc"
        case .spaceExplorer: return "chart.bar.doc.horizontal"
        case .uninstaller: return "xmark.app"
        case .performance: return "speedometer"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var updates: UpdateChecker

    private var module: Module { navigation.selection ?? .smartScan }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(module)
                .transition(.opacity)
        }
        .animation(.easeInOut(duration: 0.2), value: module)
        .background(AppBackground(accent: module.info.accent).ignoresSafeArea())
        .scrollContentBackground(.hidden)
        .preferredColorScheme(.dark)
        .tint(Theme.mint)
        .sheet(isPresented: $updates.showDetails) {
            UpdateSheet().environmentObject(updates)
        }
    }

    @ViewBuilder private var detail: some View {
        switch module {
        case .smartScan: DashboardView(selection: $navigation.selection)
        case .search: SmartSearchView()
        case .junk: JunkView()
        case .rules: RulesView()
        case .largeFiles: LargeFilesView()
        case .duplicates: DuplicatesView()
        case .spaceExplorer: SpaceExplorerView()
        case .uninstaller: UninstallerView()
        case .performance: PerformanceView()
        case .history: HistoryView()
        }
    }
}
