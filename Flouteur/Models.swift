//
//  Models.swift
//  Flouteur
//
//  Modèles de données de l'application.
//

import Foundation

/// Une zone à flouter, exprimée en coordonnées normalisées (0...1)
/// dans l'espace de l'image affichée (origine en haut à gauche).
/// Le format normalisé rend la zone indépendante de la résolution
/// (le même rectangle vaut pour l'aperçu et pour l'export haute définition).
struct MaskRect: Identifiable, Equatable {
    let id = UUID()
    var rect: CGRect
}

/// Un résultat de recherche de texte : la page concernée et la zone
/// (normalisée, origine haut-gauche) du texte trouvé.
struct SearchMatch: Identifiable, Equatable {
    let id = UUID()
    var page: Int
    var rect: CGRect
}

/// Nature du document chargé.
enum DocumentKind: Equatable {
    case pdf
    case image
}
