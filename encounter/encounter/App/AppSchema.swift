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

    /// Whether the unit tests are running the app as their host, which must not touch a real iCloud container.
    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// How the store was opened, so the About screen can say whether the app is syncing and, if not, why.
    static private(set) var startup: SyncStartup = .switchedOff

    /// The container for the models. Only a store on disk syncs, and only when asked: previews and tests keep to themselves.
    static func makeContainer(inMemory: Bool = false, syncsWithICloud: Bool = false) throws -> ModelContainer {
        let schema = Schema(models)
        var database: ModelConfiguration.CloudKitDatabase = .none
        if syncsWithICloud && !inMemory {
            if !appHasICloudContainer {
                startup = .unavailable("This build of the app isn’t signed with the iCloud container.")
            } else if isRunningUnitTests {
                startup = .switchedOff
            } else {
                database = .private(cloudKitContainerID)
                startup = .syncing
            }
        } else if !inMemory {
            startup = .switchedOff
        }
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: database)
        do {
            return try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            guard case .syncing = startup else { throw error }
            // The store won't load with sync, so the device's own copy is opened and the reason kept to show.
            startup = .unavailable("iCloud sync couldn’t start: \(error.localizedDescription)")
            let local = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: [local])
        }
    }
}
