//
//  OutlineDraftTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct OutlineDraftTests {
    private func makeWorld() throws -> (World, ModelContext, WorldMap) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        let root = world.ensureRootPlace(in: context)
        let map = WorldMap(name: "World", kind: .world)
        map.pixelWidth = 1500
        map.pixelHeight = 900
        context.insert(map)
        map.world = world
        map.place = root
        // 400 m a pixel, with the bottom left corner at the origin.
        map.calibration = MapCalibration(pixelA: (0, 0), pixelB: (1500, 0), distanceMetres: 600_000, imageHeight: 900)
        return (world, context, map)
    }

    @Test func anOutlineNeedsThreeCornersThatFormAProperShape() throws {
        let (world, context, map) = try makeWorld()
        let town = world.addPage(kind: .place, in: context)
        let calibration = try #require(map.calibration)
        var draft = OutlineDraft(page: town)

        #expect(draft.geometry(on: calibration) == nil)
        #expect(draft.problem(on: calibration) != nil)
        draft.add(x: 200, y: 500)
        draft.add(x: 700, y: 500)
        #expect(draft.geometry(on: calibration) == nil)

        draft.add(x: 700, y: 800)
        #expect(draft.problem(on: calibration) == nil)
        let shape = try #require(draft.geometry(on: calibration))
        guard case .polygon(let points) = shape else { Issue.record("not a polygon"); return }
        #expect(points.count == 3)
        // Pixel (200, 500) is 80 km east, and 160 km north of the bottom (900 - 500 pixels up).
        #expect(abs(points[0].easting - 80_000) < 1e-6 && abs(points[0].northing - 160_000) < 1e-6)
    }

    @Test func aCrossedOutlineCantBeFinishedButUndoFixesIt() throws {
        let (world, context, map) = try makeWorld()
        let calibration = try #require(map.calibration)
        var draft = OutlineDraft(page: world.addPage(kind: .place, in: context))
        for (x, y) in [(100.0, 100.0), (500, 500), (500, 100), (100, 500)] { draft.add(x: x, y: y) }   // a bow tie
        #expect(draft.geometry(on: calibration) == nil)
        #expect(draft.problem(on: calibration) != nil)

        draft.removeLast()
        #expect(draft.geometry(on: calibration) != nil)
        #expect(draft.corners.count == 3)
    }

    @Test func aClickOnTheLastCornerIsIgnored() throws {
        let (world, context, _) = try makeWorld()
        var draft = OutlineDraft(page: world.addPage(kind: .place, in: context))
        draft.add(x: 100, y: 100)
        draft.add(x: 101, y: 100.5)
        #expect(draft.corners.count == 1)
        draft.add(x: 130, y: 100)
        #expect(draft.corners.count == 2)
        draft.removeLast(); draft.removeLast(); draft.removeLast()
        #expect(draft.corners.isEmpty)
    }

    @Test func anOutlineThatReachesOffTheEdgeOfTheWorldIsRefused() throws {
        let (world, context, _) = try makeWorld()
        // A map centred near the origin reaches into negative positions.
        let scene = MapCalibration(anchoringPixel: (500, 300), at: GridPoint(easting: 50, northing: 50), metresPerPixel: 1)!
        var draft = OutlineDraft(page: world.addPage(kind: .place, in: context))
        for (x, y) in [(100.0, 100.0), (600, 100), (600, 500)] { draft.add(x: x, y: y) }
        #expect(draft.geometry(on: scene) == nil)
        #expect(draft.problem(on: scene) != nil)
    }

    @Test func finishingAnOutlineAdoptsThePlacesInsideItAndTheShapeSurvivesSaving() throws {
        let (world, context, map) = try makeWorld()
        let calibration = try #require(map.calibration)
        let town = world.addPage(kind: .place, in: context)
        town.title = "Brackwater"
        let tavern = world.addPage(kind: .place, in: context)
        tavern.title = "Tavern"
        map.position(tavern, atPixelX: 400, y: 650)           // inside the outline below
        let hut = world.addPage(kind: .place, in: context)
        map.position(hut, atPixelX: 1200, y: 200)             // outside it
        #expect(tavern.parent === world.rootPlace)

        var draft = OutlineDraft(page: town)
        for (x, y) in [(200.0, 500.0), (700, 500), (700, 800), (200, 800)] { draft.add(x: x, y: y) }
        let shape = try #require(draft.geometry(on: calibration))
        #expect(town.setGeometry(shape))

        #expect(tavern.parent === town && tavern.parentSource == .automatic)
        #expect(hut.parent === world.rootPlace)
        #expect(town.geometry == shape)
        // The place is drawn on the map at the middle of its outline.
        let shown = try #require(map.pixel(of: town))
        #expect(abs(shown.x - 450) < 1e-6 && abs(shown.y - 650) < 1e-6)

        try context.save()
        #expect(town.geometry == shape)
    }
}
