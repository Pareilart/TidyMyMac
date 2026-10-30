import Foundation
import SemanticSearch

/// Recherche de documents en langage naturel avec un modèle d'embeddings open source exécuté sur le Mac.
@MainActor
final class SmartSearchModel: ObservableObject {
    enum ModelState: Equatable {
        case missing
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    static var examples: [String] { [
        localized("Mon assurance responsabilité civile"),
        localized("Facture d'électricité"),
        localized("Contrat de travail"),
        localized("Avis d'imposition"),
        localized("Relevé bancaire"),
    ] }
    private static let selectedModelKey = "searchModelID"

    @Published private(set) var selectedModel: ModelDescriptor
    @Published private(set) var customModels = ModelStore.customModels()
    @Published private(set) var modelState: ModelState
    @Published private(set) var indexing: IndexingProgress?
    @Published private(set) var documentCount = 0
    @Published private(set) var indexDate: Date?
    @Published var query = ""
    @Published private(set) var results: [SearchHit] = []
    @Published private(set) var searchedQuery: String?
    @Published private(set) var searching = false
    @Published var useOCR = UserDefaults.standard.object(forKey: "searchUsesOCR") as? Bool ?? true {
        didSet { UserDefaults.standard.set(useOCR, forKey: "searchUsesOCR") }
    }

    // Choix du modèle
    @Published var showingModelPicker = false
    @Published var customRepository = ""
    @Published private(set) var resolvingCustomModel = false
    @Published private(set) var customModelError: String?

    private var encoder: SentenceEncoder?
    private var index: SemanticIndex?
    private var indexingTask: Task<SemanticIndex?, Never>?
    /// Données fictives affichées pour les captures d'écran du README.
    private var isDemo = false

    init() {
        let savedID = UserDefaults.standard.string(forKey: Self.selectedModelKey)
        let model = (ModelStore.catalog + ModelStore.customModels()).first { $0.id == savedID } ?? ModelStore.defaultModel
        selectedModel = model
        modelState = ModelStore.isInstalled(model) ? .loading : .missing
    }

    var availableModels: [ModelDescriptor] { ModelStore.catalog + customModels }
    var hasIndex: Bool { index != nil || isDemo }

    /// Affiche des résultats fictifs, sans modèle ni index (captures d'écran du README).
    func showDemo(query: String, results: [SearchHit], documentCount: Int) {
        isDemo = true
        modelState = .ready
        self.query = query
        self.results = results
        searchedQuery = query
        self.documentCount = documentCount
        indexDate = Date().addingTimeInterval(-3 * 3600)
    }

    /// Charge le modèle choisi et son index à la première ouverture du module.
    func prepare() async {
        let model = selectedModel
        guard !isDemo, encoder == nil, ModelStore.isInstalled(model) else { return }
        modelState = .loading
        do {
            let loaded = try await Task.detached(priority: .userInitiated) { () throws -> (SentenceEncoder, SemanticIndex?) in
                (try SentenceEncoder(model: model), SemanticIndex.load(from: SemanticIndex.directory(for: model), for: model))
            }.value
            // Le modèle a pu changer pendant le chargement.
            guard model.id == selectedModel.id else { return }
            encoder = loaded.0
            apply(loaded.1)
            modelState = .ready
        } catch {
            if model.id == selectedModel.id { modelState = .failed(error.localizedDescription) }
        }
    }

    func downloadModel() async {
        let model = selectedModel
        modelState = .downloading(0)
        let report: @Sendable (Double) -> Void = { [weak self] fraction in
            Task { @MainActor in
                if self?.selectedModel.id == model.id { self?.modelState = .downloading(fraction) }
            }
        }
        do {
            try await ModelStore.download(model, progress: report)
            guard model.id == selectedModel.id else { return }
            await prepare()
            // Premier lancement avec ce modèle : on indexe tout de suite les dossiers habituels.
            if index == nil { reindex() }
        } catch {
            if model.id == selectedModel.id { modelState = .failed(error.localizedDescription) }
        }
    }

    func reindex() {
        guard let encoder, indexingTask == nil else { return }
        let model = selectedModel
        let previous = index
        let ocr = useOCR
        indexing = IndexingProgress(done: 0, total: 0, current: "")
        let report: @Sendable (IndexingProgress) -> Void = { [weak self] progress in
            Task { @MainActor in
                if self?.indexingTask != nil { self?.indexing = progress }
            }
        }
        let task = Task.detached(priority: .utility) {
            DocumentIndexer.build(
                folders: DocumentIndexer.defaultFolders, encoder: encoder, previous: previous, ocr: ocr, progress: report
            )
        }
        indexingTask = task
        Task {
            let built = await task.value
            indexingTask = nil
            indexing = nil
            guard let built else { return }
            try? built.save(to: SemanticIndex.directory(for: model))
            guard model.id == selectedModel.id else { return }
            apply(built)
            if searchedQuery != nil { await search() }
        }
    }

    func cancelIndexing() {
        indexingTask?.cancel()
    }

    func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, let encoder, let index else { return }
        searching = true
        let prepared = QueryParser.prepare(text)
        results = await Task.detached(priority: .userInitiated) { index.search(prepared, encoder: encoder, limit: 15) }.value
        searchedQuery = text
        searching = false
    }

    func search(example: String) async {
        query = example
        await search()
    }

    func clearResults() {
        query = ""
        results = []
        searchedQuery = nil
    }

    // MARK: - Choix du modèle

    func isInstalled(_ model: ModelDescriptor) -> Bool {
        ModelStore.isInstalled(model)
    }

    /// Change de modèle. Chaque modèle a son propre index : un modèle déjà utilisé retrouve le sien.
    func select(_ model: ModelDescriptor) {
        guard model.id != selectedModel.id else { return }
        cancelIndexing()
        selectedModel = model
        UserDefaults.standard.set(model.id, forKey: Self.selectedModelKey)
        encoder = nil
        apply(nil)
        results = []
        searchedQuery = nil
        modelState = ModelStore.isInstalled(model) ? .loading : .missing
        guard modelState == .loading else { return }
        Task {
            await prepare()
            if index == nil { reindex() }
        }
    }

    /// Ajoute un modèle depuis son identifiant Hugging Face, après avoir vérifié sa compatibilité.
    func addCustomModel() async {
        let input = customRepository
        resolvingCustomModel = true
        customModelError = nil
        do {
            let model = try await ModelStore.resolve(input)
            if !availableModels.contains(where: { $0.id == model.id }) {
                customModels.append(model)
                try ModelStore.saveCustomModels(customModels)
            }
            customRepository = ""
            select(availableModels.first { $0.id == model.id } ?? model)
        } catch {
            customModelError = error.localizedDescription
        }
        resolvingCustomModel = false
    }

    /// Supprime les fichiers d'un modèle et son index ; un modèle personnalisé disparaît aussi de la liste.
    func deleteModel(_ model: ModelDescriptor) {
        let wasSelected = model.id == selectedModel.id
        if wasSelected {
            cancelIndexing()
            encoder = nil
            apply(nil)
            results = []
            searchedQuery = nil
        }
        try? ModelStore.remove(model)
        try? SemanticIndex.remove(at: SemanticIndex.directory(for: model))
        if model.isCustom {
            customModels.removeAll { $0.id == model.id }
            try? ModelStore.saveCustomModels(customModels)
        }
        guard wasSelected else { return }
        if model.isCustom {
            select(ModelStore.defaultModel)
        } else {
            modelState = .missing
        }
    }

    /// Supprime tous les modèles téléchargés et tous les index.
    func removeAll() {
        cancelIndexing()
        encoder = nil
        apply(nil)
        results = []
        searchedQuery = nil
        try? FileManager.default.removeItem(at: ModelStore.rootDirectory)
        try? SemanticIndex.remove(at: SemanticIndex.rootDirectory)
        customModels = []
        selectedModel = ModelStore.defaultModel
        UserDefaults.standard.removeObject(forKey: Self.selectedModelKey)
        modelState = .missing
    }

    private func apply(_ index: SemanticIndex?) {
        self.index = index
        documentCount = index?.documents.count ?? 0
        indexDate = index?.updatedAt
    }
}
