import AppKit
import SemanticSearch
import SwiftUI

/// Génère les captures d'écran du README avec des données fictives (aucun fichier, nom ou app réels) :
///
///     build/TidyMyMac.app/Contents/MacOS/TidyMyMac --screenshots docs/screenshots
///
/// Chaque écran est dessiné dans une fenêtre placée hors de l'écran : aucune autorisation
/// d'enregistrement de l'écran n'est nécessaire.
///
/// `--language <fr|en|es|de>` change la langue pendant l'exécution, sans relancer l'app (et sans l'enregistrer).
/// `--app-icon <fichier.png>` exporte l'icône de l'app en 1024 × 1024 (voir scripts/make-icon.sh).
@MainActor
enum ScreenshotStudio {
    static var isActive: Bool {
        CommandLine.arguments.contains("--screenshots") || CommandLine.arguments.contains("--app-icon")
    }

    private static let windowSize = CGSize(width: 1200, height: 760)

    static func run() {
        let arguments = CommandLine.arguments
        if let flag = arguments.firstIndex(of: "--app-icon"), flag + 1 < arguments.count {
            exportAppIcon(to: URL(fileURLWithPath: arguments[flag + 1]))
        }
        // Langue demandée, sinon celle du lancement (-AppleLanguages), jamais celle enregistrée dans les Réglages.
        let requested = arguments.firstIndex(of: "--language").flatMap { flag in
            flag + 1 < arguments.count ? AppLanguage(rawValue: arguments[flag + 1]) : nil
        }
        let launched = AppLanguage(rawValue: Bundle.main.preferredLocalizations.first ?? "")
        AppLocalization.shared.apply(requested ?? launched ?? .en, persist: false)
        // Total fictif, en mémoire seulement : les captures ne montrent pas les chiffres de ce Mac.
        var argumentDomain = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        argumentDomain[Stats.totalFreedKey] = 48_600_000_000
        UserDefaults.standard.setVolatileDomain(argumentDomain, forName: UserDefaults.argumentDomain)
        guard let flag = arguments.firstIndex(of: "--screenshots"), flag + 1 < arguments.count else {
            print("Usage : TidyMyMac --screenshots <dossier>")
            exit(1)
        }
        let directory = URL(fileURLWithPath: arguments[flag + 1])
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let scenes: [(name: String, module: Module)] = [
            ("01-quick-check", .smartScan),
            ("02-junk-files", .junk),
            ("03-space-explorer", .spaceExplorer),
            ("04-performance", .performance),
            ("05-ai-search", .search),
            ("09-rules", .rules),
            ("10-history", .history),
            ("13-how-it-works", .howItWorks),
        ]
        for scene in scenes {
            let demo = DemoModels()
            save(capture(demo.window(scene.module), size: windowSize), framed: true, to: directory, name: scene.name)
        }

        let monitor = SystemMonitor()
        monitor.showDemo()
        let demo = DemoModels()
        save(capture(StatusPanel()
            .environmentObject(monitor)
            .environmentObject(demo.navigation)
            .environmentObject(demo.updates)
            .environmentObject(demo.search), size: nil), framed: false, to: directory, name: "06-menu-bar")
        save(capture(SettingsView().environmentObject(demo.updates), size: nil), framed: true, to: directory, name: "07-settings")
        save(capture(DemoModels().cleanupDone(), size: windowSize), framed: true, to: directory, name: "11-undo")
        save(capture(DemoModels().cleanupPlan(), size: nil), framed: true, to: directory, name: "12-cleanup-plan")
        if let rule = RuleBook.load().builtIn.first(where: { $0.id == "installers" }) {
            save(capture(RuleDetails(rule: rule).background(Theme.backgroundTop), size: nil),
                 framed: false, to: directory, name: "08-rule-details")
        }
        save(capture(AppIconArt().scaleEffect(0.25).frame(width: 256, height: 256), size: nil), framed: nil, to: directory, name: "logo")

        print("Captures enregistrées dans \(directory.path)")
        exit(0)
    }

    private static func exportAppIcon(to url: URL) {
        guard let bitmap = capture(AppIconArt(), size: CGSize(width: 1024, height: 1024)),
              let data = bitmap.representation(using: .png, properties: [:]),
              (try? data.write(to: url)) != nil else {
            print("Échec de l'export de l'icône")
            exit(1)
        }
        print("Icône enregistrée : \(url.path)")
        exit(0)
    }

    // MARK: - Rendu

    private static func capture<V: View>(_ view: V, size: CGSize?) -> NSBitmapImageRep? {
        // Taille imposée : sans cela, la vue s'agrandit pour montrer tout son contenu.
        let hosting = NSHostingView(rootView: view
            .environment(\.locale, AppLocalization.locale)
            .frame(width: size?.width, height: size?.height))
        let target = size ?? hosting.fittingSize
        hosting.sizingOptions = []
        hosting.frame = CGRect(origin: .zero, size: target)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = hosting
        // Fenêtre affichée loin de l'écran visible, pour un rendu complet.
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(0.8))
        hosting.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        defer { window.orderOut(nil) }
        guard let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        return bitmap
    }

    /// `framed` : `true` ajoute les boutons de fenêtre, `false` seulement les coins arrondis et l'ombre, `nil` rien.
    private static func save(_ bitmap: NSBitmapImageRep?, framed: Bool?, to directory: URL, name: String) {
        guard let bitmap, let image = bitmap.cgImage else {
            print("Échec de la capture : \(name)")
            return
        }
        let output = framed.map { frame(image, scale: CGFloat(bitmap.pixelsWide) / bitmap.size.width, trafficLights: $0) } ?? image
        guard let output, let data = NSBitmapImageRep(cgImage: output).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Coins arrondis, fine bordure, ombre portée et, pour une fenêtre, les trois boutons de macOS.
    private static func frame(_ image: CGImage, scale: CGFloat, trafficLights: Bool) -> CGImage? {
        let margin = 40 * scale
        let rect = CGRect(x: margin, y: margin, width: CGFloat(image.width), height: CGFloat(image.height))
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: image.width + Int(margin * 2), height: image.height + Int(margin * 2),
                  bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }
        let radius = (trafficLights ? 12 : 14) * scale
        let outline = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)

        context.saveGState()
        context.setShadow(offset: CGSize(width: 0, height: -14 * scale), blur: 32 * scale, color: CGColor(gray: 0, alpha: 0.4))
        context.addPath(outline)
        context.setFillColor(CGColor(gray: 0.1, alpha: 1))
        context.fillPath()
        context.restoreGState()

        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.draw(image, in: rect)
        context.restoreGState()

        context.addPath(outline)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.14))
        context.setLineWidth(scale)
        context.strokePath()

        if trafficLights {
            let colors: [(CGFloat, CGFloat, CGFloat)] = [(1.0, 0.37, 0.34), (1.0, 0.74, 0.18), (0.16, 0.78, 0.25)]
            for (index, color) in colors.enumerated() {
                let center = CGPoint(x: rect.minX + (20 + CGFloat(index) * 20) * scale, y: rect.maxY - 20 * scale)
                context.setFillColor(CGColor(red: color.0, green: color.1, blue: color.2, alpha: 1))
                context.fillEllipse(in: CGRect(x: center.x - 6 * scale, y: center.y - 6 * scale, width: 12 * scale, height: 12 * scale))
            }
        }
        return context.makeImage()
    }
}

/// Des modèles remplis de données fictives, un jeu par capture.
@MainActor
private final class DemoModels {
    let navigation = AppNavigation()
    let junk = JunkModel()
    let rules = RulesModel()
    let apps = AppsModel()
    let largeFiles = LargeFilesModel()
    let duplicates = DuplicatesModel()
    let spaceExplorer = SpaceExplorerModel()
    let maintenance = MaintenanceModel()
    let launchItems = LaunchItemsModel()
    let search = SmartSearchModel()
    let updates = UpdateChecker()

    private static let gigabyte: Int64 = 1_000_000_000

    /// Plan de nettoyage des fichiers inutiles fictifs.
    func cleanupPlan() -> some View {
        fillJunk()
        return CleanupPlanSheet(model: junk) {}
    }

    /// Écran de fin d'un nettoyage, avec « Annuler ce nettoyage ».
    func cleanupDone() -> some View {
        ActivityJournal.shared.showDemo()
        junk.lastEntryID = ActivityJournal.shared.entries.first?.id
        junk.phase = .done(freed: 13_100_000_000)
        return window(.junk, prepare: false)
    }

    func window(_ module: Module, prepare: Bool = true) -> some View {
        navigation.selection = module
        switch prepare ? module : nil {
        case .junk: fillJunk()
        case .rules: rules.showDemo()
        case .history: ActivityJournal.shared.showDemo()
        case .spaceExplorer: fillSpaceExplorer()
        case .performance: fillPerformance()
        case .search: fillSearch()
        default: break
        }
        return ContentView()
            .environmentObject(navigation)
            .environmentObject(junk)
            .environmentObject(rules)
            .environmentObject(apps)
            .environmentObject(largeFiles)
            .environmentObject(duplicates)
            .environmentObject(spaceExplorer)
            .environmentObject(maintenance)
            .environmentObject(launchItems)
            .environmentObject(search)
            .environmentObject(updates)
    }

    private func home(_ path: String) -> URL {
        FS.home.appendingPathComponent(path)
    }

    private func fillJunk() {
        let rules = Dictionary(uniqueKeysWithValues: RuleBook.load().builtIn.map { ($0.id, $0) })
        func result(_ id: String, _ entries: [(String, Double)], selected: Bool = true) -> JunkResult? {
            guard let rule = rules[id] else { return nil }
            let items = entries.map { ScanItem(url: home($0.0), size: Int64($0.1 * Double(Self.gigabyte)), selected: selected) }
            return JunkResult(rule: rule, items: items)
        }
        junk.results = [
            result("xcode-derived", [("Library/Developer/Xcode/DerivedData/MyApp-dkqf", 6.8), ("Library/Developer/Xcode/DerivedData/Widget-aebc", 1.9)]),
            result("device-support", [("Library/Developer/Xcode/iOS DeviceSupport/17.5 (21F79)", 3.9)]),
            result("user-caches", [("Library/Caches/com.example.browser", 2.4), ("Library/Caches/Homebrew", 0.86), ("Library/Caches/com.example.music", 1.1)]),
            result("trash", [(".Trash/Old project", 2.7)]),
            result("dev-caches", [(".npm/_cacache", 1.3)]),
            result("user-logs", [("Library/Logs/DiagnosticReports", 0.42)]),
            result("mail-downloads", [("Library/Containers/com.apple.mail/Data/Library/Mail Downloads/Quote", 0.31)], selected: false),
            result("installers", [("Downloads/Installer.dmg", 1.2)], selected: false),
        ].compactMap { $0 }
        junk.phase = .ready
    }

    private func fillSpaceExplorer() {
        let entries: [(String, Double, Bool)] = [
            ("Movies", 182, true), ("Pictures", 96, true), ("Documents", 41, true), ("Library", 38, true),
            ("Downloads", 27, true), ("Music", 12, true), ("Developer", 9.4, true), ("Final edit.mov", 6.1, false),
            ("Desktop", 4.2, true), ("Archive 2023.zip", 3.2, false), ("Projects", 2.6, true), ("Public", 0.4, true),
        ]
        spaceExplorer.current = FS.home
        spaceExplorer.displayMode = .bubbles
        spaceExplorer.entries = entries
            .map { SizedEntry(url: home($0.0), size: Int64($0.1 * Double(Self.gigabyte)), isDirectory: $0.2) }
            .sorted { $0.size > $1.size }
        spaceExplorer.hovered = home("Movies").path
    }

    private func fillPerformance() {
        func agent(_ label: String, _ program: String, _ scope: LaunchItem.Scope, broken: Bool = false) -> LaunchItem {
            LaunchItem(url: URL(fileURLWithPath: "\(scope.directory.path)/\(label).plist"), label: label,
                       program: program, scope: scope, isBroken: broken)
        }
        launchItems.items = [
            agent("com.example.sync.agent", "/Applications/Sync.app/Contents/MacOS/SyncAgent", .userAgent),
            agent("com.example.updater", "/Applications/Old Tool.app/Contents/MacOS/Updater", .userAgent, broken: true),
            agent("com.example.cloud.helper", "/Applications/Cloud.app/Contents/Helpers/CloudHelper", .systemAgent),
            agent("com.example.vpn.daemon", "/Library/PrivilegedHelperTools/com.example.vpn", .systemDaemon),
            agent("com.example.license", "/Library/Application Support/Removed/license", .systemDaemon, broken: true),
            agent("com.example.backup", "/Applications/Backup.app/Contents/MacOS/BackupAgent", .userAgent),
        ]
        launchItems.loaded = true
        launchItems.loginItems = [
            LoginItem(name: "Calendar", path: "/System/Applications/Calendar.app"),
            LoginItem(name: "Notes", path: "/System/Applications/Notes.app"),
            LoginItem(name: "Reminders", path: "/System/Applications/Reminders.app"),
        ]
        launchItems.loginItemsLoaded = true
        launchItems.loginItemsReadable = true
        maintenance.lastGains = MaintenanceGains(memoryFreed: 2_100_000_000, succeeded: 2, total: 2)
        navigation.performanceRoute = .overview
    }

    private func fillSearch() {
        let now = Date()
        func hit(_ path: String, relevance: Double, days: Double, _ snippet: String) -> SearchHit {
            SearchHit(url: home(path), score: Float(0.75 + relevance * 0.2), relevance: relevance,
                      snippet: snippet, modified: now.addingTimeInterval(-days * 86_400))
        }
        search.showDemo(query: "Find my liability insurance certificate", results: [
            hit("Documents/Insurance/Liability_Certificate_2025.pdf", relevance: 0.96, days: 34,
                "CERTIFICATE OF INSURANCE — Personal liability. We certify that the policyholder is covered for the period from January 1 to December 31, 2025."),
            hit("Downloads/Scan_0042.pdf", relevance: 0.81, days: 210,
                "Policy schedule: personal liability cover for damage caused to third parties by the insured and members of their household."),
            hit("Documents/Insurance/Home insurance policy.pdf", relevance: 0.48, days: 400,
                "Home insurance policy: fire, water damage, theft and occupier's liability."),
            hit("Documents/Health/Health plan 2025.pdf", relevance: 0.22, days: 60,
                "Summary of benefits for the 2025 health insurance plan."),
            hit("Documents/Bills/Electricity January.pdf", relevance: 0.06, days: 25,
                "Electricity bill: January usage, amount due by February 15."),
        ], documentCount: 1_284)
    }
}
