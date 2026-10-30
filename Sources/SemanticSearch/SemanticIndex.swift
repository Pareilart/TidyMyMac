import Accelerate
import Foundation

public struct SearchHit: Identifiable, Sendable {
    public let url: URL
    /// Similarité sémantique (cosinus) plus un léger bonus quand les mots de la demande apparaissent.
    public let score: Float
    /// Pertinence entre 0 et 1, relative aux autres documents de l'index : chaque modèle a sa propre échelle de scores.
    public let relevance: Double
    public let snippet: String
    public let modified: Date
    public var id: URL { url }

    public init(url: URL, score: Float, relevance: Double, snippet: String, modified: Date) {
        self.url = url
        self.score = score
        self.relevance = relevance
        self.snippet = snippet
        self.modified = modified
    }
}

/// Index des documents pour un modèle donné : quelques passages de texte par fichier et leurs vecteurs.
/// Enregistré dans `index.json` (métadonnées) et `vectors.bin` (Float32 bruts), un dossier par modèle.
public struct SemanticIndex: Sendable {
    public struct Document: Codable, Sendable {
        public let path: String
        public let modified: Date
        public let passages: [String]
        let firstVector: Int
    }

    private struct Manifest: Codable {
        let version: Int
        let modelID: String
        let dimension: Int
        let updatedAt: Date
        let documents: [Document]
    }

    public let modelID: String
    public let dimension: Int
    public private(set) var documents: [Document] = []
    public private(set) var updatedAt: Date?
    private var vectors: [Float] = []

    public init(modelID: String, dimension: Int) {
        self.modelID = modelID
        self.dimension = dimension
    }

    public static var rootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TidyMyMac/Search", isDirectory: true)
    }

    public static func directory(for model: ModelDescriptor) -> URL {
        rootDirectory.appendingPathComponent(model.folder, isDirectory: true)
    }

    private var passageCount: Int { vectors.count / dimension }

    mutating func append(path: String, modified: Date, passages: [String], vectors passageVectors: [Float]) {
        documents.append(Document(path: path, modified: modified, passages: passages, firstVector: passageCount))
        vectors += passageVectors
    }

    mutating func markUpdated() {
        updatedAt = Date()
    }

    func vectors(of document: Document) -> [Float] {
        Array(vectors[(document.firstVector * dimension)..<((document.firstVector + document.passages.count) * dimension)])
    }

    // MARK: - Recherche

    public func search(_ query: PreparedQuery, encoder: SentenceEncoder, limit: Int = 20) -> [SearchHit] {
        // Des vecteurs d'un autre modèle ne sont pas comparables.
        guard passageCount > 0, encoder.model.id == modelID, encoder.dimension == dimension else { return [] }
        let queryVector = encoder.embedQuery(query.text)
        var similarities = [Float](repeating: 0, count: passageCount)
        vDSP_mmul(vectors, 1, queryVector, 1, &similarities, 1, vDSP_Length(passageCount), 1, vDSP_Length(dimension))

        var candidates: [(document: Document, passage: String, score: Float)] = []
        for document in documents where !document.passages.isEmpty {
            let range = document.firstVector..<(document.firstVector + document.passages.count)
            guard let best = range.max(by: { similarities[$0] < similarities[$1] }) else { continue }
            let name = QueryParser.fold(URL(fileURLWithPath: document.path).lastPathComponent)
            let passage = document.passages[best - document.firstVector]
            let foldedPassage = QueryParser.fold(passage)
            var bonus: Float = 0
            for keyword in query.keywords {
                if name.contains(keyword) {
                    bonus += 0.03
                } else if foldedPassage.contains(keyword) {
                    bonus += 0.01
                }
            }
            candidates.append((document, passage, similarities[best] + min(bonus, 0.08)))
        }
        guard let top = candidates.map(\.score).max() else { return [] }

        // Pertinence : écart au score moyen, en écarts-types (index fourni) ou rapporté au meilleur score (petit index).
        let scores = candidates.map { Double($0.score) }
        let mean = scores.reduce(0, +) / Double(scores.count)
        let deviation = (scores.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(scores.count)).squareRoot()
        func relevance(of score: Float) -> Double {
            let value = scores.count >= 20 && deviation > 0
                ? ((Double(score) - mean) / deviation - 1) / 2
                : (Double(score) - mean) / max(Double(top) - mean, 1e-6)
            return min(max(value, 0), 1)
        }

        return candidates
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { candidate in
                SearchHit(
                    url: URL(fileURLWithPath: candidate.document.path),
                    score: candidate.score,
                    relevance: relevance(of: candidate.score),
                    snippet: String(candidate.passage.prefix(240)),
                    modified: candidate.document.modified
                )
            }
    }

    // MARK: - Enregistrement

    public func save(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let manifest = Manifest(version: 2, modelID: modelID, dimension: dimension, updatedAt: updatedAt ?? Date(), documents: documents)
        try JSONEncoder().encode(manifest).write(to: directory.appendingPathComponent("index.json"), options: .atomic)
        try vectors.withUnsafeBufferPointer { Data(buffer: $0) }
            .write(to: directory.appendingPathComponent("vectors.bin"), options: .atomic)
    }

    public static func load(from directory: URL, for model: ModelDescriptor) -> SemanticIndex? {
        guard let manifestData = try? Data(contentsOf: directory.appendingPathComponent("index.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: manifestData),
              manifest.version == 2, manifest.modelID == model.id, manifest.dimension > 0,
              let vectorData = try? Data(contentsOf: directory.appendingPathComponent("vectors.bin")) else { return nil }
        let expected = manifest.documents.reduce(0) { $0 + $1.passages.count } * manifest.dimension
        guard vectorData.count == expected * MemoryLayout<Float>.size else { return nil }
        var index = SemanticIndex(modelID: manifest.modelID, dimension: manifest.dimension)
        index.documents = manifest.documents
        index.updatedAt = manifest.updatedAt
        index.vectors = vectorData.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        return index
    }

    public static func remove(at directory: URL) throws {
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }
}

// MARK: - Indexation

public struct IndexingProgress: Sendable {
    public let done: Int
    public let total: Int
    public let current: String

    public init(done: Int, total: Int, current: String) {
        self.done = done
        self.total = total
        self.current = current
    }
}

public enum DocumentIndexer {
    private static let passageLength = 450
    private static let maxPassages = 4
    private static let maxFileSize = 80_000_000
    private static let batchSize = 8

    public static var defaultFolders: [URL] {
        [.documentDirectory, .downloadsDirectory, .desktopDirectory]
            .compactMap { FileManager.default.urls(for: $0, in: .userDomainMask).first }
    }

    private struct Candidate {
        let url: URL
        let modified: Date
    }

    private struct Entry {
        let passages: [String]
        let vectors: [Float]
    }

    /// Construit un nouvel index ; les fichiers inchangés depuis `previous` (même modèle) ne sont pas réencodés.
    /// Renvoie `nil` si la tâche est annulée.
    public static func build(
        folders: [URL], encoder: SentenceEncoder, previous: SemanticIndex?, ocr: Bool,
        progress: @escaping @Sendable (IndexingProgress) -> Void
    ) -> SemanticIndex? {
        let candidates = findCandidates(in: folders)
        let reusable = previous?.modelID == encoder.model.id ? previous : nil
        var known: [String: SemanticIndex.Document] = [:]
        for document in reusable?.documents ?? [] {
            known[document.path] = document
        }

        var index = SemanticIndex(modelID: encoder.model.id, dimension: encoder.dimension)
        var start = 0
        while start < candidates.count {
            if Task.isCancelled { return nil }
            let batch = Array(candidates[start..<min(start + batchSize, candidates.count)])
            progress(IndexingProgress(done: start, total: candidates.count, current: batch[0].url.lastPathComponent))

            var entries = [Entry?](repeating: nil, count: batch.count)
            entries.withUnsafeMutableBufferPointer { output in
                let output = output
                DispatchQueue.concurrentPerform(iterations: batch.count) { position in
                    let candidate = batch[position]
                    if let document = known[candidate.url.path],
                       abs(document.modified.timeIntervalSince(candidate.modified)) < 1,
                       let reusable {
                        output[position] = Entry(passages: document.passages, vectors: reusable.vectors(of: document))
                    } else {
                        output[position] = encode(candidate.url, encoder: encoder, ocr: ocr)
                    }
                }
            }
            for (candidate, entry) in zip(batch, entries) {
                guard let entry else { continue }
                index.append(path: candidate.url.path, modified: candidate.modified, passages: entry.passages, vectors: entry.vectors)
            }
            start += batch.count
        }
        progress(IndexingProgress(done: candidates.count, total: candidates.count, current: ""))
        index.markUpdated()
        return index
    }

    private static func findCandidates(in folders: [URL]) -> [Candidate] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]
        var seen = Set<String>()
        var candidates: [Candidate] = []
        for folder in folders {
            guard let enumerator = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: Array(keys),
                options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }
            ) else { continue }
            for case let url as URL in enumerator {
                guard DocumentText.supportedExtensions.contains(url.pathExtension.lowercased()),
                      let values = try? url.resourceValues(forKeys: keys),
                      values.isRegularFile == true,
                      (values.fileSize ?? 0) <= maxFileSize,
                      seen.insert(url.path).inserted else { continue }
                candidates.append(Candidate(url: url, modified: values.contentModificationDate ?? .distantPast))
            }
        }
        return candidates
    }

    /// Le nom du fichier et de son dossier précèdent chaque passage : ils décrivent souvent le mieux le document.
    private static func encode(_ url: URL, encoder: SentenceEncoder, ocr: Bool) -> Entry {
        let text = DocumentText.extract(from: url, ocr: ocr)
        let name = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let header = "\(url.deletingLastPathComponent().lastPathComponent) / \(name)"
        let passages = split(text)
        var vectors: [Float] = []
        for passage in passages {
            vectors += encoder.embedPassage("\(header)\n\(passage)")
        }
        return Entry(passages: passages, vectors: vectors)
    }

    private static func split(_ text: String) -> [String] {
        var passages: [String] = []
        var current: [Substring] = []
        var length = 0
        for word in text.split(whereSeparator: { $0.isWhitespace }) {
            if length + word.count > passageLength, !current.isEmpty {
                passages.append(current.joined(separator: " "))
                current = []
                length = 0
                if passages.count == maxPassages { break }
            }
            current.append(word)
            length += word.count + 1
        }
        if !current.isEmpty, passages.count < maxPassages {
            passages.append(current.joined(separator: " "))
        }
        // Sans texte lisible, le document reste trouvable par son nom.
        return passages.isEmpty ? [""] : passages
    }
}

// MARK: - Demande

public struct PreparedQuery: Sendable {
    /// Demande sans formule d'introduction ; l'encodeur y ajoute le préfixe propre au modèle.
    public let text: String
    public let keywords: [String]
}

public enum QueryParser {
    private static let commandPattern =
        #"^(re)?(trouve|cherche)(r|z)?(-moi)?\s+|^(montre|affiche|ouvre)(r|z)?(-moi)?\s+|^o[uù] (est|sont)\s+|^(find|search( for)?|show( me)?|where is)\s+"#

    private static let stopWords: Set<String> = [
        "le", "la", "les", "l", "un", "une", "des", "de", "du", "d", "mon", "ma", "mes", "ton", "ta", "tes", "son", "sa",
        "ses", "notre", "nos", "votre", "vos", "leur", "leurs", "et", "ou", "a", "au", "aux", "en", "pour", "par", "sur",
        "dans", "avec", "sans", "ce", "cet", "cette", "ces", "qui", "que", "quoi", "est", "sont", "je", "j", "me", "moi",
        "trouver", "trouve", "retrouver", "retrouve", "chercher", "cherche", "rechercher", "recherche", "montre", "affiche",
        "fichier", "fichiers", "document", "documents", "the", "my", "find", "an", "of", "for", "file",
    ]

    /// Retire la formule d'introduction (« Trouver mon… ») et garde les mots significatifs pour le bonus lexical.
    public static func prepare(_ query: String) -> PreparedQuery {
        var cleaned = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if let range = cleaned.range(of: commandPattern, options: [.regularExpression, .caseInsensitive]) {
            cleaned.removeSubrange(range)
        }
        let keywords = fold(cleaned)
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 2 && !stopWords.contains($0) }
        return PreparedQuery(text: cleaned, keywords: keywords)
    }

    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }
}
