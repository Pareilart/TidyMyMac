import SwiftUI

struct LargeFile: Identifiable, Sendable {
    let url: URL
    let size: Int64
    let accessed: Date?
    var selected = false
    var id: URL { url }
}

enum LargeFilesScanner {
    /// Parcourt `root` (hors ~/Library et fichiers cachés). Les paquets (.app, .photoslibrary…) comptent comme un seul élément.
    static func find(in root: URL, minSize: Int64) -> [LargeFile] {
        let keys: Set<URLResourceKey> = [
            .isRegularFileKey, .isPackageKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey,
        ]
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
        ) else { return [] }
        var found: [LargeFile] = []
        for case let url as URL in enumerator {
            if url.path == FS.library.path {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: keys) else { continue }
            var size: Int64 = 0
            if values.isPackage == true {
                size = FS.size(of: url)
            } else if values.isRegularFile == true {
                size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            }
            if size >= minSize {
                found.append(LargeFile(url: url, size: size, accessed: values.contentAccessDate))
            }
        }
        return found.sorted { $0.size > $1.size }
    }
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var phase: ScanPhase = .idle
    @Published var thresholdMB = 100
    @Published var root = FS.home
    @Published var failures: [URL] = []

    var selectedSize: Int64 { files.reduce(0) { $1.selected ? $0 + $1.size : $0 } }

    func scan() async {
        phase = .scanning
        let root = self.root
        let minSize = Int64(thresholdMB) * 1_000_000
        files = await Task.detached(priority: .userInitiated) {
            LargeFilesScanner.find(in: root, minSize: minSize)
        }.value
        phase = .ready
    }

    func trashSelected() async {
        phase = .cleaning
        let selected = files.filter(\.selected)
        let urls = selected.map(\.url)
        let failed = await Task.detached { Remover.remove(urls, permanently: false) }.value
        let failedSet = Set(failed)
        let freed = selected.filter { !failedSet.contains($0.url) }.reduce(0) { $0 + $1.size }
        failures = failed
        files = []
        Stats.record(freed: freed)
        phase = .done(freed: freed)
    }
}

struct LargeFilesView: View {
    @EnvironmentObject var model: LargeFilesModel

    var body: some View {
        if model.phase == .idle {
            ModuleIntro(module: .largeFiles, action: { Task { await model.scan() } }) {
                HStack {
                    thresholdPicker
                    folderButton
                }
                .padding(.top, 8)
            }
        } else {
            VStack(spacing: 0) {
                ModuleHeader(module: .largeFiles)
                HStack {
                    thresholdPicker
                    folderButton
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

    private var thresholdPicker: some View {
        Picker("Taille minimale", selection: $model.thresholdMB) {
            Text("50 Mo").tag(50)
            Text("100 Mo").tag(100)
            Text("500 Mo").tag(500)
            Text("1 Go").tag(1000)
        }
        .frame(width: 220)
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
            ProgressPrompt(text: "Analyse de \(model.root.path.abbreviatingHome)…")
        case .cleaning:
            ProgressPrompt(text: "Déplacement vers la Corbeille…")
        case .done(let freed):
            DonePrompt(freed: freed, failures: model.failures) { Task { await model.scan() } }
        case .ready:
            VStack(spacing: 0) {
                List {
                    ForEach($model.files) { $file in
                        FileRow(url: file.url, size: file.size, selected: $file.selected, detail: detail(for: file))
                    }
                }
                Divider()
                ActionBar(
                    summary: "\(model.files.filter(\.selected).count) fichier(s) · \(model.selectedSize.formattedBytes)",
                    actionTitle: "Mettre à la corbeille",
                    disabled: model.selectedSize == 0
                ) {
                    Task { await model.trashSelected() }
                }
            }
        }
    }

    private func detail(for file: LargeFile) -> String {
        let folder = file.url.deletingLastPathComponent().path.abbreviatingHome
        guard let accessed = file.accessed else { return folder }
        return localized("\(folder) · ouvert \(accessed.relativeDescription)")
    }
}
