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

    @State private var linkRouter = LinkRouter()

    var body: some Scene {
        WindowGroup {
            WorldListView()
                .environment(linkRouter)
                // Mention links come back from the system as encounter:// URLs.
                .onOpenURL { linkRouter.open($0) }
                // Without this, each incoming URL would open a new window instead of using this one.
                .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
                // Notes written before their plain text was kept need it filled in so they can be searched.
                .task { Page.backfillSearchText(in: modelContainer.mainContext) }
                // Worlds from before there were root places get one, with their places and world map inside it.
                .task { World.ensureRootPlaces(in: modelContainer.mainContext) }
        }
        .modelContainer(modelContainer)
        .commands { AppCommands() }
    }
}
