import Foundation

/// Un élément du plan de nettoyage : ce qui sera supprimé, la règle qui le propose et où il ira.
struct PlanItem: Identifiable, Codable, Sendable {
    let path: String
    let size: Int64
    let modified: Date?
    let ruleID: String
    let rule: String
    let risk: RiskLevel
    /// Supprimé sans passer par la Corbeille.
    let permanent: Bool
    /// Coché pour le nettoyage (toujours vrai dans le plan affiché avant de nettoyer).
    let selected: Bool

    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

/// Ce que le nettoyage s'apprête à supprimer, élément par élément. Le construire n'exécute rien.
struct CleanupPlan: Encodable, Sendable {
    let createdAt: Date
    var items: [PlanItem]

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var permanentCount: Int { items.filter(\.permanent).count }

    init(items: [PlanItem]) {
        createdAt = Date()
        self.items = items
    }

    /// Les éléments cochés de l'analyse des fichiers inutiles.
    init(results: [JunkResult]) {
        self.init(items: results.flatMap { result in
            result.items.filter(\.selected).map { item in
                PlanItem(
                    path: item.url.path, size: item.size, modified: FS.modificationDate(item.url),
                    ruleID: result.rule.id, rule: result.rule.title, risk: result.rule.effectiveRisk,
                    permanent: result.rule.deletesPermanently, selected: true
                )
            }
        })
    }

    /// Simulation complète des règles actives, cochées ou non (`--list-rules --json`).
    static func simulate(_ rules: [CleanupRule]) -> CleanupPlan {
        CleanupPlan(items: rules.flatMap { rule in
            rule.locate().map { url in
                PlanItem(
                    path: url.path, size: FS.size(of: url), modified: FS.modificationDate(url), ruleID: rule.id,
                    rule: rule.title, risk: rule.effectiveRisk, permanent: rule.deletesPermanently,
                    selected: rule.selectedByDefault
                )
            }
        })
    }

    // MARK: Export

    private enum CodingKeys: String, CodingKey { case createdAt, items, itemCount, totalSize, permanentCount }

    /// Les totaux sont écrits avec la liste, pour qui lit l'export sans le recalculer.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(createdAt, forKey: .createdAt)
        try container.encode(items.count, forKey: .itemCount)
        try container.encode(totalSize, forKey: .totalSize)
        try container.encode(permanentCount, forKey: .permanentCount)
        try container.encode(items, forKey: .items)
    }

    func csv() -> String {
        func field(_ value: String) -> String { "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        let dates = ISO8601DateFormatter()
        var lines = ["path,size_bytes,modified,rule_id,rule,risk,destination,selected"]
        for item in items {
            lines.append([
                field(item.path), String(item.size), item.modified.map(dates.string(from:)) ?? "", item.ruleID,
                field(item.rule), item.risk.rawValue, item.permanent ? "delete" : "trash", item.selected ? "yes" : "no",
            ].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    func json() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
