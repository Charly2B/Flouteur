//
//  DocumentStore.swift
//  Flouteur
//
//  État de l'application et logique de rendu / export.
//  Gère indifféremment un PDF (multi-pages) ou une image.
//

import SwiftUI
import PDFKit
import UniformTypeIdentifiers

@MainActor
@Observable
final class DocumentStore {

    // MARK: - État exposé à l'UI

    /// Nature du document courant (nil si rien n'est chargé).
    private(set) var kind: DocumentKind?
    /// URL du fichier source (sert à proposer un nom d'export).
    private(set) var sourceURL: URL?
    /// Nombre de pages (1 pour une image).
    private(set) var pageCount: Int = 0
    /// Page actuellement affichée (0...pageCount-1).
    var currentPage: Int = 0
    /// Zones à flouter, par page : [indexPage: zones].
    var masks: [Int: [MaskRect]] = [:]
    /// Intensité du flou (0...1).
    var intensity: Double = 0.55

    /// Texte recherché.
    var searchQuery: String = ""
    /// Résultats de la recherche (toutes pages), triés.
    private(set) var searchMatches: [SearchMatch] = []
    /// Index du résultat courant (navigation).
    private(set) var currentMatchIndex: Int?
    /// Dernière requête réellement lancée (pour l'affichage « aucun résultat »).
    private(set) var lastSearchedQuery: String?

    // MARK: - Sources internes

    private var pdf: PDFDocument?
    /// Image source en pleine résolution (cas image).
    private var imageFull: CGImage?
    /// Cache des pages de base rendues pour l'aperçu : [indexPage: image].
    private var previewBaseCache: [Int: CGImage] = [:]

    /// Dimension maximale (en pixels) du rendu d'aperçu.
    private let previewMaxDimension: CGFloat = 1600

    // MARK: - Types acceptés

    /// Types acceptés à l'ouverture (PDF + formats image courants).
    static let acceptedTypes: [UTType] = [.pdf, .png, .jpeg, .tiff, .heic, .bmp, .gif]

    var hasDocument: Bool { kind != nil }
    var currentPageMaskCount: Int { masks[currentPage]?.count ?? 0 }
    var totalMaskCount: Int { masks.values.reduce(0) { $0 + $1.count } }

    // MARK: - Ouverture

    /// Charge un fichier (PDF ou image). Renvoie false si le format n'est pas géré.
    @discardableResult
    func open(url: URL) -> Bool {
        reset()
        let ext = url.pathExtension.lowercased()

        if ext == "pdf" {
            guard let document = PDFDocument(url: url), document.pageCount > 0 else { return false }
            pdf = document
            kind = .pdf
            pageCount = document.pageCount
            sourceURL = url
            currentPage = 0
            return true
        } else {
            guard let nsImage = NSImage(contentsOf: url),
                  let cgImage = nsImage.cgImageForBlur() else { return false }
            imageFull = cgImage
            kind = .image
            pageCount = 1
            sourceURL = url
            currentPage = 0
            return true
        }
    }

    private func reset() {
        pdf = nil
        imageFull = nil
        kind = nil
        sourceURL = nil
        pageCount = 0
        currentPage = 0
        masks = [:]
        previewBaseCache = [:]
        searchQuery = ""
        searchMatches = []
        currentMatchIndex = nil
        lastSearchedQuery = nil
    }

    // MARK: - Navigation

    func goToPage(_ index: Int) {
        guard pageCount > 0 else { return }
        currentPage = min(max(index, 0), pageCount - 1)
    }

    // MARK: - Édition des zones

    func addMask(_ rect: CGRect) {
        // On ignore les sélections minuscules (clics accidentels).
        guard rect.width > 0.005, rect.height > 0.005 else { return }
        masks[currentPage, default: []].append(MaskRect(rect: rect))
    }

    func undoLast() {
        guard var list = masks[currentPage], !list.isEmpty else { return }
        list.removeLast()
        masks[currentPage] = list
    }

    func clearCurrentPage() {
        masks[currentPage] = []
    }

    func clearAll() {
        masks = [:]
    }

    // MARK: - Recherche de texte (PDF)

    /// Indique si la recherche est disponible (PDF avec couche texte).
    var searchSupported: Bool { kind == .pdf }
    var hasSearchResults: Bool { !searchMatches.isEmpty }

    /// Résultats présents sur une page donnée.
    func matches(on page: Int) -> [SearchMatch] {
        searchMatches.filter { $0.page == page }
    }

    /// Résultat actuellement sélectionné.
    var currentMatch: SearchMatch? {
        guard let index = currentMatchIndex, searchMatches.indices.contains(index) else { return nil }
        return searchMatches[index]
    }

    /// Vrai si une recherche a été lancée et n'a rien renvoyé.
    var showsNoResults: Bool {
        guard let last = lastSearchedQuery else { return false }
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return !query.isEmpty && query == last && searchMatches.isEmpty
    }

    /// Position lisible du résultat courant, ex. « 3 / 17 ».
    var matchPositionText: String {
        guard let index = currentMatchIndex else { return "\(searchMatches.count)" }
        return "\(index + 1) / \(searchMatches.count)"
    }

    /// Lance la recherche de texte dans le PDF (insensible à la casse).
    func runSearch() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        searchMatches = []
        currentMatchIndex = nil
        lastSearchedQuery = query.isEmpty ? nil : query
        guard let pdf, kind == .pdf, !query.isEmpty else { return }

        var results: [SearchMatch] = []
        for selection in pdf.findString(query, withOptions: [.caseInsensitive]) {
            for page in selection.pages {
                let pageIndex = pdf.index(for: page)
                let mediaBox = page.bounds(for: .mediaBox)
                // Bornes du texte (points, origine bas-gauche), légèrement élargies.
                let raw = selection.bounds(for: page).insetBy(dx: -2, dy: -2)
                guard raw.width > 0, raw.height > 0, mediaBox.width > 0, mediaBox.height > 0 else { continue }
                // Conversion vers le repère normalisé haut-gauche utilisé par les zones.
                let normalized = CGRect(
                    x: (raw.minX - mediaBox.minX) / mediaBox.width,
                    y: (mediaBox.maxY - raw.maxY) / mediaBox.height,
                    width: raw.width / mediaBox.width,
                    height: raw.height / mediaBox.height
                )
                results.append(SearchMatch(page: pageIndex, rect: normalized))
            }
        }
        results.sort { ($0.page, $0.rect.minY) < ($1.page, $1.rect.minY) }
        searchMatches = results
        if !results.isEmpty { goToMatch(0) }
    }

    /// Réinitialise les résultats si la requête a changé depuis la dernière recherche.
    func handleQueryChange() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if query != lastSearchedQuery {
            searchMatches = []
            currentMatchIndex = nil
        }
    }

    func goToMatch(_ index: Int) {
        guard searchMatches.indices.contains(index) else { return }
        currentMatchIndex = index
        currentPage = searchMatches[index].page
    }

    func nextMatch() {
        guard !searchMatches.isEmpty else { return }
        goToMatch(((currentMatchIndex ?? -1) + 1) % searchMatches.count)
    }

    func previousMatch() {
        guard !searchMatches.isEmpty else { return }
        let count = searchMatches.count
        goToMatch(((currentMatchIndex ?? 0) - 1 + count) % count)
    }

    /// Floute toutes les occurrences trouvées, puis efface la surbrillance.
    func blurAllMatches() {
        for match in searchMatches {
            masks[match.page, default: []].append(MaskRect(rect: match.rect))
        }
        searchMatches = []
        currentMatchIndex = nil
        lastSearchedQuery = nil
    }

    func clearSearch() {
        searchQuery = ""
        searchMatches = []
        currentMatchIndex = nil
        lastSearchedQuery = nil
    }

    // MARK: - Aperçu

    /// Image de base (non floutée) de la page, en résolution d'aperçu (avec cache).
    private func previewBase(for page: Int) -> CGImage? {
        if let cached = previewBaseCache[page] { return cached }

        let rendered: CGImage?
        switch kind {
        case .pdf:
            guard let pdfPage = pdf?.page(at: page) else { return nil }
            let size = pdfPage.bounds(for: .mediaBox).size
            let scale = previewMaxDimension / max(size.width, size.height, 1)
            rendered = Self.renderPDFPage(pdfPage, scale: max(scale, 0.1))
        case .image:
            rendered = imageFull.map { Self.downscale($0, maxDimension: previewMaxDimension) }
        case .none:
            rendered = nil
        }

        if let rendered { previewBaseCache[page] = rendered }
        return rendered
    }

    /// Aperçu flouté de la page courante (ce que l'UI affiche).
    func previewImage() -> NSImage? {
        guard let base = previewBase(for: currentPage) else { return nil }
        let rects = (masks[currentPage] ?? []).map { $0.rect }
        guard let baked = BlurEngine.bake(cgImage: base, normalizedRects: rects, intensity: intensity) else {
            return NSImage(cgImage: base, size: NSSize(width: base.width, height: base.height))
        }
        return NSImage(cgImage: baked, size: NSSize(width: baked.width, height: baked.height))
    }

    // MARK: - Export

    /// Extension suggérée pour l'export (identique à la source).
    var suggestedExportExtension: String {
        guard let ext = sourceURL?.pathExtension, !ext.isEmpty else {
            return kind == .pdf ? "pdf" : "png"
        }
        return ext.lowercased()
    }

    /// Nom de fichier suggéré : <base>_floute.<ext>
    var suggestedExportName: String {
        let base = sourceURL?.deletingPathExtension().lastPathComponent ?? "document"
        return "\(base)_floute.\(suggestedExportExtension)"
    }

    /// Exporte le document masqué. Renvoie true en cas de succès.
    @discardableResult
    func export(to url: URL) -> Bool {
        switch kind {
        case .pdf:   return exportPDF(to: url)
        case .image: return exportImage(to: url)
        case .none:  return false
        }
    }

    /// Export PDF : chaque page est rendue à ~200 DPI, floutée, puis ré-encapsulée.
    /// Le résultat est aplati en image → le texte masqué n'est plus récupérable.
    private func exportPDF(to url: URL) -> Bool {
        guard let pdf else { return false }
        let exportScale: CGFloat = 200.0 / 72.0  // ~200 DPI

        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return false }
        var defaultBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(consumer: consumer, mediaBox: &defaultBox, nil) else { return false }

        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index) else { continue }
            let pointSize = page.bounds(for: .mediaBox).size
            guard let base = Self.renderPDFPage(page, scale: exportScale) else { continue }

            let rects = (masks[index] ?? []).map { $0.rect }
            let baked = BlurEngine.bake(cgImage: base, normalizedRects: rects, intensity: intensity) ?? base

            let box = CGRect(origin: .zero, size: pointSize)
            let pageInfo: [String: Any] = [kCGPDFContextMediaBox as String: NSValue(rect: box)]
            context.beginPDFPage(pageInfo as CFDictionary)
            context.draw(baked, in: box)
            context.endPDFPage()
        }

        context.closePDF()
        return data.write(to: url, atomically: true)
    }

    /// Export image : on floute l'image pleine résolution et on réenregistre
    /// dans le même format que la source.
    private func exportImage(to url: URL) -> Bool {
        guard let base = imageFull else { return false }
        let rects = (masks[0] ?? []).map { $0.rect }
        let baked = BlurEngine.bake(cgImage: base, normalizedRects: rects, intensity: intensity) ?? base

        let representation = NSBitmapImageRep(cgImage: baked)
        let fileType: NSBitmapImageRep.FileType
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg": fileType = .jpeg
        case "tiff", "tif": fileType = .tiff
        case "bmp":         fileType = .bmp
        case "gif":         fileType = .gif
        default:            fileType = .png
        }
        let properties: [NSBitmapImageRep.PropertyKey: Any] =
            fileType == .jpeg ? [.compressionFactor: 0.9] : [:]
        guard let data = representation.representation(using: fileType, properties: properties) else { return false }
        return (try? data.write(to: url)) != nil
    }

    // MARK: - Rendu bas niveau

    /// Rend une page PDF en bitmap (origine haut-gauche), sur fond blanc.
    static func renderPDFPage(_ page: PDFPage, scale: CGFloat) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { return nil }

        context.setFillColor(NSColor.white.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    /// Réduit une image à une dimension maximale (pour accélérer l'aperçu).
    static func downscale(_ image: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let longestSide = max(width, height)
        guard longestSide > maxDimension else { return image }

        let scale = maxDimension / longestSide
        let newWidth = Int((width * scale).rounded())
        let newHeight = Int((height * scale).rounded())
        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return image }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? image
    }
}

// MARK: - Aide NSImage

private extension NSImage {
    /// Renvoie un CGImage exploitable par Core Image.
    func cgImageForBlur() -> CGImage? {
        var rect = CGRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}
