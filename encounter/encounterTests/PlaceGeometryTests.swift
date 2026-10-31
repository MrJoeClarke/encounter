//
//  PlaceGeometryTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct PlaceGeometryTests {
    private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

    private func square(_ e: Double, _ n: Double, size: Double) -> PlaceGeometry {
        .polygon([p(e, n), p(e + size, n), p(e + size, n + size), p(e, n + size)])
    }

    /// An L shape: a 100 m square with its top right quarter cut away.
    private var lShape: PlaceGeometry {
        .polygon([p(0, 0), p(100, 0), p(100, 50), p(50, 50), p(50, 100), p(0, 100)])
    }

    // MARK: Maths

    @Test func areaCentreAndDistanceOfASquare() {
        let shape = square(1000, 2000, size: 100)
        #expect(shape.area == 10_000)
        #expect(shape.centre == p(1050, 2050))
        #expect(PlaceGeometry.point(p(0, 0)).distance(to: .point(p(300, 400))) == 500)
        // The same square drawn the other way round has the same area and centre.
        let reversed = PlaceGeometry.polygon([p(0, 0), p(0, 10), p(10, 10), p(10, 0)])
        #expect(reversed.area == 100)
        #expect(reversed.centre == p(5, 5))
    }

    @Test func pointsAreInsideOnTheEdgeOrOutside() {
        let shape = square(0, 0, size: 100)
        #expect(shape.contains(p(50, 50)))
        #expect(shape.contains(p(0, 50)))
        #expect(shape.contains(p(100, 100)))
        #expect(!shape.contains(p(100.5, 50)))
        #expect(!shape.contains(p(-1, 50)))
        #expect(!PlaceGeometry.point(p(1, 1)).contains(p(1, 1)))
    }

    @Test func aConcaveShapeDoesNotHoldItsNotch() {
        #expect(lShape.contains(p(25, 75)))
        #expect(lShape.contains(p(75, 25)))
        #expect(!lShape.contains(p(75, 75)))
    }

    @Test func aPolygonHoldsSmallerPolygonsInsideIt() {
        let outer = square(0, 0, size: 100)
        #expect(outer.contains(square(10, 10, size: 20)))
        #expect(outer.contains(square(0, 0, size: 50)))
        #expect(!outer.contains(square(80, 80, size: 40)))
        #expect(!outer.contains(square(200, 200, size: 10)))
        #expect(!outer.contains(outer))
        #expect(!square(10, 10, size: 20).contains(outer))
    }

    @Test func aPolygonThatSpansAConcaveNotchIsNotHeld() {
        // Both its corners are inside the L, but it crosses the notch.
        let across = PlaceGeometry.polygon([p(10, 60), p(90, 10), p(90, 40), p(40, 90)])
        #expect(!lShape.contains(across))
        #expect(lShape.contains(square(10, 10, size: 30)))
    }

    @Test func badShapesAreNotValid() {
        #expect(PlaceGeometry.point(p(10, 20)).isValid)
        #expect(!PlaceGeometry.point(p(-1, 20)).isValid)
        #expect(!PlaceGeometry.point(p(.nan, 20)).isValid)
        #expect(!PlaceGeometry.polygon([p(0, 0), p(10, 10)]).isValid)
        #expect(!PlaceGeometry.polygon([p(0, 0), p(10, 10), p(20, 20)]).isValid)
        #expect(!PlaceGeometry.polygon([p(0, 0), p(10, 0), p(0, 10), p(10, 10)]).isValid)
        #expect(!PlaceGeometry.polygon([p(0, 0), p(10, 0), p(-5, 10)]).isValid)
        #expect(square(0, 0, size: 10).isValid)
        #expect(lShape.isValid)
    }

    @Test func geometryRoundTripsThroughJSON() throws {
        for shape in [PlaceGeometry.point(p(1, 2)), lShape] {
            let data = try JSONEncoder().encode(shape)
            #expect(try JSONDecoder().decode(PlaceGeometry.self, from: data) == shape)
        }
    }

    // MARK: Automatic parents

    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        return (world, context)
    }

    private func place(_ title: String, _ world: World, _ context: ModelContext, _ shape: PlaceGeometry? = nil) -> Page {
        let page = world.addPage(kind: .place, in: context)
        page.title = title
        if let shape { #expect(page.setGeometry(shape)) }
        return page
    }

    @Test func aPlaceInsideAnOutlineBecomesItsChild() throws {
        let (world, context) = try makeWorld()
        let town = place("Saltmarch", world, context, square(1000, 1000, size: 500))
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))
        let far = place("Faraway", world, context, .point(p(9000, 9000)))

        #expect(tavern.parent === town)
        #expect(tavern.parentSource == .automatic)
        #expect(far.parent == nil)
        #expect(far.parentSource == nil)
    }

    @Test func theSmallestOutlineWinsAndNestedOutlinesChain() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", world, context, square(0, 0, size: 10_000))
        let town = place("Saltmarch", world, context, square(1000, 1000, size: 500))
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))

        #expect(town.parent === region)
        #expect(tavern.parent === town)
        #expect(tavern.ancestors.map(\.title) == ["Saltmarch", "Coast"])
    }

    @Test func drawingAnOutlineAdoptsThePlacesInsideIt() throws {
        let (world, context) = try makeWorld()
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))
        let market = place("Market", world, context, .point(p(1200, 1200)))
        let town = place("Saltmarch", world, context)
        #expect(tavern.parent == nil)

        town.setGeometry(square(1000, 1000, size: 500))
        #expect(tavern.parent === town)
        #expect(market.parent === town)
        #expect(town.parent == nil)
    }

    @Test func aParentChosenByTheCreatorIsNeverReplaced() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", world, context)
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))
        #expect(tavern.setParent(region))

        let town = place("Saltmarch", world, context, square(1000, 1000, size: 500))
        #expect(tavern.parent === region)
        #expect(tavern.parentSource == .manual)

        // Moving the place or the outline doesn't change it either.
        tavern.setGeometry(.point(p(1200, 1300)))
        town.setGeometry(square(1000, 1000, size: 600))
        #expect(tavern.parent === region)
    }

    @Test func choosingNoParentIsAlsoAChoice() throws {
        let (world, context) = try makeWorld()
        let town = place("Saltmarch", world, context, square(1000, 1000, size: 500))
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))
        #expect(tavern.parent === town)

        #expect(tavern.setParent(nil))
        town.setGeometry(square(1000, 1000, size: 600))
        #expect(tavern.parent == nil)
    }

    @Test func movingOrRemovingAPositionUpdatesAnAutomaticParent() throws {
        let (world, context) = try makeWorld()
        let west = place("West", world, context, square(0, 0, size: 1000))
        let east = place("East", world, context, square(2000, 0, size: 1000))
        let tavern = place("Tavern", world, context, .point(p(500, 500)))
        #expect(tavern.parent === west)

        tavern.setGeometry(.point(p(2500, 500)))
        #expect(tavern.parent === east)

        tavern.setGeometry(nil)
        #expect(tavern.parent == nil)
        #expect(tavern.parentSource == nil)

        tavern.setGeometry(.point(p(500, 500)))
        east.setGeometry(nil)
        west.setGeometry(square(0, 0, size: 100))
        #expect(tavern.parent == nil)
    }

    @Test func aPlaceNeverBecomesItsOwnAncestor() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", world, context, square(0, 0, size: 1000))
        let town = place("Saltmarch", world, context, square(100, 100, size: 100))
        // A manual choice that would otherwise put the region inside the town is refused.
        #expect(!region.setParent(town))
        #expect(town.parent === region)
        #expect(region.ancestors.isEmpty)
    }

    @Test func anInvalidShapeOrANonPlaceIsRefused() throws {
        let (world, context) = try makeWorld()
        let town = place("Saltmarch", world, context)
        let person = world.addPage(kind: .character, in: context)

        #expect(!town.setGeometry(.polygon([p(0, 0), p(10, 0)])))
        #expect(town.geometry == nil)
        #expect(!person.setGeometry(.point(p(1, 1))))
        #expect(person.geometry == nil)
    }

    // MARK: Export and import

    @Test func positionsSurviveSavingAndReloading() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let world = World(name: "Test")
        context.insert(world)
        let town = place("Saltmarch", world, context, square(1000, 1000, size: 500))
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))
        try context.save()

        let pages = try ModelContext(container).fetch(FetchDescriptor<Page>())
        #expect(pages.first { $0.title == "Saltmarch" }?.geometry == square(1000, 1000, size: 500))
        #expect(pages.first { $0.title == "Tavern" }?.geometry == .point(p(1100, 1100)))
        #expect(pages.first { $0.title == "Tavern" }?.parentSource == .automatic)
        _ = (town, tavern)
    }

    @Test func positionsAndParentChoicesSurviveExportAndImport() async throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", world, context)
        let town = place("Saltmarch", world, context, square(1000, 1000, size: 500))
        let tavern = place("Tavern", world, context, .point(p(1100, 1100)))
        let hut = place("Hut", world, context, .point(p(9000, 9000)))
        #expect(hut.setParent(region))
        try context.save()
        #expect(tavern.parent === town)

        let contents = WorldExporter.makeContents(of: world)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let pages = imported.pages ?? []
        func named(_ title: String) throws -> Page { try #require(pages.first { $0.title == title }) }

        #expect(try named("Saltmarch").geometry == square(1000, 1000, size: 500))
        #expect(try named("Tavern").geometry == .point(p(1100, 1100)))
        #expect(try named("Tavern").parent === named("Saltmarch"))
        #expect(try named("Tavern").parentSource == .automatic)
        #expect(try named("Hut").parent === named("Coast"))
        #expect(try named("Hut").parentSource == .manual)
        #expect(try named("Coast").geometry == nil)
    }

    @Test func anInvalidShapeInAFileIsDropped() async throws {
        let (world, context) = try makeWorld()
        _ = place("Saltmarch", world, context)
        var contents = WorldExporter.makeContents(of: world)
        contents.archive.pages[0].geometry = .polygon([p(0, 0), p(10, 10)])

        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        #expect(imported.pages?.first?.geometry == nil)
    }
}
