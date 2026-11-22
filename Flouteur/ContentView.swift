//
//  ContentView.swift
//  Flouteur
//
//  Vue principale : barre d'outils + zone de prévisualisation / sélection.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var store = DocumentStore()
    @State private var errorMessage: String?

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            toolbar
            if store.searchSupported {
                Divider()
                searchBar
            }
            Divider()
            PageCanvasView(store: store)
                .onDrop(of: [.fileURL], isTargeted: nil) { providers in
                    handleDrop(providers)
                }
        }
        .frame(minWidth: 760, minHeight: 620)
        .alert(
            "Erreur",
            isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Barre d'outils

    private var toolbar: some View {
        @Bindable var store = store

        return HStack(spacing: 12) {
            Button { openDocument() } label: {
                Label("Ouvrir", systemImage: "folder")
            }

            if store.hasDocument {
                Divider().frame(height: 20)

                // Navigation entre pages (PDF multi-pages).
                if store.pageCount > 1 {
                    Button { store.goToPage(store.currentPage - 1) } label: {
                        Image(systemName: "chevron.left")
                    }
                    .disabled(store.currentPage <= 0)

                    Text("Page \(store.currentPage + 1) / \(store.pageCount)")
                        .monospacedDigit()
                        .frame(minWidth: 80)

                    Button { store.goToPage(store.currentPage + 1) } label: {
                        Image(systemName: "chevron.right")
                    }
                    .disabled(store.currentPage >= store.pageCount - 1)

                    Divider().frame(height: 20)
                }

                // Intensité du flou.
                HStack(spacing: 6) {
                    Image(systemName: "drop.fill").foregroundStyle(.secondary)
                    Slider(value: $store.intensity, in: 0.1...1.0)
                        .frame(width: 120)
                }

                Divider().frame(height: 20)

                Button { store.undoLast() } label: {
                    Label("Annuler", systemImage: "arrow.uturn.backward")
                }
                .disabled(store.currentPageMaskCount == 0)

                Button { store.clearCurrentPage() } label: {
                    Label("Effacer la page", systemImage: "xmark.circle")
                }
                .disabled(store.currentPageMaskCount == 0)

                Spacer()

                Text("\(store.totalMaskCount) zone(s)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()

                Button { exportDocument() } label: {
                    Label("Exporter", systemImage: "square.and.arrow.down")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(store.totalMaskCount == 0)
                .buttonStyle(.borderedProminent)
            } else {
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Barre de recherche

    private var searchBar: some View {
        @Bindable var store = store

        return HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher du texte…", text: $store.searchQuery)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .onSubmit { store.runSearch() }
                .onChange(of: store.searchQuery) { store.handleQueryChange() }

            Button("Rechercher") { store.runSearch() }
                .disabled(store.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty)

            if store.hasSearchResults {
                Button { store.previousMatch() } label: { Image(systemName: "chevron.up") }
                    .help("Résultat précédent")
                Button { store.nextMatch() } label: { Image(systemName: "chevron.down") }
                    .help("Résultat suivant")
                Text(store.matchPositionText)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)

                Divider().frame(height: 18)

                Button { store.blurAllMatches() } label: {
                    Label("Flouter les résultats", systemImage: "drop.fill")
                }
                .buttonStyle(.borderedProminent)
            } else if store.showsNoResults {
                Text("Aucun résultat").foregroundStyle(.secondary)
            }

            Spacer()

            if !store.searchQuery.isEmpty {
                Button { store.clearSearch() } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Effacer la recherche")
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Ouverture / export

    private func openDocument() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = DocumentStore.acceptedTypes
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.message = "Choisissez un PDF ou une image à flouter"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !store.open(url: url) {
            errorMessage = "Impossible d'ouvrir ce fichier."
        }
    }

    private func exportDocument() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = store.suggestedExportName
        if let type = UTType(filenameExtension: store.suggestedExportExtension) {
            panel.allowedContentTypes = [type]
        }
        panel.message = "Enregistrer le document masqué"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !store.export(to: url) {
            errorMessage = "Échec de l'export du document."
        }
    }

    // MARK: - Glisser-déposer

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            var resolved: URL?
            if let data = item as? Data {
                resolved = URL(dataRepresentation: data, relativeTo: nil)
            } else if let url = item as? URL {
                resolved = url
            }
            guard let url = resolved else { return }

            Task { @MainActor in
                if !store.open(url: url) {
                    errorMessage = "Format de fichier non supporté."
                }
            }
        }
        return true
    }
}
