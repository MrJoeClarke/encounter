//
//  AppSchema.swift
//  encounter
//

import SwiftData

/// The SwiftData schema and container factory.
///
/// Every model here must stay CloudKit-compatible so sync can be enabled later without migration:
/// no unique attributes, every property defaulted or optional, optional relationships with inverses.
enum AppSchema {
    static let models: [any PersistentModel.Type] = [
        World.self,
        CalendarDefinition.self,
        Campaign.self,
        Page.self,
        PageImage.self,
        PageLink.self,
        WorldMap.self,
    ]

    static func makeContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
