import AppKit
import SemanticSearch
import SwiftUI

struct StatusPanel: View {
    @EnvironmentObject var monitor: SystemMonitor
    @EnvironmentObject var navigation: AppNavigation
    @EnvironmentObject var updates: UpdateChecker
    @EnvironmentObject var search: SmartSearchModel
    @Environment(\.openWindow) private var openWindow

    /// Les résultats remplacent les cartes de mesures, pour garder un panneau compact.
    private var showingResults: Bool { search.searchedQuery != nil && !search.query.isEmpty }

    var body: some View {
        VStack(spacing: 12) {
            header
            searchBar
            if showingResults {
                searchResults
            } else {
                Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                    GridRow {
                        diskCard
                        memoryCard
                    }
                    GridRow {
                        cpuCard
                        batteryCard
                    }
                    GridRow {
                        networkCard.gridCellColumns(2)
                    }
                    GridRow {
                        volumesCard.gridCellColumns(2)
                    }
                }
            }
            footer
        }
        .padding(14)
        .frame(width: 390)
        .background(
            LinearGradient(colors: [Theme.backgroundTop, Theme.backgroundBottom], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .environment(\.colorScheme, .dark)
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    // MARK: - En-tête

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            BrandMark()
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("État du Mac").font(.system(size: 17, weight: .bold, design: .rounded))
                    healthPill
                }
                Text(systemSubtitle).font(.caption).foregroundColor(.secondary)
                ForEach(monitor.issues, id: \.self) { issue in
                    Label(issue, systemImage: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(Theme.amber)
                }
                if let release = updates.availableRelease {
                    Button {
                        openWindow(id: "main")
                        NSApp.activate(ignoringOtherApps: true)
                        updates.showDetails = true
                    } label: {
                        Label("Version \(release.version.raw) disponible", systemImage: "arrow.down.circle.fill")
                            .font(.caption.bold())
                            .foregroundColor(Theme.mint)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 4)
    }

    private var healthPill: some View {
        let (text, color): (String, Color) = {
            switch monitor.health {
            case .good: return (localized("Tout va bien"), Theme.mint)
            case .watch: return (localized("À surveiller"), Theme.amber)
            case .critical: return (localized("Critique"), Theme.coral)
            }
        }()
        return Text(text)
            .font(.caption.bold())
            .foregroundColor(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.opacity(0.15)))
    }

    private var systemSubtitle: String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let system = "macOS \(version.majorVersion).\(version.minorVersion)"
        return localized("\(system) · actif depuis \(formatDuration(ProcessInfo.processInfo.systemUptime))")
    }

    // MARK: - Recherche IA

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.magnifyingglass").foregroundColor(Theme.peach)
            TextField("Rechercher un document, ex. « mon assurance RC »", text: $search.query)
                .textFieldStyle(.plain)
                .onSubmit(runSearch)
            if search.searching {
                ProgressView().controlSize(.small)
            } else if !search.query.isEmpty {
                Button { search.clearResults() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .help("Effacer")
            }
            Image(systemName: "lock.shield.fill")
                .foregroundColor(Theme.mint)
                .help("Recherche entièrement locale : vos fichiers et vos recherches ne sont envoyés à aucun serveur.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.peach.opacity(0.35)))
    }

    /// Recherche sur place si le modèle et l'index sont prêts ; sinon, ouvre la Recherche IA pour les préparer.
    private func runSearch() {
        Task {
            await search.prepare()
            guard search.modelState == .ready, search.hasIndex else {
                open(.search)
                return
            }
            await search.search()
        }
    }

    private var searchResults: some View {
        PanelCard(title: "Documents trouvés", icon: "text.magnifyingglass") {
            if search.results.isEmpty {
                Text("Aucun document ne correspond.").font(.caption).foregroundColor(.secondary)
            } else {
                VStack(spacing: 4) {
                    ForEach(search.results.prefix(6)) { hit in
                        resultRow(hit)
                    }
                }
            }
            HStack {
                Label("Traité sur ce Mac, rien n'est envoyé", systemImage: "lock.shield.fill")
                    .font(.caption2)
                    .foregroundColor(Theme.mint)
                Spacer()
                PanelAction(title: "Tous les résultats") { open(.search) }
            }
        }
    }

    private func resultRow(_ hit: SearchHit) -> some View {
        let relevance = hit.relevance
        return Button { NSWorkspace.shared.open(hit.url) } label: {
            HStack(spacing: 10) {
                Image(nsImage: FS.icon(for: hit.url))
                    .resizable()
                    .frame(width: 26, height: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(hit.url.lastPathComponent)
                        .font(.system(.callout, design: .rounded).weight(.medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(hit.url.deletingLastPathComponent().path.abbreviatingHome)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                Circle()
                    .fill(relevance >= 0.7 ? Theme.mint : relevance >= 0.35 ? Theme.peach : Color(white: 0.5))
                    .frame(width: 8, height: 8)
                    .help(relevance >= 0.7
                          ? localized("Très pertinent")
                          : relevance >= 0.35 ? localized("Pertinent") : localized("Peu pertinent"))
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Ouvrir") { NSWorkspace.shared.open(hit.url) }
            Button("Afficher dans le Finder") { FS.reveal(hit.url) }
        }
    }

    // MARK: - Cartes

    private var diskCard: some View {
        let fraction = monitor.disk?.usedFraction ?? 0
        return PanelCard(title: "Disque", icon: "internaldrive") {
            HStack(spacing: 12) {
                RingGauge(value: fraction, tint: Theme.level(fraction))
                VStack(alignment: .leading, spacing: 2) {
                    Text(monitor.disk?.free.formattedBytes ?? "–").font(.system(.body, design: .rounded).bold()).monospacedDigit()
                    Text("disponibles").font(.caption).foregroundColor(.secondary)
                }
            }
            PanelAction(title: "Nettoyer") { open(.junk) }
        }
    }

    private var memoryCard: some View {
        let fraction = monitor.memoryFraction
        return PanelCard(title: "Mémoire", icon: "memorychip") {
            HStack(spacing: 12) {
                RingGauge(value: fraction, tint: Theme.level(fraction))
                VStack(alignment: .leading, spacing: 2) {
                    Text(Int64(monitor.memoryUsed).formattedBytes).font(.system(.body, design: .rounded).bold()).monospacedDigit()
                    Text(pressureLabel).font(.caption).foregroundColor(.secondary)
                }
            }
            HStack(spacing: 8) {
                if monitor.memoryFreeing {
                    ProgressView().controlSize(.small)
                } else {
                    PanelAction(title: "Libérer") { monitor.freeMemory() }
                }
                if let gain = monitor.memoryGainText {
                    Text(gain).font(.caption.bold()).foregroundColor(Theme.mint).lineLimit(1)
                }
            }
        }
    }

    private var cpuCard: some View {
        PanelCard(title: "Processeur", icon: "cpu") {
            HStack(spacing: 12) {
                RingGauge(value: monitor.cpuLoad, tint: Theme.level(monitor.cpuLoad))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Charge").font(.system(.body, design: .rounded).bold())
                    Text(thermalLabel).font(.caption).foregroundColor(.secondary)
                }
            }
        }
    }

    @ViewBuilder private var batteryCard: some View {
        if let battery = monitor.battery {
            let fraction = Double(battery.percent) / 100
            PanelCard(title: "Batterie", icon: battery.isCharging ? "battery.100.bolt" : "battery.75") {
                HStack(spacing: 12) {
                    RingGauge(value: fraction, tint: fraction < 0.2 ? Theme.coral : Theme.mint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(batteryHeadline(battery)).font(.system(.body, design: .rounded).bold())
                        Text(batteryDetail(battery)).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
        } else {
            PanelCard(title: "Alimentation", icon: "powerplug") {
                Text("Sur secteur").font(.system(.body, design: .rounded).bold())
            }
        }
    }

    private var networkCard: some View {
        PanelCard(title: "Réseau", icon: "wifi") {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Label(rate(monitor.downloadRate), systemImage: "arrow.down")
                    Label(rate(monitor.uploadRate), systemImage: "arrow.up").foregroundColor(.secondary)
                }
                .font(.system(.callout, design: .rounded).monospacedDigit())
                .frame(width: 110, alignment: .leading)
                Sparkline(values: monitor.downloadHistory, tint: Theme.mint)
                    .frame(height: 34)
            }
            HStack {
                speedTestResult
                Spacer()
                PanelAction(title: "Tester le débit") { monitor.runSpeedTest() }
                    .disabled(monitor.speedTest == .running)
            }
        }
    }

    @ViewBuilder private var speedTestResult: some View {
        switch monitor.speedTest {
        case .idle:
            EmptyView()
        case .running:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Mesure en cours…").font(.caption).foregroundColor(.secondary)
            }
        case .finished(let download, let upload):
            Text("↓ \(Int(download)) Mbit/s · ↑ \(Int(upload)) Mbit/s").font(.caption.bold()).foregroundColor(Theme.mint)
        case .failed:
            Text("Test impossible").font(.caption).foregroundColor(Theme.coral)
        }
    }

    private var volumesCard: some View {
        PanelCard(title: "Volumes connectés", icon: "externaldrive") {
            if monitor.volumes.isEmpty {
                Text("Aucun disque externe ni image disque").font(.caption).foregroundColor(.secondary)
            } else {
                ForEach(monitor.volumes) { volume in
                    HStack {
                        Text(volume.name).lineLimit(1)
                        Spacer()
                        Text("\(volume.free.formattedBytes) libres").font(.caption).foregroundColor(.secondary).monospacedDigit()
                        Button { monitor.eject(volume) } label: { Image(systemName: "eject.fill") }
                            .buttonStyle(.borderless)
                            .help("Éjecter")
                    }
                }
            }
        }
    }

    // MARK: - Pied

    private var footer: some View {
        HStack(spacing: 8) {
            Button { open(.smartScan) } label: {
                Text("Ouvrir TidyMyMac")
                    .font(.system(.body, design: .rounded).bold())
                    .foregroundColor(Theme.backgroundBottom)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.mint))
            }
            .buttonStyle(.plain)
            FooterIcon(icon: "trash", help: "Vider la Corbeille") {
                Task.detached { Shell.run("/usr/bin/osascript", ["-e", "tell application \"Finder\" to empty trash"]) }
            }
            settingsButton
            FooterIcon(icon: "power", help: "Quitter TidyMyMac") { NSApp.terminate(nil) }
        }
    }

    @ViewBuilder private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink { FooterIconLabel(icon: "gearshape") }
                .buttonStyle(.plain)
                .help("Réglages")
        } else {
            FooterIcon(icon: "gearshape", help: "Réglages") {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
        }
    }

    // MARK: - Aides

    private func open(_ module: Module) {
        navigation.selection = module
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var pressureLabel: String {
        switch monitor.memoryPressure {
        case 4...: return localized("Pression critique")
        case 2...: return localized("Pression élevée")
        default: return localized("Pression normale")
        }
    }

    private var thermalLabel: String {
        switch monitor.thermalState {
        case .nominal: return localized("Température normale")
        case .fair: return localized("Légèrement chaud")
        case .serious: return localized("Chaud")
        case .critical: return localized("Très chaud")
        @unknown default: return localized("Température inconnue")
        }
    }

    private func batteryHeadline(_ battery: BatteryInfo) -> String {
        if battery.isCharging { return localized("En charge") }
        return battery.isPluggedIn ? localized("Branchée") : localized("Sur batterie")
    }

    private func batteryDetail(_ battery: BatteryInfo) -> String {
        guard let minutes = battery.minutesRemaining else {
            return battery.isPluggedIn ? localized("Secteur") : localized("Calcul…")
        }
        let duration = formatDuration(TimeInterval(minutes * 60))
        return battery.isCharging ? localized("Pleine dans \(duration)") : localized("Encore \(duration)")
    }

    private func rate(_ bytesPerSecond: Double) -> String {
        Int64(bytesPerSecond).formattedBytes + "/s"
    }

    /// Durée abrégée dans la langue de l'utilisateur (« 3 j 4 h », « 2 h 15 min », « 3d 4h »…).
    private func formatDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        var calendar = Calendar.current
        calendar.locale = AppLocalization.locale
        formatter.calendar = calendar
        formatter.allowedUnits = seconds >= 86_400 ? [.day, .hour] : [.hour, .minute]
        formatter.maximumUnitCount = 2
        return formatter.string(from: seconds) ?? ""
    }
}

// MARK: - Composants du panneau

private struct PanelCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.system(.subheadline, design: .rounded).bold())
                .foregroundColor(.secondary)
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

private struct PanelAction: View {
    let title: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption.bold())
                .foregroundColor(Theme.mint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().strokeBorder(Theme.mint.opacity(0.5)))
        }
        .buttonStyle(.plain)
    }
}

private struct FooterIconLabel: View {
    let icon: String

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .frame(width: 34, height: 34)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Theme.cardBorder))
    }
}

private struct FooterIcon: View {
    let icon: String
    let help: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) { FooterIconLabel(icon: icon) }
            .buttonStyle(.plain)
            .help(help)
    }
}

struct RingGauge: View {
    let value: Double
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 6)
            Circle()
                .trim(from: 0, to: min(max(value, 0.001), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int((value * 100).rounded()))%")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .frame(width: 46, height: 46)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { geometry in
            let peak = max(values.max() ?? 1, 1)
            let points = values.enumerated().map { index, value in
                CGPoint(
                    x: geometry.size.width * CGFloat(index) / CGFloat(max(values.count - 1, 1)),
                    y: geometry.size.height * (1 - CGFloat(value / peak))
                )
            }
            ZStack {
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: geometry.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last?.x ?? 0, y: geometry.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.35), tint.opacity(0)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
