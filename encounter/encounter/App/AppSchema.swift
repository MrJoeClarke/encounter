//
//  AppSchema.swift
//  encounter
//

import Foundation
import SwiftData
import Security

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

    /// The CloudKit container the worlds sync through.
    static let cloudKitContainerID = "iCloud.com.infography.encounter"
    /// The setting that turns iCloud sync on or off. It is read when the app opens, so a change takes effect the next time.
    static let syncDefaultsKey = "iCloudSyncEnabled"

    /// Whether the user wants their worlds synced through iCloud. On unless they turned it off.
    static var syncIsEnabled: Bool {
        UserDefaults.standard.object(forKey: syncDefaultsKey) as? Bool ?? true
    }

    /// Whether this build of the app is signed with the CloudKit container. Opening the store with CloudKit when it isn't stops the app
    /// with an exception that can't be caught, so sync is only tried when it is. Only the Mac can look; elsewhere a signed build is trusted.
    static var appHasICloudContainer: Bool {
        #if os(macOS)
        guard let task = SecTaskCreateFromSelf(nil),
              let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-container-identifiers" as CFString, nil) as? [String]
        else { return false }
        return value.contains(cloudKitContainerID)
        #else
        return true
        #endif
    }

    /// The container for the models. Only a store on disk syncs, and only when asked: previews and tests keep to themselves.
    static func makeContainer(inMemory: Bool = false, syncsWithICloud: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        let database: ModelConfiguration.CloudKitDatabase = syncsWithICloud && !inMemory && appHasICloudContainer ? .private(cloudKitContainerID) : .none
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: database)
        return try ModelContainer(for: schema, configurations: [configuration])
    }
}
