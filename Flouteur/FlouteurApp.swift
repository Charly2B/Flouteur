//
//  FlouteurApp.swift
//  Flouteur
//
//  Point d'entrée de l'application : un flouteur de documents (PDF / images).
//

import SwiftUI

@main
struct FlouteurApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .commands {
            // Pas de commande « Nouveau document » : l'app ouvre des fichiers existants.
            CommandGroup(replacing: .newItem) {}
        }
    }
}
