//
//  RootPlaceTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct RootPlaceTests {
    private func makeWorld(name: String = "Faerûn") throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: name)
        context.insert(world)
        return (world, context)
    }

    private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

    @Test func aWorldGetsARootPlaceNamedAfterIt() throws {
        let (world, context) = try makeWorld()
        #expect(world.rootPlace == nil)

        let root = world.ensureRootPlace(in: context)
        #expect(root.title == "Faerûn" && root.kind == .place)
        #expect(root.isWorldRoot && root.parent == nil)
        #expect(world.rootPlace === root)
        #expect(world.worldMap == nil)

        // Asking again changes nothing.
        #expect(world.ensureRootPlace(in: context) === root)
        #expect((world.pages ?? []).filter { $0.kind == .place }.count == 1)
    }

    @Test func aRootPlaceTakesInPlacesAndMapsFromBeforeItExisted() throws {
        let (world, context) = try makeWorld()
        let coast = world.addPage(kind: .place, in: context)
        coast.title = "Coast"
        let town = world.addPage(kind: .place, in: context)
        town.title = "Brackwater"
        town.setParent(coast)
        let person = world.addPage(kind: .character, in: context)
        let oldMap = WorldMap(name: "Old", kind: .world)
        context.insert(oldMap)
        oldMap.world = world

        let root = world.ensureRootPlace(in: context)
        #expect(coast.parent === root && coast.parentSource == .automatic)
        #expect(town.parent === coast)          // already had a parent
        #expect(person.parent == nil)
        #expect(oldMap.place === root)
        #expect(world.worldMap === oldMap)
    }

    @Test func newPlacesStartInsideTheRootPlace() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        let person = world.addPage(kind: .character, in: context)

        #expect(town.parent === root && town.parentSource == .automatic)
        #expect(person.parent == nil)
        #expect(root.childPages.count == 1)
    }

    @Test func theRootPlaceHasNoParentAndEveryOtherPlaceHasOne() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let coast = world.addPage(kind: .place, in: context)
        let town = world.addPage(kind: .place, in: context)
        town.setParent(coast)

        #expect(!root.canHaveParent(coast))
        #expect(!root.setParent(coast))
        #expect(root.parent == nil)
        // Nobody is left at the top of the world except the root.
        #expect(!town.canHaveParent(nil))
        #expect(!town.setParent(nil))
        #expect(town.parent === coast)
        #expect(town.setParent(root) && town.parent === root)
    }

    @Test func aPlaceWithoutAnOutlineAroundItFallsBackToTheRoot() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let coast = world.addPage(kind: .place, in: context)
        coast.setGeometry(.polygon([p(0, 0), p(1_000, 0), p(1_000, 1_000), p(0, 1_000)]))
        let tavern = world.addPage(kind: .place, in: context)
        tavern.setGeometry(.point(p(500, 500)))
        #expect(tavern.parent === coast)

        coast.setGeometry(nil)                  // the outline goes
        #expect(tavern.parent === root && tavern.parentSource == .automatic)
        #expect(coast.parent === root)
    }

    @Test func aParentChosenByTheCreatorIsNotMovedToTheRoot() throws {
        let (world, context) = try makeWorld()
        _ = world.ensureRootPlace(in: context)
        let coast = world.addPage(kind: .place, in: context)
        let town = world.addPage(kind: .place, in: context)
        town.setParent(coast)
        town.setGeometry(.point(p(10, 10)))
        #expect(town.parent === coast)
    }

    @Test func pathsLeaveOutTheRootPlace() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let coast = world.addPage(kind: .place, in: context)
        coast.title = "Coast"
        let town = world.addPage(kind: .place, in: context)
        town.title = "Brackwater"
        town.setParent(coast)

        #expect(town.pathTitle == "Coast › Brackwater")
        #expect(coast.pathTitle == "Coast")
        #expect(root.pathTitle == "Faerûn")
        #expect(town.ancestors.map(\.title) == ["Coast", "Faerûn"])
    }

    @Test func renamingTheWorldRenamesItsRootPlaceUnlessItHasItsOwnName() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)

        let old = world.name
        world.name = "Eberron"
        world.renameRootPlace(from: old)
        #expect(root.title == "Eberron")

        root.title = "The Known World"
        let older = world.name
        world.name = "Greyhawk"
        world.renameRootPlace(from: older)
        #expect(root.title == "The Known World")
    }

    @Test func everyWorldIsGivenARootPlaceAtLaunch() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let first = World(name: "One")
        let second = World(name: "Two")
        context.insert(first)
        context.insert(second)
        let kept = second.ensureRootPlace(in: context)

        World.ensureRootPlaces(in: context)
        #expect(first.rootPlace?.title == "One")
        #expect(second.rootPlace === kept)
    }

    @Test func aWorldWhoseRootPlaceHasNotArrivedYetIsNotGivenAnother() throws {
        // With iCloud sync a world can arrive before its pages. It already names its root place, so none is made.
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Synced")
        context.insert(world)
        let expected = UUID()
        world.rootPlaceID = expected

        World.ensureRootPlaces(in: context)
        #expect(world.rootPlaceID == expected)
        #expect((world.pages ?? []).isEmpty)
    }

    @Test func theWorldMapIsTheMapOfTheRootPlace() async throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        let image = SampleData.solidImage(width: 80, height: 50, blue: 0.5)

        let townMap = try #require(await world.addMap(named: "Town", from: image, for: town, in: context))
        #expect(townMap.kind == .settlement && !townMap.isWorldMap)
        #expect(world.worldMap == nil)

        let worldMap = try #require(await world.addMap(named: "World", from: image, for: root, in: context))
        #expect(worldMap.kind == .world && worldMap.isWorldMap)
        #expect(world.worldMap === worldMap)
        #expect(town.sortedMaps == [townMap])
    }

    @Test func aPlacePutOnASettlementsMapIsInsideThatSettlement() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        town.setGeometry(.point(p(5_000, 5_000)))
        #expect(town.parent === root)

        let map = WorldMap(name: "Town", kind: .settlement)
        map.pixelWidth = 1000
        map.pixelHeight = 600
        context.insert(map)
        map.world = world
        map.place = town
        map.calibration = MapCalibration(anchoringPixel: (500, 300), at: p(5_000, 5_000), metresPerPixel: 1)

        let tavern = world.addPage(kind: .place, in: context)
        tavern.setParent(town)                   // what the map does for a new place
        #expect(map.position(tavern, atPixelX: 600, y: 300) == .placed)
        #expect(tavern.parent === town && tavern.parentSource == .manual)
    }

    // MARK: Export and import

    @Test func theRootPlaceSurvivesExportAndImport() async throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let town = world.addPage(kind: .place, in: context)
        town.title = "Brackwater"
        let map = try #require(await world.addMap(named: "World", from: SampleData.solidImage(width: 80, height: 50, blue: 0.5), for: root, in: context))
        map.calibration = MapCalibration(originEasting: 0, originNorthing: 5_000, metresPerPixel: 100)

        let contents = WorldExporter.makeContents(of: world)
        #expect(contents.archive.world.rootPlaceID == root.id)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)

        let importedRoot = try #require(imported.rootPlace)
        #expect(importedRoot.title == "Faerûn" && importedRoot.id != root.id)
        #expect((imported.pages ?? []).filter { $0.kind == .place }.count == 2)
        #expect(importedRoot.childPages.map(\.title) == ["Brackwater"])
        #expect(imported.worldMap?.calibration == map.calibration)
    }

    @Test func aFileFromBeforeRootPlacesGetsOneOnImport() async throws {
        let (world, context) = try makeWorld()
        let coast = world.addPage(kind: .place, in: context)
        coast.title = "Coast"
        var contents = WorldExporter.makeContents(of: world)
        contents.archive.world.rootPlaceID = nil

        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let root = try #require(imported.rootPlace)
        #expect(root.title == "Faerûn")
        let importedCoast = try #require((imported.pages ?? []).first { $0.title == "Coast" })
        #expect(importedCoast.parent === root)
    }
}
