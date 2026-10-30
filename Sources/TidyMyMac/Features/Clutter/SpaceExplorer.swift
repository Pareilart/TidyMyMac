import AppKit
import SwiftUI

struct SizedEntry: Identifiable, Equatable, Sendable {
    let url: URL
    let size: Int64
    let isDirectory: Bool
    var id: URL { url }
}

@MainActor
final class SpaceExplorerModel: ObservableObject {
    enum DisplayMode: String {
        case bubbles, list
    }

    @Published var current: URL?
    @Published var entries: [SizedEntry] = [] {
        didSet { bubbles = BubblePacker.pack(entries) }
    }
    @Published private(set) var bubbles: [PackedBubble] = []
    @Published var hovered: String?
    @Published var selection: Set<URL> = []
    @Published private(set) var lastTrashMessage: String?
    /// Dernière action enregistrée dans le journal, pour pouvoir l'annuler.
    @Published private(set) var lastEntryID: UUID?
    @Published var loading = false
    @Published var progress = ""
    @Published var displayMode = DisplayMode(rawValue: UserDefaults.standard.string(forKey: "spaceExplorerMode") ?? "") ?? .bubbles {
        didSet { UserDefaults.standard.set(displayMode.rawValue, forKey: "spaceExplorerMode") }
    }

    private var cache: [URL: [SizedEntry]] = [:]
    private var task: Task<Void, Never>?

    var total: Int64 { entries.reduce(0) { $0 + $1.size } }
    var largest: Int64 { entries.first?.size ?? 0 }
    var hoveredBubble: PackedBubble? { bubbles.first { $0.id == hovered } }
    var selectedEntries: [SizedEntry] { entries.filter { selection.contains($0.url) } }

    func toggleSelection(_ url: URL) {
        if selection.contains(url) {
            selection.remove(url)
        } else {
            selection.insert(url)
        }
    }

    func open(_ url: URL) {
        task?.cancel()
        current = url
        hovered = nil
        selection = []
        lastTrashMessage = nil
        if let cached = cache[url] {
            entries = cached
            loading = false
            return
        }
        entries = []
        loading = true
        task = Task {
            var collected: [SizedEntry] = []
            for child in FS.children(of: url, includeHidden: true) {
                if Task.isCancelled { return }
                progress = child.lastPathComponent
                let entry = await Task.detached(priority: .userInitiated) {
                    SizedEntry(url: child, size: FS.size(of: child), isDirectory: FS.isDirectory(child))
                }.value
                if Task.isCancelled { return }
                collected.append(entry)
                entries = collected.sorted { $0.size > $1.size }
            }
            cache[url] = entries
            loading = false
        }
    }

    /// Relit le dossier affiché, par exemple après avoir remis des éléments en place.
    func reload() {
        cache = [:]
        if let current { open(current) }
    }

    func up() {
        guard let current, current.path != "/" else { return }
        open(current.deletingLastPathComponent())
    }

    func trash(_ targets: [SizedEntry]) {
        let removal = Remover.perform(targets.map(\.url), permanently: false)
        let failed = removal.failed
        let removed = targets.filter { removal.removed.contains($0.url) }
        let removedURLs = Set(removed.map(\.url))
        let freed = removed.reduce(0) { $0 + $1.size }
        Stats.record(freed: freed)
        lastEntryID = ActivityJournal.shared.recordRemoval(
            .spaceExplorer, removal: removal, candidates: targets.map { RemovalCandidate(url: $0.url, size: $0.size) }
        )?.id
        entries.removeAll { removedURLs.contains($0.url) }
        selection.subtract(removedURLs)
        // Les tailles des dossiers parents ne sont plus à jour.
        cache = [:]
        if let current { cache[current] = entries }
        lastTrashMessage = failed.isEmpty
            ? localized("\(removed.count) élément(s) dans la Corbeille · \(freed.formattedBytes) libérés")
            : localized("\(freed.formattedBytes) libérés · \(failed.count) élément(s) non supprimé(s)")
    }
}

struct SpaceExplorerView: View {
    @EnvironmentObject var model: SpaceExplorerModel
    @StateObject private var pendingTrash = ViewState<[SizedEntry]>([])

    var body: some View {
        Group {
            if let current = model.current {
                VStack(spacing: 0) {
                    ModuleHeader(module: .spaceExplorer)
                    Divider()
                    toolbar(for: current)
                    Divider()
                    switch model.displayMode {
                    case .bubbles:
                        bubbleChart
                        bubbleFooter
                    case .list:
                        entryList
                    }
                    selectionBar
                }
                .onDeleteCommand { pendingTrash.value = model.selectedEntries }
            } else {
                ModuleIntro(module: .spaceExplorer, action: { model.open(FS.home) }) {
                    Button("Choisir un autre dossier…") {
                        if let url = chooseFolder() { model.open(url) }
                    }
                    .padding(.top, 8)
                }
            }
        }
        .confirmationDialog(
            trashQuestion,
            isPresented: Binding(get: { !pendingTrash.value.isEmpty }, set: { if !$0 { pendingTrash.value = [] } })
        ) {
            Button("Mettre à la corbeille", role: .destructive) {
                model.trash(pendingTrash.value)
                pendingTrash.value = []
            }
        }
    }

    private var trashQuestion: String {
        let targets = pendingTrash.value
        if targets.count == 1, let entry = targets.first {
            return localized("Mettre « \(entry.url.lastPathComponent) » à la corbeille ?")
        }
        let size = targets.reduce(0) { $0 + $1.size }.formattedBytes
        return localized("Mettre \(targets.count) éléments (\(size)) à la corbeille ?")
    }

    /// Un clic droit sur un élément sélectionné agit sur toute la sélection.
    private func targets(for entry: SizedEntry) -> [SizedEntry] {
        model.selection.contains(entry.url) ? model.selectedEntries : [entry]
    }

    private var selectionBar: some View {
        let selected = model.selectedEntries
        return Group {
            if !selected.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundColor(Theme.sky)
                    Text("\(selected.count) élément(s) sélectionné(s) · \(selected.reduce(0) { $0 + $1.size }.formattedBytes)")
                        .monospacedDigit()
                    Spacer()
                    Button("Désélectionner") { model.selection = [] }
                    Button("Afficher dans le Finder") { FS.reveal(selected.map(\.url)) }
                    Button("Mettre à la corbeille…") { pendingTrash.value = selected }
                        .buttonStyle(PrimaryButtonStyle(tint: Theme.coral))
                }
            } else if let message = model.lastTrashMessage {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill").foregroundColor(Theme.mint)
                    Text(message).foregroundColor(Theme.mint).monospacedDigit()
                    Spacer()
                    UndoActionButton(entryID: model.lastEntryID, title: "Annuler") { model.reload() }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, selected.isEmpty && model.lastTrashMessage == nil ? 0 : 12)
        .background(Color.black.opacity(0.18))
    }

    private func toolbar(for current: URL) -> some View {
        HStack(spacing: 10) {
            Button { model.up() } label: { Image(systemName: "chevron.left") }
                .disabled(current.path == "/")
                .help("Dossier parent")
            Text(current.path.abbreviatingHome).lineLimit(1).truncationMode(.head)
            Spacer()
            if model.loading {
                ProgressView().controlSize(.small)
                Text(model.progress).font(.caption).foregroundColor(.secondary).lineLimit(1).frame(maxWidth: 160)
            }
            Text(model.total.formattedBytes).monospacedDigit().bold()
            Picker("Affichage", selection: $model.displayMode) {
                Image(systemName: "circle.hexagongrid.fill").tag(SpaceExplorerModel.DisplayMode.bubbles)
                Image(systemName: "list.bullet").tag(SpaceExplorerModel.DisplayMode.list)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 84)
            .help("Bulles ou liste")
            Button("Choisir…") {
                if let url = chooseFolder() { model.open(url) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    // MARK: - Bulles

    private var bubbleChart: some View {
        GeometryReader { geometry in
            let fit = BubbleFit(bubbles: model.bubbles, size: geometry.size)
            ZStack {
                ForEach(model.bubbles) { bubble in
                    BubbleView(
                        bubble: bubble,
                        diameter: bubble.radius * 2 * fit.scale,
                        highlighted: model.hovered == bubble.id,
                        selected: bubble.entry.map { model.selection.contains($0.url) } ?? false
                    )
                        .contentShape(Circle())
                        .onHover { inside in
                            if inside {
                                model.hovered = bubble.id
                            } else if model.hovered == bubble.id {
                                model.hovered = nil
                            }
                        }
                        .onTapGesture(count: 2) { activate(bubble) }
                        .onTapGesture {
                            if let entry = bubble.entry { model.toggleSelection(entry.url) }
                        }
                        .contextMenu { bubbleMenu(bubble) }
                        .position(fit.point(bubble.center))
                }
            }
            .animation(.spring(response: 0.45, dampingFraction: 0.8), value: model.bubbles)
        }
        .padding(16)
    }

    @ViewBuilder private func bubbleMenu(_ bubble: PackedBubble) -> some View {
        if let entry = bubble.entry {
            entryMenu(targets(for: entry))
        } else {
            Button("Voir la liste complète") { model.displayMode = .list }
        }
    }

    private func activate(_ bubble: PackedBubble) {
        guard let entry = bubble.entry else {
            model.displayMode = .list
            return
        }
        if entry.isDirectory {
            model.open(entry.url)
        } else {
            FS.reveal(entry.url)
        }
    }

    private var bubbleFooter: some View {
        HStack(spacing: 12) {
            if let bubble = model.hoveredBubble {
                Circle().fill(bubble.kind.color).frame(width: 10, height: 10)
                Text(bubble.label).bold().lineLimit(1).truncationMode(.middle)
                Text("\(bubble.size.formattedBytes) · \(share(of: bubble.size)) du dossier")
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            } else {
                Text("Clic : sélectionner · double-clic : ouvrir un dossier")
                    .foregroundColor(.secondary)
            }
            Spacer()
            ForEach(FileKind.allCases.filter { kind in model.bubbles.contains { $0.kind == kind } }, id: \.self) { kind in
                HStack(spacing: 4) {
                    Circle().fill(kind.color).frame(width: 8, height: 8)
                    Text(kind.label).font(.caption).foregroundColor(.secondary)
                }
            }
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(Color.black.opacity(0.18))
    }

    private func share(of size: Int64) -> String {
        "\(Int((Double(size) / Double(max(model.total, 1)) * 100).rounded())) %"
    }

    /// Actions communes au menu contextuel des bulles et de la liste.
    @ViewBuilder private func entryMenu(_ targets: [SizedEntry]) -> some View {
        if targets.count == 1, let entry = targets.first, entry.isDirectory {
            Button("Ouvrir") { model.open(entry.url) }
        }
        Button(targets.count > 1
               ? localized("Afficher les \(targets.count) éléments dans le Finder")
               : localized("Afficher dans le Finder")) {
            FS.reveal(targets.map(\.url))
        }
        Divider()
        Button(targets.count > 1
               ? localized("Mettre les \(targets.count) éléments à la corbeille…")
               : localized("Mettre à la corbeille…")) {
            pendingTrash.value = targets
        }
    }

    // MARK: - Liste

    private var entryList: some View {
        List(model.entries, selection: $model.selection) { entry in
            row(entry)
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            entryMenu(model.entries.filter { urls.contains($0.url) })
        } primaryAction: { urls in
            let targets = model.entries.filter { urls.contains($0.url) }
            if targets.count == 1, let entry = targets.first, entry.isDirectory {
                model.open(entry.url)
            } else {
                FS.reveal(targets.map(\.url))
            }
        }
    }

    private func row(_ entry: SizedEntry) -> some View {
        HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { model.selection.contains(entry.url) },
                set: { _ in model.toggleSelection(entry.url) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path))
                .resizable()
                .frame(width: 20, height: 20)
            Text(entry.url.lastPathComponent)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 240, alignment: .leading)
            ProgressView(value: Double(entry.size), total: Double(max(model.largest, 1)))
                .tint(FileKind(entry: entry).color)
            Text(entry.size.formattedBytes)
                .monospacedDigit()
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
            Image(systemName: "chevron.right")
                .foregroundColor(.secondary)
                .opacity(entry.isDirectory ? 1 : 0)
        }
        .tag(entry.url)
    }
}

/// Mise à l'échelle des coordonnées normalisées du packer vers la zone d'affichage.
private struct BubbleFit {
    let scale: CGFloat
    let offset: CGPoint

    init(bubbles: [PackedBubble], size: CGSize) {
        let minX = bubbles.map { $0.center.x - $0.radius }.min() ?? 0
        let maxX = bubbles.map { $0.center.x + $0.radius }.max() ?? 1
        let minY = bubbles.map { $0.center.y - $0.radius }.min() ?? 0
        let maxY = bubbles.map { $0.center.y + $0.radius }.max() ?? 1
        let width = max(maxX - minX, 0.001)
        let height = max(maxY - minY, 0.001)
        scale = min(size.width / width, size.height / height) * 0.96
        offset = CGPoint(
            x: size.width / 2 - (minX + width / 2) * scale,
            y: size.height / 2 - (minY + height / 2) * scale
        )
    }

    func point(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x * scale + offset.x, y: point.y * scale + offset.y)
    }
}

private struct BubbleView: View {
    let bubble: PackedBubble
    let diameter: CGFloat
    let highlighted: Bool
    let selected: Bool

    private var fontSize: CGFloat { min(max(diameter / 9, 10), 17) }

    var body: some View {
        let color = bubble.kind.color
        ZStack {
            Circle().fill(
                RadialGradient(
                    colors: [color.opacity(0.55), color.opacity(0.16)],
                    center: UnitPoint(x: 0.35, y: 0.3), startRadius: 0, endRadius: diameter * 0.75
                )
            )
            Circle().strokeBorder(
                selected ? Color.white : color.opacity(highlighted ? 1 : 0.45),
                style: StrokeStyle(lineWidth: selected ? 2.5 : highlighted ? 2 : 1, dash: selected ? [6, 4] : [])
            )
            if selected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: max(min(diameter * 0.16, 22), 12)))
                    .foregroundStyle(Theme.backgroundBottom, Color.white)
                    .offset(x: diameter * 0.33, y: -diameter * 0.33)
            }
            if diameter > 58 {
                VStack(spacing: 2) {
                    if diameter > 120 {
                        Image(systemName: bubble.kind.icon)
                            .font(.system(size: fontSize * 1.3))
                            .foregroundColor(color)
                    }
                    Text(bubble.label)
                        .font(.system(size: fontSize, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(bubble.size.formattedBytes)
                        .font(.system(size: fontSize * 0.85, design: .rounded))
                        .foregroundColor(.secondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, diameter * 0.15)
                .frame(width: diameter)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: color.opacity(highlighted ? 0.5 : 0), radius: 14)
        .scaleEffect(highlighted ? 1.03 : 1)
        .animation(.easeOut(duration: 0.15), value: highlighted)
    }
}
