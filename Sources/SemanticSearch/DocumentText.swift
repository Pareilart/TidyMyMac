import AppKit
import ImageIO
import PDFKit
import Vision

/// Extraction du début du texte d'un document, avec reconnaissance de texte (OCR) pour les scans et les images.
public enum DocumentText {
    static let plainExtensions: Set<String> = ["txt", "md", "markdown", "csv"]
    static let richExtensions: Set<String> = ["rtf", "doc", "docx", "odt"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "tif", "tiff"]
    public static let supportedExtensions = plainExtensions.union(richExtensions).union(imageExtensions).union(["pdf"])

    public static func extract(from url: URL, limit: Int = 3000, ocr: Bool = true) -> String {
        let ext = url.pathExtension.lowercased()
        var text = ""
        if ext == "pdf" {
            text = pdfText(url, limit: limit)
            // Un PDF sans texte est presque toujours un scan.
            if ocr, text.trimmingCharacters(in: .whitespacesAndNewlines).count < 40 {
                text = renderPDFPages(url, count: 2).map(recognizeText).joined(separator: "\n")
            }
        } else if plainExtensions.contains(ext) {
            if let handle = try? FileHandle(forReadingFrom: url) {
                text = String(decoding: (try? handle.read(upToCount: limit * 4)) ?? Data(), as: UTF8.self)
                try? handle.close()
            }
        } else if richExtensions.contains(ext) {
            text = (try? NSAttributedString(url: url, options: [:], documentAttributes: nil))?.string ?? ""
        } else if ocr, imageExtensions.contains(ext), let image = thumbnail(of: url) {
            text = recognizeText(in: image)
        }
        return String(text.prefix(limit))
    }

    private static func pdfText(_ url: URL, limit: Int) -> String {
        guard let document = PDFDocument(url: url) else { return "" }
        var text = ""
        for index in 0..<min(document.pageCount, 4) {
            text += (document.page(at: index)?.string ?? "") + "\n"
            if text.count >= limit { break }
        }
        return text
    }

    private static func thumbnail(of url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 2400,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    /// Rendu des premières pages d'un PDF en niveaux de gris (~144 dpi) pour l'OCR.
    private static func renderPDFPages(_ url: URL, count: Int) -> [CGImage] {
        guard let document = CGPDFDocument(url as CFURL), document.numberOfPages > 0 else { return [] }
        return (1...min(count, document.numberOfPages)).compactMap { number -> CGImage? in
            guard let page = document.page(at: number) else { return nil }
            let box = page.getBoxRect(.mediaBox)
            let scale: CGFloat = 2
            let width = Int(box.width * scale)
            let height = Int(box.height * scale)
            guard width > 0, height > 0, width * height < 40_000_000,
                  let context = CGContext(
                      data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue
                  ) else { return nil }
            context.setFillColor(gray: 1, alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: -box.minX, y: -box.minY)
            context.drawPDFPage(page)
            return context.makeImage()
        }
    }

    private static func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["fr-FR", "en-US"]
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }
}
