//
//  encounterApp.swift
//  encounter
//
//  Created by Joe Clarke on 30/10/2026.
//

import SwiftUI
import SwiftData

@main
struct encounterApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try AppSchema.makeContainer()
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            WorldListView()
        }
        .modelContainer(modelContainer)
    }
}
