import Foundation

/// Un fichier ou dossier trouvé par une analyse, que l'utilisateur peut cocher.
struct ScanItem: Identifiable, Hashable, Sendable {
    let id = UUID()
    let url: URL
    let size: Int64
    var selected: Bool
}

enum ScanPhase: Equatable {
    case idle
    case scanning
    case ready
    case cleaning
    case done(freed: Int64)
}

extension Array where Element == ScanItem {
    var totalSize: Int64 { reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { reduce(0) { $1.selected ? $0 + $1.size : $0 } }
}
