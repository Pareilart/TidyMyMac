import Foundation

struct JunkResult: Identifiable, Sendable {
    let category: JunkCategory
    var items: [ScanItem]
    var id: String { category.id }
    var allSelected: Bool { !items.isEmpty && items.allSatisfy(\.selected) }
}

@MainActor
final class JunkModel: ObservableObject {
    @Published var results: [JunkResult] = []
    @Published var phase: ScanPhase = .idle
    @Published var progressLabel = ""
    @Published var failures: [URL] = []

    var totalSize: Int64 { results.reduce(0) { $0 + $1.items.totalSize } }
    var selectedSize: Int64 { results.reduce(0) { $0 + $1.items.selectedSize } }

    func scan() async {
        phase = .scanning
        results = []
        failures = []
        for category in JunkCategory.all {
            progressLabel = category.title
            let result = await Task.detached(priority: .userInitiated) {
                let items = category.locate()
                    .map { ScanItem(url: $0, size: FS.size(of: $0), selected: category.selectedByDefault) }
                    .filter { $0.size > 0 }
                    .sorted { $0.size > $1.size }
                return JunkResult(category: category, items: items)
            }.value
            if !result.items.isEmpty {
                results.append(result)
            }
        }
        progressLabel = ""
        phase = .ready
    }

    func clean() async {
        phase = .cleaning
        var failed: [URL] = []
        for result in results {
            let urls = result.items.filter(\.selected).map(\.url)
            guard !urls.isEmpty else { continue }
            let permanently = result.category.alwaysPermanent || Remover.deletePermanently
            failed += await Task.detached { Remover.remove(urls, permanently: permanently) }.value
        }
        let failedSet = Set(failed)
        let freed = results
            .flatMap(\.items)
            .filter { $0.selected && !failedSet.contains($0.url) }
            .totalSize
        failures = failed
        results = []
        Stats.record(freed: freed)
        phase = .done(freed: freed)
    }
}
