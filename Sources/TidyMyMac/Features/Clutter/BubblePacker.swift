import CoreGraphics
import SwiftUI
import UniformTypeIdentifiers

enum FileKind: CaseIterable {
    case folder, application, image, video, audio, archive, document, other

    init(entry: SizedEntry) {
        let ext = entry.url.pathExtension.lowercased()
        if ext == "app" {
            self = .application
            return
        }
        if entry.isDirectory {
            self = .folder
            return
        }
        guard let type = UTType(filenameExtension: ext) else {
            self = .other
            return
        }
        if type.conforms(to: .image) {
            self = .image
        } else if type.conforms(to: .audio) {
            self = .audio
        } else if type.conforms(to: .audiovisualContent) {
            self = .video
        } else if type.conforms(to: .archive) || type.conforms(to: .diskImage) {
            self = .archive
        } else if [.text, .pdf, .presentation, .spreadsheet].contains(where: { type.conforms(to: $0) }) {
            self = .document
        } else {
            self = .other
        }
    }

    var label: String {
        switch self {
        case .folder: return localized("Dossiers")
        case .application: return localized("Apps")
        case .image: return localized("Images")
        case .video: return localized("Vidéos")
        case .audio: return localized("Audio")
        case .archive: return localized("Archives")
        case .document: return localized("Documents")
        case .other: return localized("Autres")
        }
    }

    var icon: String {
        switch self {
        case .folder: return "folder.fill"
        case .application: return "app.fill"
        case .image: return "photo.fill"
        case .video: return "film.fill"
        case .audio: return "music.note"
        case .archive: return "archivebox.fill"
        case .document: return "doc.text.fill"
        case .other: return "doc.fill"
        }
    }

    var color: Color {
        switch self {
        case .folder: return Theme.sky
        case .application: return Theme.lavender
        case .image: return Theme.rose
        case .video: return Theme.amber
        case .audio: return Theme.lime
        case .archive: return Theme.coral
        case .document: return Theme.aqua
        case .other: return Color(white: 0.62)
        }
    }
}

struct PackedBubble: Identifiable, Equatable {
    let id: String
    /// `nil` pour la bulle qui regroupe les plus petits éléments.
    let entry: SizedEntry?
    let label: String
    let size: Int64
    let kind: FileKind
    let center: CGPoint
    let radius: CGFloat
}

/// Empilement glouton de cercles : surface proportionnelle à la taille, chaque bulle posée
/// contre deux voisines au plus près du centre. Coordonnées normalisées (plus grosse bulle : rayon 1).
enum BubblePacker {
    static let maxBubbles = 40
    private static let gap: CGFloat = 0.03
    private static let minimumRadius: CGFloat = 0.06

    private struct Item {
        let id: String
        let entry: SizedEntry?
        let label: String
        let size: Int64
        let kind: FileKind
    }

    private struct Disc {
        let center: CGPoint
        let radius: CGFloat
    }

    static func pack(_ entries: [SizedEntry]) -> [PackedBubble] {
        let sorted = entries.filter { $0.size > 0 }.sorted { $0.size > $1.size }
        guard let largest = sorted.first?.size else { return [] }

        var items = sorted.prefix(maxBubbles).map {
            Item(id: $0.url.path, entry: $0, label: $0.url.lastPathComponent, size: $0.size, kind: FileKind(entry: $0))
        }
        let rest = sorted.dropFirst(maxBubbles)
        if !rest.isEmpty {
            let restSize = rest.reduce(0) { $0 + $1.size }
            items.append(Item(id: "tidymymac.others", entry: nil, label: localized("\(rest.count) autres éléments"), size: restSize, kind: .other))
            items.sort { $0.size > $1.size }
        }

        var placed: [Disc] = []
        var bubbles: [PackedBubble] = []
        for item in items {
            let radius = max(CGFloat((Double(item.size) / Double(largest)).squareRoot()), minimumRadius)
            let center = position(for: radius, among: placed)
            placed.append(Disc(center: center, radius: radius))
            bubbles.append(PackedBubble(
                id: item.id, entry: item.entry, label: item.label, size: item.size,
                kind: item.kind, center: center, radius: radius
            ))
        }
        return bubbles
    }

    private static func position(for radius: CGFloat, among placed: [Disc]) -> CGPoint {
        guard let first = placed.first else { return .zero }
        if placed.count == 1 {
            return CGPoint(x: first.radius + radius + gap, y: 0)
        }
        var best: CGPoint?
        var bestDistance = CGFloat.infinity
        for i in placed.indices {
            for j in placed.indices where j > i {
                for candidate in tangentPoints(placed[i], placed[j], radius: radius) {
                    let distance = hypot(candidate.x, candidate.y)
                    guard distance < bestDistance, !overlaps(candidate, radius, placed) else { continue }
                    best = candidate
                    bestDistance = distance
                }
            }
        }
        // Repli improbable : à droite de tout ce qui est déjà placé.
        let rightEdge = placed.map { $0.center.x + $0.radius }.max() ?? 0
        return best ?? CGPoint(x: rightEdge + radius + gap, y: 0)
    }

    /// Les deux positions où un cercle de rayon `radius` touche à la fois `a` et `b`.
    private static func tangentPoints(_ a: Disc, _ b: Disc, radius: CGFloat) -> [CGPoint] {
        let ra = a.radius + radius + gap
        let rb = b.radius + radius + gap
        let dx = b.center.x - a.center.x
        let dy = b.center.y - a.center.y
        let d = hypot(dx, dy)
        guard d > 0, d <= ra + rb, d >= abs(ra - rb) else { return [] }
        let along = (ra * ra - rb * rb + d * d) / (2 * d)
        let h = sqrt(max(ra * ra - along * along, 0))
        let px = a.center.x + along * dx / d
        let py = a.center.y + along * dy / d
        return [
            CGPoint(x: px - h * dy / d, y: py + h * dx / d),
            CGPoint(x: px + h * dy / d, y: py - h * dx / d),
        ]
    }

    private static func overlaps(_ center: CGPoint, _ radius: CGFloat, _ placed: [Disc]) -> Bool {
        placed.contains { hypot($0.center.x - center.x, $0.center.y - center.y) < $0.radius + radius + gap - 0.0001 }
    }
}
