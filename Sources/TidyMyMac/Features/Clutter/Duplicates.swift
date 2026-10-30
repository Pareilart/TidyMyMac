import CryptoKit
import SwiftUI

struct DuplicateGroup: Identifiable, Sendable {
    let id = UUID()
    let size: Int64
    var files: [ScanItem]
    var wasted: Int64 { size * Int64(max(files.count - 1, 0)) }
}

enum DuplicateFinder {
    private static let partialHashLength = 64 * 1024

    /// Regroupe par taille, puis par empreinte des 64 premiers Ko, puis par empreinte complète.
    static func find(in root: URL, minSize: Int64) -> [DuplicateGroup] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }
        var bySize: [Int64: [URL]] = [:]
        for case let url as URL in enumerator {
            if url.path == FS.library.path {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true,
                  let size = values.fileSize, Int64(size) >= minSize else { continue }
            bySize[Int64(size), default: []].append(url)
        }

        var groups: [DuplicateGroup] = []
        for (size, urls) in bySize where urls.count > 1 {
            for partial in regroup(urls, limit: partialHashLength) {
                let identical = size <= Int64(partialHashLength) ? [partial] : regroup(partial, limit: nil)
                for same in identical {
                    // On garde le plus ancien, les copies suivantes sont pré-cochées.
                    let ordered = same.sorted { creationDate($0) < creationDate($1) }
                    let items = ordered.enumerated().map { ScanItem(url: $1, size: size, selected: $0 > 0) }
                    groups.append(DuplicateGroup(size: size, files: items))
                }
            }
        }
        return groups.sorted { $0.wasted > $1.wasted }
    }

    private static func regroup(_ urls: [URL], limit: Int?) -> [[URL]] {
        var byHash: [String: [URL]] = [:]
        for url in urls {
            if let digest = hash(url, limit: limit) {
                byHash[digest, default: []].append(url)
            }
        }
        return byHash.values.filter { $0.count > 1 }
    }

    private static func hash(_ url: URL, limit: Int?) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        var remaining = limit ?? Int.max
        while remaining > 0 {
            let chunk = autoreleasepool { try? handle.read(upToCount: min(1 << 20, remaining)) }
            guard let data = chunk, !data.isEmpty else { break }
            hasher.update(data: data)
            remaining -= data.count
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private static func creationDate(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture
    }
}

@MainActor
final class DuplicatesModel: ObservableObject {
    @Published var groups: [DuplicateGroup] = []
    @Published var phase: ScanPhase = .idle
    @Published var root = FS.home
    @Published var failures: [URL] = []
    /// Dernière action enregistrée dans le journal, pour pouvoir l'annuler.
    @Published var lastEntryID: UUID?

    var wasted: Int64 { groups.reduce(0) { $0 + $1.wasted } }
    var selectedSize: Int64 { groups.reduce(0) { $0 + $1.files.selectedSize } }

    func scan() async {
        phase = .scanning
        let root = self.root
        groups = await Task.detached(priority: .userInitiated) {
            DuplicateFinder.find(in: root, minSize: 1_000_000)
        }.value
        phase = .ready
    }

    func trashSelected() async {
        phase = .cleaning
        // Garde-fou : on conserve toujours au moins un exemplaire de chaque groupe.
        for index in groups.indices where groups[index].files.allSatisfy(\.selected) {
            groups[index].files[0].selected = false
        }
        let selected = groups.flatMap(\.files).filter(\.selected)
        let urls = selected.map(\.url)
        let removal = await Task.detached { Remover.perform(urls, permanently: false) }.value
        let freed = selected.filter { removal.removed.contains($0.url) }.totalSize
        failures = removal.failed
        groups = []
        Stats.record(freed: freed)
        lastEntryID = ActivityJournal.shared.recordRemoval(
            .duplicates, removal: removal, candidates: selected.map { RemovalCandidate(url: $0.url, size: $0.size) }
        )?.id
        phase = .done(freed: freed)
    }
}

struct DuplicatesView: View {
    @EnvironmentObject var model: DuplicatesModel

    var body: some View {
        if model.phase == .idle {
            ModuleIntro(module: .duplicates, action: { Task { await model.scan() } }) {
                folderButton.padding(.top, 8)
            }
        } else {
            VStack(spacing: 0) {
                ModuleHeader(module: .duplicates)
                HStack {
                    folderButton
                    Text("Au moins un exemplaire est toujours conservé.").font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Button("Analyser") { Task { await model.scan() } }
                        .disabled(model.phase == .scanning || model.phase == .cleaning)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                Divider()
                content
            }
        }
    }

    private var folderButton: some View {
        Button("Dossier : \(model.root.lastPathComponent)") {
            if let url = chooseFolder() { model.root = url }
        }
    }

    @ViewBuilder private var content: some View {
        switch model.phase {
        case .idle:
            EmptyView()
        case .scanning:
            ProgressPrompt(text: "Comparaison des fichiers de \(model.root.path.abbreviatingHome)…")
        case .cleaning:
            ProgressPrompt(text: "Déplacement vers la Corbeille…")
        case .done(let freed):
            DonePrompt(freed: freed, failures: model.failures, entryID: model.lastEntryID) { Task { await model.scan() } }
        case .ready:
            if model.groups.isEmpty {
                StartPrompt(text: "Aucun doublon trouvé.", buttonTitle: "Analyser à nouveau") {
                    Task { await model.scan() }
                }
            } else {
                VStack(spacing: 0) {
                    List {
                        ForEach($model.groups) { $group in
                            Section("\(group.files.count) copies · \(group.size.formattedBytes) chacune") {
                                ForEach($group.files) { $file in
                                    FileRow(url: file.url, size: file.size, selected: $file.selected)
                                }
                            }
                        }
                    }
                    Divider()
                    ActionBar(
                        summary: "\(model.selectedSize.formattedBytes) sélectionnés · \(model.wasted.formattedBytes) récupérables",
                        actionTitle: "Mettre à la corbeille",
                        disabled: model.selectedSize == 0
                    ) {
                        Task { await model.trashSelected() }
                    }
                }
            }
        }
    }
}
