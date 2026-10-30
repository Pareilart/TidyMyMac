import Foundation
import SemanticSearch

// Vérifie la recherche sémantique sans l'interface :
//   swift run search-check [--model propriétaire/modèle] [--dir dossier-du-modèle] [dossier-à-indexer "demande"]
// Sans --model, utilise le modèle par défaut ; sans --dir, son emplacement habituel dans l'app.

func elapsed(since start: Date) -> String {
    String(format: "%.2f s", Date().timeIntervalSince(start))
}

var arguments = Array(CommandLine.arguments.dropFirst())

func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    let value = arguments[index + 1]
    arguments.removeSubrange(index...(index + 1))
    return value
}

let requested = option("--model")
let customDirectory = option("--dir").map { URL(fileURLWithPath: $0) }
var model = ModelStore.catalog.first { $0.repository == requested } ?? ModelStore.defaultModel
if let requested, model.repository != requested {
    model = try await ModelStore.resolve(requested)
}
let directory = customDirectory ?? ModelStore.directory(for: model)
print("Modèle : \(model.repository) (\(model.dimension) dimensions, \(model.pooling.rawValue), \(model.license))")

if !ModelStore.isInstalled(model, in: directory) {
    print("Téléchargement dans \(directory.path)…")
    try await ModelStore.download(model, to: directory) { fraction in
        print(String(format: "\r  %3.0f %%", fraction * 100), terminator: "")
        fflush(stdout)
    }
    print()
}

var start = Date()
let encoder = try SentenceEncoder(model: model, directory: directory)
print("Modèle chargé en \(elapsed(since: start))")

// Références : XLM-RoBERTa (Unigram) → [0, 35378, 8999, 2] ; BERT anglais sans majuscules (WordPiece) → [101, 7592, 2088, 102].
let tokens = encoder.tokenIDs("Hello world")
let references: [[Int32]] = [[0, 35378, 8999, 2], [101, 7592, 2088, 102]]
print("Jetons de « Hello world » : \(tokens) \(references.contains(tokens) ? "✓" : "✗ (aucune référence connue)")")

let english = model.languages == "Anglais"
let queries = english
    ? ["home insurance liability certificate", "electricity bill", "employment contract"]
    : ["assurance responsabilité civile", "facture d'électricité", "contrat de travail"]
let passages = english
    ? ["Certificate of personal liability insurance, valid for the year 2025.",
       "Electricity bill: January consumption, total amount 84.20 euros.",
       "Permanent employment contract between the employer and the employee.",
       "Pancake recipe: flour, eggs, milk and a pinch of salt."]
    : ["Attestation d'assurance responsabilité civile vie privée valable pour l'année 2025.",
       "Facture EDF : consommation d'électricité de janvier, montant TTC 84,20 euros.",
       "Contrat de travail à durée indéterminée entre l'employeur et le salarié.",
       "Recette des crêpes : farine, œufs, lait et une pincée de sel."]
start = Date()
let passageVectors = passages.map { encoder.embedPassage($0) }
print("4 passages encodés en \(elapsed(since: start))")

var allCorrect = true
for (index, query) in queries.enumerated() {
    let vector = encoder.embedQuery(query)
    let similarities = passageVectors.map { zip(vector, $0).reduce(0) { $0 + $1.0 * $1.1 } }
    let best = similarities.indices.max { similarities[$0] < similarities[$1] } ?? -1
    allCorrect = allCorrect && best == index
    let scores = similarities.map { String(format: "%.3f", $0) }.joined(separator: "  ")
    print("\(best == index ? "✓" : "✗") \(query)  →  \(scores)")
}
print(allCorrect ? "Encodeur : classement correct." : "Encodeur : classement INCORRECT.")

if arguments.count >= 2 {
    let folder = URL(fileURLWithPath: arguments[0])
    start = Date()
    guard let index = DocumentIndexer.build(folders: [folder], encoder: encoder, previous: nil, ocr: true, progress: { _ in }) else {
        exit(1)
    }
    print("\n\(index.documents.count) documents indexés en \(elapsed(since: start))")
    let query = QueryParser.prepare(arguments[1])
    print("Demande : « \(query.text) » · mots-clés : \(query.keywords)")
    for hit in index.search(query, encoder: encoder, limit: 5) {
        print(String(format: "  %.3f  ", hit.score) + hit.url.lastPathComponent + "  —  " + hit.snippet.prefix(70))
    }
}
