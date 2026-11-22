//
//  BlurEngine.swift
//  Flouteur
//
//  Moteur de flou gaussien basé sur Core Image.
//  Indépendant de l'UI : prend une image et des zones, renvoie une image floutée.
//

import CoreImage
import CoreGraphics

enum BlurEngine {

    /// Contexte Core Image réutilisé (sa création est coûteuse).
    private static let context = CIContext(options: [.useSoftwareRenderer: false])

    /// Calcule un sigma de flou proportionnel à la taille de l'image.
    /// Ainsi le rendu est visuellement identique entre l'aperçu (basse résolution)
    /// et l'export (haute résolution).
    /// - Parameter intensity: intensité choisie par l'utilisateur (0...1).
    static func sigma(for cgImage: CGImage, intensity: Double) -> Double {
        let minDimension = Double(min(cgImage.width, cgImage.height))
        return max(4.0, intensity * minDimension * 0.03)
    }

    /// Applique le flou aux zones données et renvoie une nouvelle image.
    /// - Parameters:
    ///   - cgImage: image source.
    ///   - normalizedRects: zones à flouter en coordonnées normalisées (origine haut-gauche).
    ///   - intensity: intensité du flou (0...1).
    /// - Returns: l'image floutée, ou l'image d'origine si aucune zone.
    static func bake(cgImage: CGImage, normalizedRects: [CGRect], intensity: Double) -> CGImage? {
        guard !normalizedRects.isEmpty else { return cgImage }

        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)
        let base = CIImage(cgImage: cgImage)

        // Flou de l'image entière : on étend les bords (clamp) pour éviter
        // un liseré transparent, puis on recadre sur l'étendue d'origine.
        let blurredFull = base
            .clampedToExtent()
            .applyingGaussianBlur(sigma: sigma(for: cgImage, intensity: intensity))
            .cropped(to: base.extent)

        // On compose chaque zone floutée par-dessus l'image nette.
        var result = base
        for normalized in normalizedRects {
            // Core Image a son origine en bas à gauche : on inverse l'axe Y.
            let ciRect = CGRect(
                x: normalized.minX * width,
                y: (1.0 - normalized.maxY) * height,
                width: normalized.width * width,
                height: normalized.height * height
            )
            let patch = blurredFull.cropped(to: ciRect)
            result = patch.composited(over: result)
        }

        return context.createCGImage(result, from: base.extent)
    }
}
