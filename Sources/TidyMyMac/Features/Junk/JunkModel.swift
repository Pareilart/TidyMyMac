import Foundation

struct JunkResult: Identifiable, Sendable {
    let rule: CleanupRule
    var items: [ScanItem]
    var id: String { rule.id }
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
        let rules = await Task.detached(priority: .userInitiated) { RuleBook.load().activeRules }.value
        for rule in rules {
            progressLabel = rule.title
            let result = await Task.detached(priority: .userInitiated) {
                let items = rule.locate()
                    .map { ScanItem(url: $0, size: FS.size(of: $0), selected: rule.selectedByDefault) }
                    .filter { $0.size > 0 }
                    .sorted { $0.size > $1.size }
                return JunkResult(rule: rule, items: items)
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
        var removal = Removal()
        var candidates: [RemovalCandidate] = []
        for result in results {
            let selected = result.items.filter(\.selected)
            guard !selected.isEmpty else { continue }
            let urls = selected.map(\.url)
            let permanently = result.rule.deletesPermanently
            removal.merge(await Task.detached { Remover.perform(urls, permanently: permanently) }.value)
            candidates += selected.map { RemovalCandidate(url: $0.url, size: $0.size, source: result.rule.title) }
        }
        let freed = results
            .flatMap(\.items)
            .filter { $0.selected && removal.removed.contains($0.url) }
            .totalSize
        failures = removal.failed
        results = []
        Stats.record(freed: freed)
        ActivityJournal.shared.recordRemoval(.junk, removal: removal, candidates: candidates)
        phase = .done(freed: freed)
    }
}
