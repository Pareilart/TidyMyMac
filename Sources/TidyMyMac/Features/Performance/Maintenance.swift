import Foundation

struct MaintenanceTask: Identifiable, Sendable {
    /// Ce que l'on mesure avant et après la tâche pour afficher le gain.
    enum Gauge: Sendable { case none, freeMemory, freeDisk, mailDatabase }

    let id: String
    let title: String
    let detail: String
    let icon: String
    let needsAdmin: Bool
    let gauge: Gauge
    /// Message affiché quand la tâche réussit sans gain mesurable.
    let doneMessage: String
    let command: String

    static var all: [MaintenanceTask] { [
        MaintenanceTask(
            id: "free-ram", title: localized("Libérer la mémoire vive"),
            detail: localized("Vide le cache disque gardé en mémoire (commande purge)."),
            icon: "memorychip", needsAdmin: true, gauge: .freeMemory,
            doneMessage: localized("Mémoire déjà optimisée"),
            command: "/usr/sbin/purge"
        ),
        MaintenanceTask(
            id: "flush-dns", title: localized("Vider le cache DNS"),
            detail: localized("Utile quand un site ne se charge plus après un changement de réseau."),
            icon: "network", needsAdmin: true, gauge: .none,
            doneMessage: localized("Cache DNS vidé"),
            command: "/usr/bin/dscacheutil -flushcache; /usr/bin/killall -HUP mDNSResponder"
        ),
        MaintenanceTask(
            id: "thin-snapshots", title: localized("Libérer l'espace purgeable"),
            detail: localized("Supprime les instantanés locaux Time Machine."),
            icon: "clock.arrow.circlepath", needsAdmin: true, gauge: .freeDisk,
            doneMessage: localized("Aucun instantané à supprimer"),
            command: "/usr/bin/tmutil thinlocalsnapshots / 999999999999 4"
        ),
        MaintenanceTask(
            id: "reindex-spotlight", title: localized("Réindexer Spotlight"),
            detail: localized("Reconstruit l'index de recherche du disque de démarrage. Peut prendre du temps."),
            icon: "magnifyingglass", needsAdmin: true, gauge: .none,
            doneMessage: localized("Réindexation lancée en arrière-plan"),
            command: "/usr/bin/mdutil -E /"
        ),
        MaintenanceTask(
            id: "speed-up-mail", title: localized("Accélérer Mail"),
            detail: localized("Compacte la base des messages (Mail est quitté). Nécessite l'accès complet au disque."),
            icon: "envelope", needsAdmin: false, gauge: .mailDatabase,
            doneMessage: localized("Base déjà compacte"),
            command: #"""
            /usr/bin/osascript -e 'if application "Mail" is running then tell application "Mail" to quit' >/dev/null 2>&1; \
            sleep 2; ok=1; \
            for f in "$HOME"/Library/Mail/V*/MailData/"Envelope Index"; do \
            [ -f "$f" ] && /usr/bin/sqlite3 "$f" vacuum && ok=0; done; exit $ok
            """#
        ),
        MaintenanceTask(
            id: "rebuild-launch-services", title: localized("Reconstruire la base Launch Services"),
            detail: localized("Corrige les doublons du menu « Ouvrir avec »."),
            icon: "list.bullet.rectangle", needsAdmin: false, gauge: .none,
            doneMessage: localized("Base reconstruite"),
            command: "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -r -domain local -domain system -domain user"
        ),
    ] }
}

struct MaintenanceOutcome: Sendable {
    let succeeded: Bool
    let message: String
}

struct MaintenanceGains: Sendable {
    var memoryFreed: Int64 = 0
    var diskRecovered: Int64 = 0
    var mailCompacted: Int64 = 0
    var succeeded = 0
    var total = 0
}

enum MaintenanceRunner {
    /// Exécute les tâches et mesure leur effet. Les tâches administrateur sont groupées
    /// pour ne demander le mot de passe qu'une fois.
    static func execute(_ tasks: [MaintenanceTask]) -> (outcomes: [String: MaintenanceOutcome], gains: MaintenanceGains) {
        var succeeded: [String: Bool] = [:]

        let mailBefore = mailDatabaseSize()
        for task in tasks where !task.needsAdmin {
            succeeded[task.id] = Shell.sh(task.command).status == 0
        }
        let mailAfter = mailDatabaseSize()

        let memoryBefore = SystemMonitor.readFreeMemory() ?? 0
        let diskBefore = DiskInfo.physicallyFree() ?? 0
        let adminTasks = tasks.filter(\.needsAdmin)
        if !adminTasks.isEmpty {
            let script = adminTasks
                .map { "( \($0.command) ) >/dev/null 2>&1 && echo OK:\($0.id) || echo KO:\($0.id)" }
                .joined(separator: "; ")
            let output = Shell.admin(script).output
            for task in adminTasks {
                succeeded[task.id] = output.contains("OK:\(task.id)")
            }
        }
        let memoryAfter = SystemMonitor.readFreeMemory() ?? 0
        let diskAfter = DiskInfo.physicallyFree() ?? 0

        var gains = MaintenanceGains(total: tasks.count)
        var outcomes: [String: MaintenanceOutcome] = [:]
        for task in tasks {
            guard succeeded[task.id] == true else {
                outcomes[task.id] = MaintenanceOutcome(succeeded: false, message: localized("Échec ou annulé"))
                continue
            }
            gains.succeeded += 1
            var message = task.doneMessage
            switch task.gauge {
            case .freeMemory:
                gains.memoryFreed = memoryAfter > memoryBefore ? Int64(memoryAfter - memoryBefore) : 0
                if gains.memoryFreed > 0 { message = localized("\(gains.memoryFreed.formattedBytes) de mémoire libérés") }
            case .freeDisk:
                gains.diskRecovered = max(diskAfter - diskBefore, 0)
                if gains.diskRecovered > 0 { message = localized("\(gains.diskRecovered.formattedBytes) récupérés sur le disque") }
            case .mailDatabase:
                gains.mailCompacted = max(mailBefore - mailAfter, 0)
                if gains.mailCompacted > 0 { message = localized("Base réduite de \(gains.mailCompacted.formattedBytes)") }
            case .none:
                break
            }
            outcomes[task.id] = MaintenanceOutcome(succeeded: true, message: message)
        }
        return (outcomes, gains)
    }

    private static func mailDatabaseSize() -> Int64 {
        FS.children(of: FS.library.appendingPathComponent("Mail"))
            .filter { $0.lastPathComponent.hasPrefix("V") }
            .map { FS.fileSize($0.appendingPathComponent("MailData/Envelope Index")) }
            .reduce(0, +)
    }
}

@MainActor
final class MaintenanceModel: ObservableObject {
    private static let lastRunKey = "lastMaintenanceRun"
    private static let interval: TimeInterval = 7 * 24 * 3600

    @Published var selected: Set<String> = ["free-ram", "flush-dns"]
    @Published var runningTasks: Set<String> = []
    @Published var outcomes: [String: MaintenanceOutcome] = [:]
    @Published var lastGains: MaintenanceGains?
    @Published private(set) var lastRun = UserDefaults.standard.object(forKey: MaintenanceModel.lastRunKey) as? Date

    var running: Bool { !runningTasks.isEmpty }

    /// Un entretien est conseillé s'il n'a jamais été fait ou date de plus d'une semaine.
    var isDue: Bool {
        guard let lastRun else { return true }
        return Date().timeIntervalSince(lastRun) > Self.interval
    }

    var selectedTasks: [MaintenanceTask] { MaintenanceTask.all.filter { selected.contains($0.id) } }

    func run() async {
        let tasks = selectedTasks
        runningTasks = Set(tasks.map(\.id))
        for task in tasks { outcomes[task.id] = nil }
        let result = await Task.detached(priority: .userInitiated) { MaintenanceRunner.execute(tasks) }.value
        outcomes.merge(result.outcomes) { _, new in new }
        lastGains = result.gains
        Stats.record(freed: result.gains.diskRecovered + result.gains.mailCompacted)
        ActivityJournal.shared.record(JournalEntry(
            kind: .maintenance,
            steps: tasks.map { task in
                let outcome = result.outcomes[task.id]
                return JournalStep(title: task.title, detail: outcome?.message, succeeded: outcome?.succeeded == true)
            },
            freed: result.gains.diskRecovered + result.gains.mailCompacted,
            memoryFreed: result.gains.memoryFreed
        ))
        if result.gains.succeeded > 0 {
            lastRun = Date()
            UserDefaults.standard.set(lastRun, forKey: Self.lastRunKey)
        }
        runningTasks = []
    }
}
