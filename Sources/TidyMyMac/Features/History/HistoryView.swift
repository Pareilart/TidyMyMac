import AppKit
import Charts
import SwiftUI
import UniformTypeIdentifiers

extension JournalKind {
    var icon: String {
        switch self {
        case .junk: return "trash"
        case .largeFiles: return "doc.text.magnifyingglass"
        case .duplicates: return "doc.on.doc"
        case .spaceExplorer: return "chart.bar.doc.horizontal"
        case .uninstall: return "xmark.app"
        case .appReset: return "arrow.counterclockwise"
        case .maintenance: return "wrench.and.screwdriver"
        case .memory: return "memorychip"
        case .launchItems: return "gearshape.2"
        case .loginItems: return "person.crop.circle.badge.xmark"
        }
    }

    var tint: Color {
        switch self {
        case .junk: return Theme.aqua
        case .largeFiles: return Theme.amber
        case .duplicates: return Theme.rose
        case .spaceExplorer: return Theme.sky
        case .uninstall, .appReset: return Theme.coral
        case .maintenance, .launchItems, .loginItems: return Theme.lime
        case .memory: return Theme.lavender
        }
    }
}

extension JournalItem.Availability {
    var title: String {
        switch self {
        case .restorable, .occupied, .inTrash: return localized("Dans la Corbeille")
        case .restored: return localized("Remis en place")
        case .trashEmptied: return localized("Corbeille vidée")
        case .deleted: return localized("Supprimé définitivement")
        case .failed: return localized("Non supprimé")
        }
    }

    var icon: String {
        switch self {
        case .restorable, .occupied, .inTrash: return "trash"
        case .restored: return "arrow.uturn.backward"
        case .trashEmptied: return "trash.slash"
        case .deleted: return "xmark.bin"
        case .failed: return "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .restorable, .occupied, .inTrash: return Theme.sky
        case .restored: return Theme.mint
        case .trashEmptied: return Color.gray
        case .deleted: return Theme.coral
        case .failed: return Theme.amber
        }
    }
}

/// Remet en place, depuis la Corbeille, ce qu'une action vient d'y mettre.
struct UndoActionButton: View {
    let entryID: UUID?
    let title: LocalizedStringKey
    var onRestore: () -> Void = {}
    @ObservedObject private var journal = ActivityJournal.shared
    /// Bilan de la dernière restauration, pour l'action concernée seulement.
    @StateObject private var outcome = ViewState<(id: UUID, message: String)?>(nil)

    var body: some View {
        if let outcome = outcome.value, outcome.id == entryID {
            Label(outcome.message, systemImage: "arrow.uturn.backward.circle")
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if let id = entryID, let entry = journal.entry(withID: id), !entry.restorableItems.isEmpty {
            Button {
                outcome.value = (id, journal.restore(id).message)
                onRestore()
            } label: {
                Label(title, systemImage: "arrow.uturn.backward")
            }
        }
    }
}

/// Espace libéré un jour donné, pour le graphique.
private struct DailyGain: Identifiable {
    let day: Date
    let bytes: Int64
    var id: Date { day }
}

/// Écran « Historique » : tout ce que TidyMyMac a fait sur ce Mac.
struct HistoryView: View {
    @ObservedObject private var journal = ActivityJournal.shared
    @AppStorage(Stats.totalFreedKey) private var totalFreed = 0
    // Les captures d'écran montrent le détail de la première action.
    @StateObject private var expanded = ViewState<Set<UUID>>(
        ScreenshotStudio.isActive ? Set(ActivityJournal.shared.entries.prefix(1).map(\.id)) : []
    )
    @StateObject private var confirmClear = ViewState(false)
    /// Garde le bandeau d'annulation affiché avec son bilan après la restauration.
    @StateObject private var undoBannerEntry = ViewState<UUID?>(nil)

    var body: some View {
        VStack(spacing: 0) {
            ModuleHeader(module: .history)
            Divider()
            if journal.entries.isEmpty {
                empty
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        undoBanner
                        summary
                        chart
                        entries
                        privacyNote
                    }
                    .padding(24)
                }
            }
        }
        .confirmationDialog(localized("Effacer tout l'historique ?"), isPresented: $confirmClear.value) {
            Button("Effacer l'historique", role: .destructive) { journal.clear() }
        } message: {
            Text("Seul l'historique est effacé : les fichiers dans la Corbeille et le total libéré ne changent pas.")
        }
    }

    // MARK: Annulation

    /// Dernière action qui a supprimé des éléments.
    private var lastRemoval: JournalEntry? {
        journal.entries.first { !$0.items.isEmpty }
    }

    @ViewBuilder private var undoBanner: some View {
        if let entry = lastRemoval, !entry.restorableItems.isEmpty || undoBannerEntry.value == entry.id {
            HStack(spacing: 12) {
                IconTile(symbol: "arrow.uturn.backward", tint: Theme.sky, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Annuler la dernière suppression").font(.system(.headline, design: .rounded))
                    Text(localized("\(entry.title) · \(entry.date.relativeDescription)"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                UndoActionButton(entryID: entry.id, title: "Tout remettre en place") {
                    undoBannerEntry.value = entry.id
                }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.sky, compact: true))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.sky.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.sky.opacity(0.35)))
        }
    }

    // MARK: Résumé

    private var thisMonth: Int64 {
        let calendar = Calendar.current
        return journal.entries
            .filter { calendar.isDate($0.date, equalTo: Date(), toGranularity: .month) }
            .reduce(0) { $0 + $1.freed }
    }

    private var summary: some View {
        HStack(spacing: 12) {
            GainTile(icon: "chart.line.uptrend.xyaxis", value: Int64(totalFreed).formattedGain, label: "Total avec TidyMyMac", tint: Theme.mint)
            GainTile(icon: "calendar", value: thisMonth.formattedGain, label: "Ce mois-ci", tint: Theme.sky)
            GainTile(icon: "list.bullet.rectangle", value: String(journal.entries.count), label: "Actions enregistrées", tint: Theme.lavender)
        }
    }

    // MARK: Graphique

    private var dailyGains: [DailyGain] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        var totals: [Date: Int64] = [:]
        for entry in journal.entries {
            totals[calendar.startOfDay(for: entry.date), default: 0] += entry.freed
        }
        return (0..<30).reversed().compactMap { offset in
            calendar.date(byAdding: .day, value: -offset, to: today).map { DailyGain(day: $0, bytes: totals[$0] ?? 0) }
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Espace libéré ces 30 derniers jours").font(.system(.headline, design: .rounded))
            Chart(dailyGains) { gain in
                BarMark(x: .value("Day", gain.day, unit: .day), y: .value("Bytes", Double(gain.bytes)))
                    .foregroundStyle(Theme.mint.gradient)
                    .cornerRadius(3)
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Color.white.opacity(0.08))
                    AxisValueLabel {
                        if let bytes = value.as(Double.self) {
                            Text(verbatim: bytes == 0 ? "0" : Int64(bytes).formattedBytes)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .day, count: 7)) { _ in
                    AxisValueLabel(format: .dateTime.day().month(.abbreviated).locale(AppLocalization.locale))
                }
            }
            .frame(height: 150)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Theme.cardBorder))
    }

    // MARK: Liste

    private var days: [(day: Date, entries: [JournalEntry])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: journal.entries) { calendar.startOfDay(for: $0.date) }
        return grouped.keys.sorted(by: >).map { ($0, grouped[$0] ?? []) }
    }

    private var entries: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Toutes les actions").font(.system(.title3, design: .rounded).weight(.semibold))
                Spacer()
                Menu {
                    Button("Exporter en CSV…") { export(journal.entries, as: .commaSeparatedText) }
                    Button("Exporter en JSON…") { export(journal.entries, as: .json) }
                } label: {
                    Label("Exporter", systemImage: "square.and.arrow.up")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                Button("Effacer l'historique") { confirmClear.value = true }
            }
            ForEach(days, id: \.day) { group in
                VStack(alignment: .leading, spacing: 8) {
                    Text(Self.dayTitle(group.day))
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    ForEach(group.entries) { entry in
                        EntryCard(
                            entry: entry,
                            expanded: Binding(
                                get: { expanded.value.contains(entry.id) },
                                set: { isOn in
                                    if isOn { expanded.value.insert(entry.id) } else { expanded.value.remove(entry.id) }
                                }
                            ),
                            export: { export([entry], as: .commaSeparatedText) }
                        )
                    }
                }
            }
        }
    }

    private var privacyNote: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield").foregroundColor(Theme.mint)
            Text("L'historique reste sur ce Mac et n'est envoyé nulle part.")
                .font(.caption)
                .foregroundColor(.secondary)
            Button("Afficher le dossier") { FS.reveal(ActivityJournal.folder) }
                .buttonStyle(.borderless)
                .font(.caption)
        }
    }

    private var empty: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 48))
                .foregroundColor(Theme.lavender)
            Text("Aucune action pour l'instant").font(.title3.weight(.semibold))
            Text("Chaque nettoyage, désinstallation ou entretien apparaîtra ici, avec la liste de ce qui a été supprimé. L'historique reste sur ce Mac.")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 460)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    static func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return localized("Aujourd'hui") }
        if calendar.isDateInYesterday(day) { return localized("Hier") }
        return day.formatted(.dateTime.weekday(.wide).day().month(.wide).year().locale(AppLocalization.locale))
    }

    private func export(_ entries: [JournalEntry], as type: UTType) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [type]
        panel.nameFieldStringValue = "TidyMyMac-" + localized("Historique") + (type == .json ? ".json" : ".csv")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let data = type == .json
            ? try? ActivityJournal.json(for: entries)
            : ActivityJournal.csv(for: entries).data(using: .utf8)
        try? data?.write(to: url, options: .atomic)
    }
}

/// Une action du journal, dépliable pour voir chaque élément.
private struct EntryCard: View {
    let entry: JournalEntry
    @Binding var expanded: Bool
    let export: () -> Void
    @ObservedObject private var journal = ActivityJournal.shared
    @StateObject private var restoreMessage = ViewState<String?>(nil)

    /// Au-delà, la liste complète est dans l'export.
    private static let visibleItems = 60

    private var summary: String {
        var parts = [entry.date.formatted(.dateTime.hour().minute().locale(AppLocalization.locale))]
        if !entry.items.isEmpty {
            parts.append(localized("\(entry.items.count) élément(s)"))
        }
        if entry.failureCount > 0 {
            parts.append(localized("\(entry.failureCount) échec(s)"))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { expanded.toggle() } label: {
                HStack(spacing: 12) {
                    IconTile(symbol: entry.kind.icon, tint: entry.kind.tint, size: 34)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.title).font(.body.weight(.medium))
                        Text(summary).font(.caption).foregroundColor(.secondary)
                    }
                    Spacer()
                    if entry.freed > 0 {
                        Text(entry.freed.formattedGain)
                            .font(.system(.body, design: .rounded).weight(.semibold))
                            .foregroundColor(Theme.mint)
                            .monospacedDigit()
                    }
                    if entry.memoryFreed > 0 {
                        Text(localized("\(entry.memoryFreed.formattedBytes) de mémoire"))
                            .font(.callout)
                            .foregroundColor(Theme.lavender)
                            .monospacedDigit()
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .foregroundColor(.secondary)
                        .frame(width: 16)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if expanded {
                details.padding(.top, 12)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.cardBorder))
    }

    @ViewBuilder private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(entry.steps, id: \.self) { step in
                HStack(spacing: 10) {
                    Image(systemName: step.succeeded ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(step.succeeded ? Theme.mint : Theme.amber)
                    Text(step.title)
                    if let detail = step.detail {
                        Text(detail).font(.caption).foregroundColor(.secondary).lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.vertical, 5)
            }
            ForEach(entry.items.prefix(Self.visibleItems)) { item in
                ItemRow(item: item) {
                    restoreMessage.value = journal.restore(entry.id, paths: [item.path]).message
                }
                Divider().opacity(0.3)
            }
            HStack {
                if entry.items.count > Self.visibleItems {
                    Text(localized("… et \(entry.items.dropFirst(Self.visibleItems).count) autres, dans l'export"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
                if !entry.restorableItems.isEmpty {
                    Button {
                        restoreMessage.value = journal.restore(entry.id).message
                    } label: {
                        Label("Tout remettre en place", systemImage: "arrow.uturn.backward")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Button("Exporter cette action…", action: export)
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.top, 8)
            if let message = restoreMessage.value {
                Text(message).font(.caption).foregroundColor(.secondary).padding(.top, 4)
            }
        }
        .padding(.leading, 46)
    }
}

private struct ItemRow: View {
    let item: JournalItem
    let restore: () -> Void

    /// Où retrouver l'élément aujourd'hui : dans la Corbeille, ou à sa place s'il n'a pas été supprimé.
    private var currentLocation: URL? {
        if let trash = item.trashURL, FS.exists(trash) { return trash }
        return FS.exists(item.url) ? item.url : nil
    }

    var body: some View {
        let availability = item.availability
        HStack(spacing: 10) {
            Image(nsImage: FS.icon(for: item.url)).resizable().frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.url.lastPathComponent).lineLimit(1)
                Text(item.source.map { "\($0) · \(item.url.deletingLastPathComponent().path.abbreviatingHome)" }
                    ?? item.url.deletingLastPathComponent().path.abbreviatingHome)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            if item.size > 0 {
                Text(item.size.formattedBytes).font(.caption).foregroundColor(.secondary).monospacedDigit()
            }
            Label(availability.title, systemImage: availability.icon)
                .font(.caption2.weight(.semibold))
                .foregroundColor(availability.tint)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(Capsule().fill(availability.tint.opacity(0.14)))
                .fixedSize()
                .help(availability == .occupied
                    ? localized("Un élément du même nom est déjà à cet emplacement : remettez celui-ci depuis la Corbeille si besoin.")
                    : "")
            if availability == .restorable {
                Button(action: restore) { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless)
                    .help("Remettre en place")
            }
            Button { if let location = currentLocation { FS.reveal(location) } } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .disabled(currentLocation == nil)
            .help("Afficher dans le Finder")
        }
        .padding(.vertical, 6)
    }
}
