//
//  PageCanvasView.swift
//  Flouteur
//
//  Affiche la page courante et permet de sélectionner les zones à flouter
//  en traçant des rectangles à la souris.
//

import SwiftUI

struct PageCanvasView: View {
    @Bindable var store: DocumentStore

    // Glissement en cours, en coordonnées du conteneur.
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?

    var body: some View {
        GeometryReader { geo in
            let preview = store.previewImage()
            // Cadre occupé par l'image (lettre-boxée) dans le conteneur.
            let frame = preview.map { Self.fittedFrame(container: geo.size, imageSize: $0.size) }

            ZStack(alignment: .topLeading) {
                Color(NSColor.windowBackgroundColor)

                if let preview, let frame {
                    Image(nsImage: preview)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .shadow(radius: 2)

                    // Cadres légers des zones déjà définies sur cette page.
                    ForEach(store.masks[store.currentPage] ?? []) { mask in
                        let r = Self.denormalize(mask.rect, in: frame)
                        Rectangle()
                            .stroke(Color.accentColor.opacity(0.7), lineWidth: 1)
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .allowsHitTesting(false)
                    }

                    // Résultats de recherche sur cette page.
                    ForEach(store.matches(on: store.currentPage)) { match in
                        let r = Self.denormalize(match.rect, in: frame)
                        let isCurrent = store.currentMatch?.id == match.id
                        Rectangle()
                            .fill(Color.yellow.opacity(isCurrent ? 0.35 : 0.18))
                            .overlay(Rectangle().stroke(isCurrent ? Color.orange : Color.yellow, lineWidth: isCurrent ? 2 : 1))
                            .frame(width: r.width, height: r.height)
                            .position(x: r.midX, y: r.midY)
                            .allowsHitTesting(false)
                    }

                    // Sélection en cours.
                    if let live = liveRect {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.20))
                            .overlay(Rectangle().stroke(Color.accentColor, lineWidth: 1.5))
                            .frame(width: live.width, height: live.height)
                            .position(x: live.midX, y: live.midY)
                            .allowsHitTesting(false)
                    }
                } else {
                    EmptyStateView()
                        .frame(width: geo.size.width, height: geo.size.height)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(dragGesture(frame: frame))
        }
    }

    // MARK: - Geste de sélection

    private func dragGesture(frame: CGRect?) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .local)
            .onChanged { value in
                if dragStart == nil { dragStart = value.startLocation }
                dragCurrent = value.location
            }
            .onEnded { value in
                defer { dragStart = nil; dragCurrent = nil }
                guard let frame, let start = dragStart else { return }
                let rectInView = CGRect(start: start, end: value.location)
                let clamped = rectInView.intersection(frame)
                guard !clamped.isNull, clamped.width > 1, clamped.height > 1 else { return }
                store.addMask(Self.normalize(clamped, in: frame))
            }
    }

    /// Rectangle de la sélection en cours (coordonnées du conteneur).
    private var liveRect: CGRect? {
        guard let start = dragStart, let current = dragCurrent else { return nil }
        return CGRect(start: start, end: current)
    }

    // MARK: - Conversions de coordonnées

    /// Cadre de l'image ajustée (aspect fit) à l'intérieur du conteneur.
    static func fittedFrame(container: CGSize, imageSize: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              container.width > 0, container.height > 0 else {
            return CGRect(origin: .zero, size: container)
        }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: (container.width - width) / 2,
            y: (container.height - height) / 2,
            width: width,
            height: height
        )
    }

    /// Rectangle conteneur → coordonnées normalisées (0...1) relatives au cadre image.
    static func normalize(_ rect: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: (rect.minX - frame.minX) / frame.width,
            y: (rect.minY - frame.minY) / frame.height,
            width: rect.width / frame.width,
            height: rect.height / frame.height
        )
    }

    /// Coordonnées normalisées → rectangle conteneur.
    static func denormalize(_ normalized: CGRect, in frame: CGRect) -> CGRect {
        CGRect(
            x: frame.minX + normalized.minX * frame.width,
            y: frame.minY + normalized.minY * frame.height,
            width: normalized.width * frame.width,
            height: normalized.height * frame.height
        )
    }
}

// MARK: - Vue d'accueil (aucun document)

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Glissez un PDF ou une image ici")
                .font(.title3)
            Text("ou utilisez le bouton « Ouvrir »")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Aide CGRect

extension CGRect {
    /// Construit un rectangle à partir de deux points opposés.
    init(start: CGPoint, end: CGPoint) {
        self.init(
            x: min(start.x, end.x),
            y: min(start.y, end.y),
            width: abs(end.x - start.x),
            height: abs(end.y - start.y)
        )
    }
}
