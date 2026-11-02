//
//  SystemIdentityTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// A world names its system by a key, which can be one read from a file, or one this app doesn't have at all.
@MainActor
struct SystemIdentityTests {
    private static func json(key: String, version: Int) -> String {
        """
        {"formatVersion": 1, "version": \(version), "id": "\(key)", "name": "Made Up \(key)",
         "modules": ["sheet"],
         "attributes": [{"key": "\(key).grit", "label": "Grit", "type": "number", "appliesTo": ["character"]}]}
        """
    }

    private func register(_ key: String, version: Int = 1) throws -> DataRuleSystem {
        let system = try #require(DataRuleSystem(data: Data(Self.json(key: key, version: version).utf8)))
        #expect(SystemRegistry.shared.register(system))
        return system
    }

    private func makeContext() throws -> ModelContext { ModelContext(try AppSchema.makeContainer(inMemory: true)) }

    @Test func aWorldCanUseASystemFromAFile() throws {
        _ = try register("made.one")
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)
        world.choose(systemKey: "made.one")

        #expect(world.systemRaw == "made.one" && world.rules == [.sheet] && world.systemTitle == "Made Up made.one")
        #expect(world.systemStatus == .current)
        let keys = RuleSystems.definitions(for: .character, systemKey: world.systemRaw).map(\.key)
        #expect(keys.contains("made.one.grit") && !RuleSystems.definitions(for: .item, systemKey: world.systemRaw).map(\.key).contains("made.one.grit"))
        #expect(RuleSystems.choices.map(\.key).starts(with: ["none", "dnd5e"]) && RuleSystems.choices.contains { $0.key == "made.one" })
        // The app's own systems are unchanged.
        let dnd = World(name: "D")
        dnd.choose(systemKey: "dnd5e")
        #expect(dnd.system == .dnd5e && dnd.rules == DnD5eSystem().modules && dnd.systemStatus == .current)
    }

    @Test func aSystemCantTakeTheKeyOfOneTheAppNames() throws {
        let system = try #require(DataRuleSystem(data: Data(Self.json(key: "dnd5e", version: 1).utf8)))
        #expect(!SystemRegistry.shared.register(system))
        #expect(RuleSystems.system(forKey: "dnd5e").modules == DnD5eSystem().modules)
        // A registry of its own holds only what is added to it.
        let registry = SystemRegistry(loadsBundle: false)
        #expect(registry.all.isEmpty && registry.system(forKey: "made.one") == nil)
    }

    @Test func aSystemTheAppDoesNotHaveIsKeptAndShowsOnlyCoreAttributes() throws {
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)
        world.systemRaw = "somebody.elses"
        world.systemVersion = 4
        let page = world.addPage(kind: .character, in: context)
        page.setAttributeNumber("somebody.elses.grit", 3)

        #expect(world.systemStatus == .unknown && world.rules.isEmpty && world.systemTitle == "somebody.elses")
        #expect(RuleSystems.definitions(for: .character, systemKey: world.systemRaw).map(\.key) == CoreAttributes.definitions(for: .character).map(\.key))
        #expect(world.visibleKinds == PageKind.allCases.filter { !$0.isConditional })
        // Nothing is lost.
        #expect(world.systemRaw == "somebody.elses" && page.attributeNumber("somebody.elses.grit") == 3)
    }

    @Test func aWorldSaysWhenItsSystemHasMovedOn() throws {
        _ = try register("made.two", version: 3)
        #expect(RuleSystems.status(key: "made.two", recordedVersion: 3) == .current)
        #expect(RuleSystems.status(key: "made.two", recordedVersion: nil) == .current)
        #expect(RuleSystems.status(key: "made.two", recordedVersion: 0) == .current)
        #expect(RuleSystems.status(key: "made.two", recordedVersion: 2) == .updated(from: 2, to: 3))
        #expect(RuleSystems.status(key: "made.two", recordedVersion: 5) == .newerThanApp(world: 5, app: 3))
        #expect(RuleSystems.status(key: "nobody", recordedVersion: 1) == .unknown)
        #expect(SystemDefinition.decode(from: Data(#"{"formatVersion":1,"id":"x","name":"X"}"#.utf8))?.version == 1)
    }

    @Test func theSystemAndItsVersionSurviveExportAndImport() async throws {
        _ = try register("made.three", version: 2)
        let source = try makeContext()
        let world = World(name: "W")
        source.insert(world)
        world.choose(systemKey: "made.three")
        let lost = World(name: "Lost")
        source.insert(lost)
        lost.systemRaw = "somebody.elses"
        lost.systemVersion = 7

        for original in [world, lost] {
            let contents = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: original)))
            let (imported, _) = await WorldImporter.importWorld(contents, into: try makeContext())
            #expect(imported.systemRaw == original.systemRaw && imported.systemVersion == original.systemVersion)
        }
        // A file written before versions were recorded imports as current.
        let old = WorldExporter.makeContents(of: world)
        var archive = old.archive
        archive.world.systemVersion = nil
        let (imported, _) = await WorldImporter.importWorld(WorldPackageContents(archive: archive, files: old.files), into: try makeContext())
        #expect(imported.systemVersion == 0 && imported.systemStatus == .current)
    }
}
