import Foundation

public enum SemanticSearchError: LocalizedError {
    case invalidModel(String)
    case download(String)

    public var errorDescription: String? {
        switch self {
        case .invalidModel(let detail): return localized("Modèle invalide : \(detail)")
        case .download(let detail): return localized("Téléchargement impossible : \(detail)")
        }
    }
}

/// Fichier de poids au format safetensors (Hugging Face), projeté en mémoire plutôt que chargé.
struct SafeTensors {
    struct Tensor {
        let dtype: String
        let shape: [Int]
        let offset: Int
        var count: Int { shape.reduce(1, *) }
    }

    private let data: Data
    private let tensors: [String: Tensor]

    init(url: URL) throws {
        data = try Data(contentsOf: url, options: .alwaysMapped)
        guard data.count > 8 else { throw SemanticSearchError.invalidModel(localized("fichier de poids tronqué")) }
        let headerLength = Int(UInt64(littleEndian: data.withUnsafeBytes { $0.loadUnaligned(as: UInt64.self) }))
        guard headerLength > 0, 8 + headerLength <= data.count,
              let header = try JSONSerialization.jsonObject(with: data.subdata(in: 8..<(8 + headerLength))) as? [String: Any]
        else { throw SemanticSearchError.invalidModel(localized("en-tête safetensors illisible")) }

        var tensors: [String: Tensor] = [:]
        for (name, value) in header {
            guard let info = value as? [String: Any],
                  let dtype = info["dtype"] as? String,
                  let shape = info["shape"] as? [Int],
                  let offsets = info["data_offsets"] as? [Int], offsets.count == 2,
                  8 + headerLength + offsets[1] <= data.count else { continue }
            tensors[name] = Tensor(dtype: dtype, shape: shape, offset: 8 + headerLength + offsets[0])
        }
        self.tensors = tensors
    }

    func tensor(_ name: String) throws -> Tensor {
        guard let tensor = tensors[name] else { throw SemanticSearchError.invalidModel(localized("tenseur absent : \(name)")) }
        return tensor
    }

    func contains(_ name: String) -> Bool {
        tensors[name] != nil
    }

    /// Taille d'un élément pour les types pris en charge (Float32, et demi-précision BF16 ou F16).
    static func byteWidth(_ dtype: String) -> Int? {
        switch dtype {
        case "F32": return 4
        case "BF16", "F16": return 2
        default: return nil
        }
    }

    /// Copie un tenseur en Float32.
    func floats(_ name: String) throws -> [Float] {
        let tensor = try tensor(name)
        guard Self.byteWidth(tensor.dtype) != nil else {
            throw SemanticSearchError.invalidModel(localized("type \(tensor.dtype) non pris en charge (\(name))"))
        }
        let count = tensor.count
        return data.withUnsafeBytes { raw in
            [Float](unsafeUninitializedCapacity: count) { buffer, initialized in
                Self.convert(raw, offset: tensor.offset, dtype: tensor.dtype, count: count, into: buffer.baseAddress!)
                initialized = count
            }
        }
    }

    /// Copie une ligne d'une matrice sans charger toute la matrice (la table des embeddings pèse des centaines de Mo).
    func copyRow(_ row: Int, of tensor: Tensor, into destination: UnsafeMutablePointer<Float>) {
        let width = tensor.shape.last ?? 0
        let elementSize = Self.byteWidth(tensor.dtype) ?? 4
        data.withUnsafeBytes { raw in
            Self.convert(raw, offset: tensor.offset + row * width * elementSize, dtype: tensor.dtype, count: width, into: destination)
        }
    }

    private static func convert(_ raw: UnsafeRawBufferPointer, offset: Int, dtype: String, count: Int,
                                into destination: UnsafeMutablePointer<Float>) {
        switch dtype {
        case "F32":
            _ = memcpy(destination, raw.baseAddress! + offset, count * MemoryLayout<Float>.size)
        case "BF16":
            for index in 0..<count {
                let bits = UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self))
                destination[index] = Float(bitPattern: UInt32(bits) << 16)
            }
        case "F16":
            for index in 0..<count {
                let bits = UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: offset + index * 2, as: UInt16.self))
                destination[index] = floatFromHalf(bits)
            }
        default:
            destination.initialize(repeating: 0, count: count)
        }
    }

    /// Conversion IEEE 754 demi-précision → simple précision.
    private static func floatFromHalf(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = UInt32(bits & 0x7C00) >> 10
        let mantissa = UInt32(bits & 0x03FF)
        switch exponent {
        case 0:
            // Zéro ou nombre sous-normal.
            let magnitude = Float(mantissa) * 5.960464477539063e-08
            return sign == 0 ? magnitude : -magnitude
        case 31:
            return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13))
        default:
            return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
        }
    }
}
