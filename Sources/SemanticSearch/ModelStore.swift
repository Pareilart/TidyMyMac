import CryptoKit
import Foundation

/// Modèle d'embeddings open source hébergé sur Hugging Face, figé à une révision précise.
public struct ModelDescriptor: Codable, Sendable, Hashable, Identifiable {
    public enum Pooling: String, Codable, Sendable {
        /// Moyenne des vecteurs de tous les jetons.
        case mean
        /// Vecteur du premier jeton ([CLS] ou <s>).
        case cls
    }

    struct File: Codable, Sendable, Hashable {
        let name: String
        let size: Int64
        /// Absente pour les petits fichiers d'un modèle personnalisé, que Hugging Face ne publie pas avec une empreinte SHA-256.
        let sha256: String?
    }

    public let repository: String
    let revision: String
    let folder: String
    public let name: String
    public let summary: String
    public let license: String
    public let languages: String
    public let dimension: Int
    public let pooling: Pooling
    public let queryPrefix: String
    public let passagePrefix: String
    public let isCustom: Bool
    let files: [File]

    public var id: String { repository }
    public var downloadSize: Int64 { files.reduce(0) { $0 + $1.size } }
    public var pageURL: URL? { URL(string: "https://huggingface.co/\(repository)") }
}

public enum ModelStore {
    static let supportedArchitectures: Set<String> = ["bert", "xlm-roberta", "roberta", "camembert"]
    private static let maxCustomModelSize: Int64 = 2_500_000_000

    /// Modèles vérifiés : architecture, tokenizer, poids et résultats testés avec TidyMyMac.
    public static var catalog: [ModelDescriptor] { [
        ModelDescriptor(
            repository: "intfloat/multilingual-e5-small", revision: "614241f622f53c4eeff9890bdc4f31cfecc418b3",
            folder: "multilingual-e5-small", name: "Multilingual E5 Small",
            summary: localized("Le meilleur compromis pour le français : précis, rapide et léger."),
            license: "MIT", languages: localized("Multilingue, dont le français"), dimension: 384, pooling: .mean,
            queryPrefix: "query: ", passagePrefix: "passage: ", isCustom: false,
            files: [
                .init(name: "config.json", size: 655, sha256: "69137736cab8b8903a07fe8afaafdda25aac55415a12a55d1bffa9f581abf959"),
                .init(name: "tokenizer.json", size: 17_082_730, sha256: "0b44a9d7b51c3c62626640cda0e2c2f70fdacdc25bbbd68038369d14ebdf4c39"),
                .init(name: "model.safetensors", size: 470_641_600, sha256: "1a55775f53449dac10a2bcbc312469fac40b96d53198c407081a831f81c98477"),
            ]
        ),
        ModelDescriptor(
            repository: "ibm-granite/granite-embedding-107m-multilingual", revision: "d6cffd338414d6a1c1f5decfad5fec62eebc90d5",
            folder: "granite-embedding-107m-multilingual", name: "Granite Embedding 107M",
            summary: localized("Le plus léger des modèles multilingues, conçu par IBM pour la recherche de documents."),
            license: "Apache 2.0", languages: localized("Multilingue, dont le français"), dimension: 384, pooling: .cls,
            queryPrefix: "", passagePrefix: "", isCustom: false,
            files: [
                .init(name: "config.json", size: 697, sha256: "aa3b6a5d1d6efeacdb844fb8ba773556463af2195003ad5e70a6f014d11be9cf"),
                .init(name: "tokenizer.json", size: 9_081_382, sha256: "7fc9e475f2ac473f070052d92b0c46ec2b91d9cd672935feb6fd837a65d33f78"),
                .init(name: "model.safetensors", size: 214_000_232, sha256: "ae6f20cc5dc433041118c900b652d87532e1335dade78c37765f0b94d1161283"),
            ]
        ),
        ModelDescriptor(
            repository: "sentence-transformers/paraphrase-multilingual-MiniLM-L12-v2", revision: "e8f8c211226b894fcb81acc59f3b34ba3efd5f42",
            folder: "paraphrase-multilingual-MiniLM-L12-v2", name: "Paraphrase Multilingual MiniLM",
            summary: localized("Spécialisé dans les phrases de sens proche, dans plus de 50 langues."),
            license: "Apache 2.0", languages: localized("Multilingue, dont le français"), dimension: 384, pooling: .mean,
            queryPrefix: "", passagePrefix: "", isCustom: false,
            files: [
                .init(name: "config.json", size: 645, sha256: "6300193cb75e01cf80c96decef7187dfb33094d97cc1490b7ead6ff134476e4e"),
                .init(name: "tokenizer.json", size: 9_081_518, sha256: "2c3387be76557bd40970cec13153b3bbf80407865484b209e655e5e4729076b8"),
                .init(name: "model.safetensors", size: 470_641_600, sha256: "eaa086f0ffee582aeb45b36e34cdd1fe2d6de2bef61f8a559a1bbc9bd955917b"),
            ]
        ),
        ModelDescriptor(
            repository: "intfloat/multilingual-e5-base", revision: "d128750597153bb5987e10b1c3493a34e5a4502a",
            folder: "multilingual-e5-base", name: "Multilingual E5 Base",
            summary: localized("Plus précis que la version Small, mais plus lourd et plus lent à indexer."),
            license: "MIT", languages: localized("Multilingue, dont le français"), dimension: 768, pooling: .mean,
            queryPrefix: "query: ", passagePrefix: "passage: ", isCustom: false,
            files: [
                .init(name: "config.json", size: 694, sha256: "9dab198f24c8c0879e481cf7822005d5ecbceedbacb390ffafa594e28d31bac4"),
                .init(name: "tokenizer.json", size: 17_082_660, sha256: "62c24cdc13d4c9952d63718d6c9fa4c287974249e16b7ade6d5a85e7bbb75626"),
                .init(name: "model.safetensors", size: 1_112_201_288, sha256: "a18a44fad1d0b46ded15928144138cff1135d5cc8233bdd90be5f18822de09a7"),
            ]
        ),
        ModelDescriptor(
            repository: "sentence-transformers/all-MiniLM-L6-v2", revision: "1110a243fdf4706b3f48f1d95db1a4f5529b4d41",
            folder: "all-MiniLM-L6-v2", name: "all-MiniLM-L6-v2",
            summary: localized("Très rapide et compact, mais conçu pour des documents en anglais."),
            license: "Apache 2.0", languages: localized("Anglais"), dimension: 384, pooling: .mean,
            queryPrefix: "", passagePrefix: "", isCustom: false,
            files: [
                .init(name: "config.json", size: 612, sha256: "953f9c0d463486b10a6871cc2fd59f223b2c70184f49815e7efbcab5d8908b41"),
                .init(name: "tokenizer.json", size: 466_247, sha256: "be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037"),
                .init(name: "model.safetensors", size: 90_868_376, sha256: "53aa51172d142c89d9012cce15ae4d6cc0ca6895895114379cacb4fab128d9db"),
            ]
        ),
    ] }

    public static var defaultModel: ModelDescriptor { catalog[0] }

    public static var rootDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TidyMyMac/Models", isDirectory: true)
    }

    public static func directory(for model: ModelDescriptor) -> URL {
        rootDirectory.appendingPathComponent(model.folder, isDirectory: true)
    }

    /// Les fichiers sont présents à la bonne taille (leur empreinte a été vérifiée au téléchargement).
    public static func isInstalled(_ model: ModelDescriptor, in directory: URL? = nil) -> Bool {
        let directory = directory ?? self.directory(for: model)
        return model.files.allSatisfy { size(of: directory.appendingPathComponent($0.name)) == $0.size }
    }

    public static func remove(_ model: ModelDescriptor) throws {
        let directory = directory(for: model)
        if FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.removeItem(at: directory)
        }
    }

    /// `progress` reçoit une fraction entre 0 et 1.
    public static func download(_ model: ModelDescriptor, to directory: URL? = nil,
                                progress: @escaping @Sendable (Double) -> Void) async throws {
        let directory = directory ?? self.directory(for: model)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let total = max(model.downloadSize, 1)
        var completed: Int64 = 0
        for file in model.files {
            let destination = directory.appendingPathComponent(file.name)
            if size(of: destination) == file.size {
                completed += file.size
                continue
            }
            guard let url = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)/\(file.name)") else {
                throw SemanticSearchError.download(localized("adresse invalide"))
            }
            let alreadyDone = completed
            let temporary = try await FileDownloader.download(url) { written in
                progress(Double(alreadyDone + written) / Double(total))
            }
            let intact = try size(of: temporary) == file.size && (file.sha256 == nil || sha256(of: temporary) == file.sha256)
            guard intact else {
                try? FileManager.default.removeItem(at: temporary)
                throw SemanticSearchError.download(localized("fichier \(file.name) incomplet ou modifié"))
            }
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: temporary, to: destination)
            completed += file.size
        }
        progress(1)
    }

    // MARK: - Modèles personnalisés

    private static var customModelsFile: URL { rootDirectory.appendingPathComponent("custom-models.json") }

    public static func customModels() -> [ModelDescriptor] {
        guard let data = try? Data(contentsOf: customModelsFile) else { return [] }
        return (try? JSONDecoder().decode([ModelDescriptor].self, from: data)) ?? []
    }

    public static func saveCustomModels(_ models: [ModelDescriptor]) throws {
        try FileManager.default.createDirectory(at: rootDirectory, withIntermediateDirectories: true)
        try JSONEncoder().encode(models).write(to: customModelsFile, options: .atomic)
    }

    /// Prépare un modèle depuis son identifiant Hugging Face (« propriétaire/modèle » ou adresse de sa page).
    /// Vérifie qu'il est compatible et lit ses réglages ; rien n'est encore téléchargé à ce stade.
    public static func resolve(_ input: String) async throws -> ModelDescriptor {
        var repository = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://huggingface.co/", "http://huggingface.co/", "huggingface.co/"] where repository.hasPrefix(prefix) {
            repository.removeFirst(prefix.count)
        }
        repository = repository.split(separator: "/").prefix(2).joined(separator: "/")
        guard repository.split(separator: "/").count == 2 else {
            throw SemanticSearchError.invalidModel(localized("indiquez le modèle sous la forme « propriétaire/modèle »"))
        }

        let info = try await json(from: "https://huggingface.co/api/models/\(repository)?blobs=true")
        guard let revision = info["sha"] as? String, let siblings = info["siblings"] as? [[String: Any]] else {
            throw SemanticSearchError.invalidModel(localized("dépôt introuvable ou privé"))
        }
        var available: [String: (size: Int64, sha256: String?)] = [:]
        for sibling in siblings {
            guard let name = sibling["rfilename"] as? String else { continue }
            let lfs = sibling["lfs"] as? [String: Any]
            let size = ((lfs?["size"] ?? sibling["size"]) as? NSNumber)?.int64Value ?? 0
            available[name] = (size, lfs?["sha256"] as? String)
        }
        let required = ["config.json", "tokenizer.json", "model.safetensors"]
        for name in required where available[name] == nil {
            throw SemanticSearchError.invalidModel(localized("le dépôt ne contient pas \(name) (format safetensors requis)"))
        }
        guard let weights = available["model.safetensors"], weights.size <= maxCustomModelSize else {
            throw SemanticSearchError.invalidModel(localized("modèle trop volumineux (plus de 2,5 Go)"))
        }

        let base = "https://huggingface.co/\(repository)/resolve/\(revision)/"
        let config = try await json(from: base + "config.json")
        let architecture = config["model_type"] as? String ?? "inconnue"
        guard supportedArchitectures.contains(architecture), let dimension = config["hidden_size"] as? Int else {
            throw SemanticSearchError.invalidModel(localized("architecture « \(architecture) » non prise en charge (BERT, RoBERTa, XLM-RoBERTa ou CamemBERT)"))
        }

        var pooling = ModelDescriptor.Pooling.mean
        if available["1_Pooling/config.json"] != nil,
           let poolingConfig = try? await json(from: base + "1_Pooling/config.json"),
           poolingConfig["pooling_mode_cls_token"] as? Bool == true {
            pooling = .cls
        }
        var queryPrefix = ""
        var passagePrefix = ""
        if available["config_sentence_transformers.json"] != nil,
           let settings = try? await json(from: base + "config_sentence_transformers.json"),
           let prompts = settings["prompts"] as? [String: String] {
            queryPrefix = prompts["query"] ?? ""
            passagePrefix = prompts["passage"] ?? prompts["document"] ?? ""
        } else if repository.lowercased().contains("e5") {
            // Convention de la famille E5.
            queryPrefix = "query: "
            passagePrefix = "passage: "
        }

        let card = info["cardData"] as? [String: Any]
        return ModelDescriptor(
            repository: repository, revision: revision,
            folder: repository.replacingOccurrences(of: "/", with: "--"),
            name: String(repository.split(separator: "/").last ?? Substring(repository)),
            summary: localized("Ajouté depuis Hugging Face (\(architecture), \(dimension) dimensions)."),
            license: card?["license"] as? String ?? localized("non précisée"),
            languages: localized("Voir la fiche du modèle"), dimension: dimension, pooling: pooling,
            queryPrefix: queryPrefix, passagePrefix: passagePrefix, isCustom: true,
            files: required.map { name in
                ModelDescriptor.File(name: name, size: available[name]!.size, sha256: available[name]!.sha256)
            }
        )
    }

    // MARK: - Outils

    private static func json(from address: String) async throws -> [String: Any] {
        guard let url = URL(string: address) else { throw SemanticSearchError.download(localized("adresse invalide")) }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let status = (response as? HTTPURLResponse)?.statusCode, status == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SemanticSearchError.invalidModel(localized("modèle introuvable, privé ou soumis à conditions sur Hugging Face"))
        }
        return object
    }

    private static func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    private static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

/// Téléchargement d'un fichier avec suivi de progression.
private final class FileDownloader: NSObject, URLSessionDownloadDelegate {
    private let progress: (Int64) -> Void
    private var continuation: CheckedContinuation<URL, Error>?
    private var lastReported: Int64 = 0

    private init(progress: @escaping (Int64) -> Void) {
        self.progress = progress
    }

    static func download(_ url: URL, progress: @escaping (Int64) -> Void) async throws -> URL {
        let downloader = FileDownloader(progress: progress)
        let session = URLSession(configuration: .default, delegate: downloader, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            downloader.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        // Au plus une mise à jour par mégaoctet, pour ne pas inonder l'interface.
        guard totalBytesWritten - lastReported >= 1 << 20 || totalBytesWritten == totalBytesExpectedToWrite else { return }
        lastReported = totalBytesWritten
        progress(totalBytesWritten)
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        if let response = downloadTask.response as? HTTPURLResponse, response.statusCode != 200 {
            finish(.failure(SemanticSearchError.download(localized("réponse HTTP \(response.statusCode)"))))
            return
        }
        // Le fichier temporaire est effacé dès le retour de cette méthode : on le déplace tout de suite.
        let kept = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: kept)
            finish(.success(kept))
        } catch {
            finish(.failure(error))
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<URL, Error>) {
        continuation?.resume(with: result)
        continuation = nil
    }
}
