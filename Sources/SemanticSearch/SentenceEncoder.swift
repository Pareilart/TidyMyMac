import Accelerate
import Foundation

/// Encodeur de phrases (architectures BERT et RoBERTa) exécuté sur le CPU avec Accelerate.
///
/// Donne un vecteur de norme 1 : la similarité de deux textes est le produit scalaire de leurs vecteurs.
public final class SentenceEncoder: @unchecked Sendable {
    public let model: ModelDescriptor
    public let dimension: Int

    private let tokenizer: TextTokenizer
    private let weights: SafeTensors
    private let wordEmbeddings: SafeTensors.Tensor
    private let positionEmbeddings: [Float]
    private let positionOffset: Int
    private let tokenTypeEmbedding: [Float]
    private let maxTokens: Int
    private let embeddingNorm: LayerNorm
    private let layers: [EncoderLayer]

    public convenience init(model: ModelDescriptor) throws {
        try self.init(model: model, directory: ModelStore.directory(for: model))
    }

    public init(model: ModelDescriptor, directory: URL) throws {
        self.model = model
        let config = try ModelConfig(url: directory.appendingPathComponent("config.json"))
        tokenizer = try TokenizerLoader.load(directory.appendingPathComponent("tokenizer.json"))
        let weights = try SafeTensors(url: directory.appendingPathComponent("model.safetensors"))
        self.weights = weights

        // Les poids sont parfois enregistrés sous le nom du modèle complet (« bert. », « roberta. »…).
        guard let prefix = ["", "bert.", "roberta.", "model."].first(where: { weights.contains("\($0)embeddings.word_embeddings.weight") }) else {
            throw SemanticSearchError.invalidModel(localized("table d'embeddings introuvable"))
        }
        wordEmbeddings = try weights.tensor(prefix + "embeddings.word_embeddings.weight")
        guard SafeTensors.byteWidth(wordEmbeddings.dtype) != nil,
              wordEmbeddings.shape.count == 2, wordEmbeddings.shape[1] == config.hiddenSize else {
            throw SemanticSearchError.invalidModel(localized("table d'embeddings inattendue"))
        }
        dimension = config.hiddenSize
        positionEmbeddings = try weights.floats(prefix + "embeddings.position_embeddings.weight")
        // RoBERTa et ses dérivés numérotent les positions à partir de pad_token_id + 1.
        positionOffset = config.isRoBERTa ? config.padTokenID + 1 : 0
        maxTokens = positionEmbeddings.count / config.hiddenSize - positionOffset
        let tokenTypes = (try? weights.floats(prefix + "embeddings.token_type_embeddings.weight")) ?? []
        tokenTypeEmbedding = tokenTypes.count >= config.hiddenSize
            ? Array(tokenTypes.prefix(config.hiddenSize))
            : [Float](repeating: 0, count: config.hiddenSize)
        embeddingNorm = try LayerNorm(weights, prefix: prefix + "embeddings.LayerNorm", epsilon: config.layerNormEpsilon)

        var layers: [EncoderLayer] = []
        while weights.contains("\(prefix)encoder.layer.\(layers.count).attention.self.query.weight") {
            layers.append(try EncoderLayer(
                weights, prefix: "\(prefix)encoder.layer.\(layers.count)", heads: config.heads, epsilon: config.layerNormEpsilon
            ))
        }
        guard !layers.isEmpty, maxTokens > 2 else { throw SemanticSearchError.invalidModel(localized("aucune couche d'encodeur")) }
        self.layers = layers
    }

    public func tokenIDs(_ text: String) -> [Int32] {
        tokenizer.encode(text, maxLength: maxTokens)
    }

    /// Vecteur d'une demande de recherche (avec le préfixe attendu par le modèle, par exemple « query: »).
    public func embedQuery(_ text: String) -> [Float] {
        embed(model.queryPrefix + text)
    }

    /// Vecteur d'un passage de document (avec le préfixe attendu par le modèle, par exemple « passage: »).
    public func embedPassage(_ text: String) -> [Float] {
        embed(model.passagePrefix + text)
    }

    public func embed(_ text: String, maxTokens limit: Int = 128) -> [Float] {
        let width = dimension
        let vocabularySize = wordEmbeddings.shape[0]
        let tokens = tokenizer.encode(text, maxLength: min(limit, maxTokens))
        let rows = tokens.count

        var hidden = [Float](repeating: 0, count: rows * width)
        hidden.withUnsafeMutableBufferPointer { buffer in
            for (row, token) in tokens.enumerated() {
                let destination = buffer.baseAddress! + row * width
                weights.copyRow(min(Int(token), vocabularySize - 1), of: wordEmbeddings, into: destination)
                let position = (row + positionOffset) * width
                for column in 0..<width {
                    destination[column] += positionEmbeddings[position + column] + tokenTypeEmbedding[column]
                }
            }
        }
        embeddingNorm.apply(&hidden, rows: rows)
        for layer in layers {
            hidden = layer(hidden, rows: rows)
        }

        var pooled = [Float](repeating: 0, count: width)
        switch model.pooling {
        case .cls:
            for column in 0..<width {
                pooled[column] = hidden[column]
            }
        case .mean:
            // La division par le nombre de jetons est absorbée par la normalisation.
            for row in 0..<rows {
                for column in 0..<width {
                    pooled[column] += hidden[row * width + column]
                }
            }
        }
        var squares: Float = 0
        vDSP_svesq(pooled, 1, &squares, vDSP_Length(width))
        let scale = squares > 0 ? 1 / squares.squareRoot() : 0
        return pooled.map { $0 * scale }
    }
}

/// Réglages lus dans le config.json Hugging Face du modèle.
private struct ModelConfig {
    let hiddenSize: Int
    let heads: Int
    let layerNormEpsilon: Float
    let isRoBERTa: Bool
    let padTokenID: Int

    init(url: URL) throws {
        guard let config = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any] else {
            throw SemanticSearchError.invalidModel(localized("config.json illisible"))
        }
        let architecture = config["model_type"] as? String ?? "inconnue"
        guard ModelStore.supportedArchitectures.contains(architecture) else {
            throw SemanticSearchError.invalidModel(localized("architecture « \(architecture) » non prise en charge"))
        }
        guard (config["hidden_act"] as? String ?? "gelu").hasPrefix("gelu") else {
            throw SemanticSearchError.invalidModel(localized("fonction d'activation non prise en charge"))
        }
        guard let hiddenSize = config["hidden_size"] as? Int,
              let heads = config["num_attention_heads"] as? Int,
              heads > 0, hiddenSize % heads == 0 else {
            throw SemanticSearchError.invalidModel(localized("dimensions du modèle absentes"))
        }
        self.hiddenSize = hiddenSize
        self.heads = heads
        layerNormEpsilon = (config["layer_norm_eps"] as? NSNumber)?.floatValue ?? 1e-12
        isRoBERTa = architecture != "bert"
        padTokenID = config["pad_token_id"] as? Int ?? 1
    }
}

// MARK: - Couches

/// Couche linéaire y = x·Wᵀ + b. Les poids sont transposés au chargement pour `vDSP_mmul`.
private struct Linear {
    let weight: [Float]
    let bias: [Float]
    let inputs: Int
    let outputs: Int

    init(_ tensors: SafeTensors, prefix: String) throws {
        let shape = try tensors.tensor("\(prefix).weight").shape
        guard shape.count == 2 else { throw SemanticSearchError.invalidModel(localized("matrice inattendue : \(prefix)")) }
        outputs = shape[0]
        inputs = shape[1]
        let original = try tensors.floats("\(prefix).weight")
        var transposed = [Float](repeating: 0, count: original.count)
        vDSP_mtrans(original, 1, &transposed, 1, vDSP_Length(inputs), vDSP_Length(outputs))
        weight = transposed
        bias = try tensors.floats("\(prefix).bias")
    }

    func callAsFunction(_ x: [Float], rows: Int) -> [Float] {
        var y = [Float](repeating: 0, count: rows * outputs)
        vDSP_mmul(x, 1, weight, 1, &y, 1, vDSP_Length(rows), vDSP_Length(outputs), vDSP_Length(inputs))
        y.withUnsafeMutableBufferPointer { output in
            bias.withUnsafeBufferPointer { bias in
                for row in 0..<rows {
                    let line = output.baseAddress! + row * outputs
                    vDSP_vadd(line, 1, bias.baseAddress!, 1, line, 1, vDSP_Length(outputs))
                }
            }
        }
        return y
    }
}

private struct LayerNorm {
    let gamma: [Float]
    let beta: [Float]
    let epsilon: Float

    init(_ tensors: SafeTensors, prefix: String, epsilon: Float) throws {
        gamma = try tensors.floats("\(prefix).weight")
        beta = try tensors.floats("\(prefix).bias")
        self.epsilon = epsilon
    }

    func apply(_ x: inout [Float], rows: Int) {
        let width = gamma.count
        x.withUnsafeMutableBufferPointer { buffer in
            for row in 0..<rows {
                let line = buffer.baseAddress! + row * width
                var mean: Float = 0
                vDSP_meanv(line, 1, &mean, vDSP_Length(width))
                var variance: Float = 0
                for column in 0..<width {
                    let delta = line[column] - mean
                    variance += delta * delta
                }
                let inverse = 1 / (variance / Float(width) + epsilon).squareRoot()
                for column in 0..<width {
                    line[column] = (line[column] - mean) * inverse * gamma[column] + beta[column]
                }
            }
        }
    }
}

private struct EncoderLayer {
    let query: Linear
    let key: Linear
    let value: Linear
    let attentionOutput: Linear
    let attentionNorm: LayerNorm
    let intermediate: Linear
    let output: Linear
    let outputNorm: LayerNorm
    let heads: Int

    init(_ tensors: SafeTensors, prefix: String, heads: Int, epsilon: Float) throws {
        query = try Linear(tensors, prefix: "\(prefix).attention.self.query")
        key = try Linear(tensors, prefix: "\(prefix).attention.self.key")
        value = try Linear(tensors, prefix: "\(prefix).attention.self.value")
        attentionOutput = try Linear(tensors, prefix: "\(prefix).attention.output.dense")
        attentionNorm = try LayerNorm(tensors, prefix: "\(prefix).attention.output.LayerNorm", epsilon: epsilon)
        intermediate = try Linear(tensors, prefix: "\(prefix).intermediate.dense")
        output = try Linear(tensors, prefix: "\(prefix).output.dense")
        outputNorm = try LayerNorm(tensors, prefix: "\(prefix).output.LayerNorm", epsilon: epsilon)
        self.heads = heads
    }

    func callAsFunction(_ x: [Float], rows: Int) -> [Float] {
        var attention = attentionOutput(selfAttention(x, rows: rows), rows: rows)
        add(x, into: &attention)
        attentionNorm.apply(&attention, rows: rows)

        var expanded = intermediate(attention, rows: rows)
        gelu(&expanded)
        var result = output(expanded, rows: rows)
        add(attention, into: &result)
        outputNorm.apply(&result, rows: rows)
        return result
    }

    /// Attention multi-têtes sur une seule séquence (pas de remplissage, donc pas de masque).
    private func selfAttention(_ x: [Float], rows: Int) -> [Float] {
        let width = query.outputs
        let headSize = width / heads
        let scale = 1 / Float(headSize).squareRoot()
        let q = query(x, rows: rows)
        let k = key(x, rows: rows)
        let v = value(x, rows: rows)

        var context = [Float](repeating: 0, count: rows * width)
        var headQuery = [Float](repeating: 0, count: rows * headSize)
        var headKeyTransposed = [Float](repeating: 0, count: headSize * rows)
        var headValue = [Float](repeating: 0, count: rows * headSize)
        var weights = [Float](repeating: 0, count: rows * rows)
        var headContext = [Float](repeating: 0, count: rows * headSize)

        for head in 0..<heads {
            for row in 0..<rows {
                for column in 0..<headSize {
                    let source = row * width + head * headSize + column
                    headQuery[row * headSize + column] = q[source] * scale
                    headKeyTransposed[column * rows + row] = k[source]
                    headValue[row * headSize + column] = v[source]
                }
            }
            vDSP_mmul(headQuery, 1, headKeyTransposed, 1, &weights, 1, vDSP_Length(rows), vDSP_Length(rows), vDSP_Length(headSize))
            softmaxRows(&weights, rows: rows, columns: rows)
            vDSP_mmul(weights, 1, headValue, 1, &headContext, 1, vDSP_Length(rows), vDSP_Length(headSize), vDSP_Length(rows))
            for row in 0..<rows {
                for column in 0..<headSize {
                    context[row * width + head * headSize + column] = headContext[row * headSize + column]
                }
            }
        }
        return context
    }
}

private func add(_ values: [Float], into target: inout [Float]) {
    target.withUnsafeMutableBufferPointer { buffer in
        vDSP_vadd(buffer.baseAddress!, 1, values, 1, buffer.baseAddress!, 1, vDSP_Length(values.count))
    }
}

private func softmaxRows(_ matrix: inout [Float], rows: Int, columns: Int) {
    matrix.withUnsafeMutableBufferPointer { buffer in
        var count = Int32(columns)
        for row in 0..<rows {
            let line = buffer.baseAddress! + row * columns
            var maximum: Float = 0
            vDSP_maxv(line, 1, &maximum, vDSP_Length(columns))
            var shift = -maximum
            vDSP_vsadd(line, 1, &shift, line, 1, vDSP_Length(columns))
            vvexpf(line, line, &count)
            var sum: Float = 0
            vDSP_sve(line, 1, &sum, vDSP_Length(columns))
            var inverse = 1 / sum
            vDSP_vsmul(line, 1, &inverse, line, 1, vDSP_Length(columns))
        }
    }
}

/// GELU exacte (avec la fonction d'erreur), comme dans BERT.
private func gelu(_ values: inout [Float]) {
    values.withUnsafeMutableBufferPointer { buffer in
        for index in buffer.indices {
            let x = buffer[index]
            buffer[index] = 0.5 * x * (1 + erff(x * 0.70710678))
        }
    }
}
