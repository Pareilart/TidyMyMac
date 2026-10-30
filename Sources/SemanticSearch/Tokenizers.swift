import Foundation

/// Découpe un texte en identifiants de jetons, encadrés par les jetons spéciaux de début et de fin.
protocol TextTokenizer {
    func encode(_ text: String, maxLength: Int) -> [Int32]
}

/// Charge un tokenizer.json Hugging Face : Unigram (SentencePiece, famille XLM-RoBERTa) ou WordPiece (famille BERT).
enum TokenizerLoader {
    static func load(_ url: URL) throws -> TextTokenizer {
        let data = try Data(contentsOf: url)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let model = root["model"] as? [String: Any] else {
            throw SemanticSearchError.invalidModel(localized("tokenizer.json illisible"))
        }
        switch model["type"] as? String {
        case "Unigram": return try UnigramTokenizer(model: model)
        case "WordPiece": return try WordPieceTokenizer(root: root, model: model)
        case let type:
            let name = type ?? "?"
            throw SemanticSearchError.invalidModel(localized("tokenizer « \(name) » non pris en charge (Unigram ou WordPiece attendu)"))
        }
    }
}

/// Découpage : normalisation NFKC, espaces remplacés par « ▁ » avec un « ▁ » initial, puis segmentation
/// de Viterbi qui maximise la somme des log-probabilités des morceaux du vocabulaire.
final class UnigramTokenizer: TextTokenizer {
    private let ids: [String: Int32]
    private let scores: [Float]
    private let maxPieceLength: Int
    private let unknownID: Int32
    private let unknownScore: Float
    private let beginID: Int32
    private let endID: Int32

    init(model: [String: Any]) throws {
        guard let vocabulary = model["vocab"] as? [[Any]] else {
            throw SemanticSearchError.invalidModel(localized("vocabulaire Unigram absent"))
        }
        var ids = [String: Int32](minimumCapacity: vocabulary.count)
        var scores = [Float](repeating: 0, count: vocabulary.count)
        var longest = 1
        for (index, entry) in vocabulary.enumerated() {
            guard entry.count == 2, let piece = entry[0] as? String, let score = entry[1] as? NSNumber else { continue }
            ids[piece] = Int32(index)
            scores[index] = score.floatValue
            longest = max(longest, piece.count)
        }
        self.ids = ids
        self.scores = scores
        maxPieceLength = min(longest, 32)
        unknownID = Int32(model["unk_id"] as? Int ?? 3)
        // Comme SentencePiece : un caractère inconnu coûte plus cher que n'importe quel morceau connu.
        unknownScore = (scores.min() ?? 0) - 10
        beginID = ids["<s>"] ?? 0
        endID = ids["</s>"] ?? 2
    }

    func encode(_ text: String, maxLength: Int) -> [Int32] {
        let words = text.precomposedStringWithCompatibilityMapping.split(whereSeparator: { $0.isWhitespace })
        guard !words.isEmpty, maxLength > 2 else { return [beginID, endID] }
        let characters = Array("▁" + words.joined(separator: "▁"))
        let count = characters.count

        var best = [Float](repeating: -.infinity, count: count + 1)
        var start = [Int](repeating: 0, count: count + 1)
        var piece = [Int32](repeating: unknownID, count: count + 1)
        best[0] = 0
        for end in 1...count {
            for begin in max(0, end - maxPieceLength)..<end {
                guard let id = ids[String(characters[begin..<end])] else { continue }
                let score = best[begin] + scores[Int(id)]
                if score > best[end] {
                    best[end] = score
                    start[end] = begin
                    piece[end] = id
                }
            }
            if best[end] == -.infinity {
                best[end] = best[end - 1] + unknownScore
                start[end] = end - 1
                piece[end] = unknownID
            }
        }

        var tokens: [Int32] = []
        var position = count
        while position > 0 {
            let id = piece[position]
            // Les caractères inconnus consécutifs ne forment qu'un seul jeton.
            if id != unknownID || tokens.last != unknownID {
                tokens.append(id)
            }
            position = start[position]
        }
        tokens.reverse()
        return [beginID] + tokens.prefix(maxLength - 2) + [endID]
    }
}

/// Découpage BERT : minuscules et accents retirés si le modèle le demande, ponctuation isolée,
/// puis plus long préfixe du vocabulaire, les suites de mot étant notées « ## ».
final class WordPieceTokenizer: TextTokenizer {
    private let vocabulary: [String: Int32]
    private let lowercase: Bool
    private let stripAccents: Bool
    private let continuationPrefix: String
    private let maxCharactersPerWord: Int
    private let unknownID: Int32
    private let beginID: Int32
    private let endID: Int32

    init(root: [String: Any], model: [String: Any]) throws {
        guard let vocabulary = model["vocab"] as? [String: Int] else {
            throw SemanticSearchError.invalidModel(localized("vocabulaire WordPiece absent"))
        }
        self.vocabulary = vocabulary.mapValues { Int32($0) }
        let normalizer = root["normalizer"] as? [String: Any]
        lowercase = normalizer?["lowercase"] as? Bool ?? false
        // `strip_accents` absent ou nul : même choix que pour les minuscules, comme dans BERT.
        stripAccents = normalizer?["strip_accents"] as? Bool ?? lowercase
        continuationPrefix = model["continuing_subword_prefix"] as? String ?? "##"
        maxCharactersPerWord = model["max_input_chars_per_word"] as? Int ?? 100
        let unknownToken = model["unk_token"] as? String ?? "[UNK]"
        guard let unknownID = self.vocabulary[unknownToken],
              let beginID = self.vocabulary["[CLS]"],
              let endID = self.vocabulary["[SEP]"] else {
            throw SemanticSearchError.invalidModel(localized("jetons [CLS], [SEP] ou inconnu absents du vocabulaire"))
        }
        self.unknownID = unknownID
        self.beginID = beginID
        self.endID = endID
    }

    func encode(_ text: String, maxLength: Int) -> [Int32] {
        guard maxLength > 2 else { return [beginID, endID] }
        var normalized = text
        if lowercase { normalized = normalized.lowercased() }
        if stripAccents { normalized = normalized.folding(options: .diacriticInsensitive, locale: nil) }

        var words: [String] = []
        var current = ""
        for character in normalized {
            if character.isWhitespace || character.isNewline {
                if !current.isEmpty { words.append(current); current = "" }
            } else if character.isPunctuation || character.isSymbol {
                if !current.isEmpty { words.append(current); current = "" }
                words.append(String(character))
            } else {
                current.append(character)
            }
        }
        if !current.isEmpty { words.append(current) }

        var tokens: [Int32] = []
        for word in words {
            tokens += pieces(of: word)
            if tokens.count >= maxLength - 2 { break }
        }
        return [beginID] + tokens.prefix(maxLength - 2) + [endID]
    }

    private func pieces(of word: String) -> [Int32] {
        let characters = Array(word)
        guard characters.count <= maxCharactersPerWord else { return [unknownID] }
        var result: [Int32] = []
        var start = 0
        while start < characters.count {
            var end = characters.count
            var found: Int32?
            while start < end {
                let piece = (start > 0 ? continuationPrefix : "") + String(characters[start..<end])
                if let id = vocabulary[piece] {
                    found = id
                    break
                }
                end -= 1
            }
            // Un mot qu'aucune suite de morceaux ne couvre devient un seul jeton inconnu.
            guard let id = found else { return [unknownID] }
            result.append(id)
            start = end
        }
        return result
    }
}
