# ARCHITECTURE.md — Flouteur

> Généré automatiquement. À mettre à jour après chaque modification architecturale importante.

---

## Vue d'ensemble

Flouteur est une application macOS SwiftUI qui permet de masquer (flouter) des zones d'un document. L'utilisateur ouvre un PDF multi-pages ou une image, trace un ou plusieurs rectangles à la souris sur les zones sensibles, ajuste l'intensité, puis exporte un document masqué dans le même format que la source.

**Principe :** sélection de rectangles → flou gaussien Core Image appliqué en direct dans l'aperçu → export aplati (le texte masqué n'est plus récupérable).

macOS 14+, SwiftUI + `@Observable`, aucune dépendance externe (PDFKit et Core Image natifs).

---

## Liste des fichiers et leur rôle

| Fichier | Type | Rôle |
|---|---|---|
| `FlouteurApp.swift` | `@main App` | Point d'entrée. `WindowGroup → ContentView`, retire la commande « Nouveau document ». |
| `ContentView.swift` | `View` | Vue principale : barre d'outils (ouvrir, navigation pages, curseur d'intensité, annuler/effacer, exporter), barre de recherche (PDF) et zone de prévisualisation. Gère `NSOpenPanel`/`NSSavePanel` et le glisser-déposer (`.fileURL`). |
| `PageCanvasView.swift` | `View` | Affiche l'aperçu flouté de la page, la surbrillance des résultats de recherche, et capte le `DragGesture` pour tracer les rectangles. Calcule le cadre « aspect-fit » et convertit vue ↔ coordonnées normalisées. Contient `EmptyStateView` et l'init `CGRect(start:end:)`. |
| `DocumentStore.swift` | `@Observable @MainActor` | État et logique. Ouvre PDF/image, rend les pages (cache d'aperçu), stocke les zones par page, recherche de texte (PDF), produit l'aperçu et gère l'export PDF/image. |
| `BlurEngine.swift` | `enum` (service pur) | Flou gaussien Core Image. `bake(cgImage:normalizedRects:intensity:)` et `sigma(for:intensity:)`. Indépendant de l'UI. |
| `Models.swift` | Modèles | `MaskRect { id, rect }` (rectangle normalisé 0...1), `SearchMatch { id, page, rect }` (résultat de recherche) et `DocumentKind { pdf, image }`. |

---

## Flux de données

```
Utilisateur ouvre/dépose un fichier
        │
        ▼
ContentView → DocumentStore.open(url:)
   ├── PDF   → PDFDocument, pageCount
   └── image → CGImage pleine résolution
        │
        ▼
PageCanvasView affiche DocumentStore.previewImage()
   ├── previewBase(page) → rendu page (PDFKit) ou downscale image, ≤ 1600 px, mis en cache
   └── BlurEngine.bake(base, masks[page], intensity) → aperçu flouté en direct
        │
        ▼
DragGesture → rectangle (coordonnées vue)
   ├── clamp au cadre image + normalisation 0...1
   └── DocumentStore.addMask(rect) → masks[currentPage] += MaskRect
        │
        ▼
Export (⌘S) → DocumentStore.export(to:)
   ├── PDF   : pour chaque page, rendu ~200 DPI → BlurEngine.bake → CGContext PDF (page aplatie)
   └── image : BlurEngine.bake pleine résolution → NSBitmapImageRep (même format)
```

---

## Décisions techniques importantes

**1. Zones en coordonnées normalisées**
`MaskRect.rect` est exprimé en fraction (0...1) de la page, origine haut-gauche. Indépendant de la résolution → le même rectangle vaut pour l'aperçu (basse résolution) et l'export (haute résolution).

**2. Flou Core Image avec inversion d'axe Y**
Core Image utilise une origine en bas à gauche. `BlurEngine.bake` convertit chaque rectangle normalisé (haut-gauche) en rectangle Core Image (bas-gauche) via `y = (1 - maxY) * hauteur`. L'image entière est floutée une seule fois (`clampedToExtent` pour éviter les bords transparents), puis chaque zone est composée par-dessus l'image nette.

**3. Sigma proportionnel à la taille**
`sigma = max(4, intensity * min(largeur, hauteur) * 0.03)`. Comme il dépend de la dimension de l'image, le flou paraît identique entre l'aperçu et l'export haute définition.

**4. Export aplati = masquage sûr**
À l'export PDF, chaque page est rendue en bitmap (~200 DPI), floutée, puis redessinée dans un `CGContext` PDF. Le résultat ne contient plus de texte sélectionnable : les zones masquées sont définitivement illisibles. Choix volontaire (sécurité) plutôt qu'une surcouche de flou laissant le texte récupérable.

**5. Cache d'aperçu**
`previewBaseCache: [Int: CGImage]` conserve le rendu de base (non flouté) de chaque page à ≤ 1600 px. Seul le flou est recalculé quand les zones ou l'intensité changent → aperçu fluide.

**6. `@Observable @MainActor`**
`DocumentStore` est isolé sur le MainActor (rendu graphique + UI). Conforme aux projets récents de l'écosystème (`@Observable` plutôt que `ObservableObject`).

**7. Pas d'App Sandbox**
Accès fichiers complet via `NSOpenPanel`/`NSSavePanel`, y compris volumes externes (`/Volumes/...`). Outil personnel, pas de distribution App Store.

**8. Recherche de texte (PDF)**
`runSearch` utilise `PDFDocument.findString(_:withOptions: .caseInsensitive)`. Chaque `PDFSelection.bounds(for:)` (points, origine bas-gauche) est converti dans le repère normalisé haut-gauche, comme les zones, puis trié par page et position. La navigation (`nextMatch`/`previousMatch`) saute à la page du résultat et le met en surbrillance ; « Flouter les résultats » (`blurAllMatches`) transforme chaque occurrence en `MaskRect`. Pas d'OCR : les images n'ont pas de couche texte, la recherche est donc réservée aux PDF.

---

## Logique métier clé

**Rendu d'une page PDF** (`DocumentStore.renderPDFPage`)
Crée un `CGContext` bitmap, fond blanc, applique l'échelle et la translation du `mediaBox`, puis `page.draw(with: .mediaBox)`. L'image résultante est à l'endroit (origine haut-gauche à l'affichage).

**Sélection des zones** (`PageCanvasView`)
`fittedFrame` calcule le cadre occupé par l'image (aspect-fit, lettre-boxée) dans le conteneur. `normalize`/`denormalize` convertissent entre coordonnées du conteneur et fractions du cadre image. Une sélection < 0,5 % est ignorée (clic accidentel).

**Aperçu en direct** (`DocumentStore.previewImage`)
Rend (ou relit depuis le cache) la page de base, applique `BlurEngine.bake` avec les zones de la page courante et l'intensité, renvoie une `NSImage`.

**Export image** (`DocumentStore.exportImage`)
Floute l'image pleine résolution puis sérialise via `NSBitmapImageRep` selon l'extension cible (`png`, `jpg/jpeg`, `tiff`, `bmp`, `gif`). JPEG à 0,9 de qualité.

**Nom d'export suggéré**
`<nom source>_floute.<extension source>` (ex. `releve_floute.pdf`).
