//
//  JourneyTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct JourneyTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        return (world, context)
    }

    private func character(_ name: String, in world: World, _ context: ModelContext) -> Page {
        let page = world.addPage(kind: .character, in: context)
        page.title = name
        return page
    }

    private func place(_ name: String, at easting: Double, _ northing: Double, in world: World, _ context: ModelContext) -> Page {
        let page = world.addPage(kind: .place, in: context)
        page.title = name
        _ = page.setGeometry(.point(GridPoint(easting: easting, northing: northing)))
        return page
    }

    @discardableResult
    private func event(
        _ title: String, year: Int?, at location: Page?, with people: [Page],
        in world: World, _ context: ModelContext
    ) -> Page {
        let page = world.addPage(kind: .event, in: context)
        page.title = title
        page.setStartDate(year.map { InWorldDate(year: $0, month: 1, day: 1, hour: 0) }, in: world.calendar)
        if let location { page.setLinkedPage(location, role: LinkRole.location, in: context) }
        for person in people { page.addLink(to: person, role: LinkRole.participant, in: context) }
        return page
    }

    /// A world map 200 pixels wide and 100 high, where a place at easting e and northing n is at pixel (e, 100 - n).
    private func makeMap(in world: World, _ context: ModelContext) throws -> WorldMap {
        let map = WorldMap(name: "World", kind: .world)
        map.pixelWidth = 200
        map.pixelHeight = 100
        map.calibration = try #require(MapCalibration(anchoringPixel: (0, 100), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 1))
        map.world = world
        context.insert(map)
        return map
    }

    @Test func aCharactersStopsAreTheirEventsByDateWithUndatedLast() throws {
        let (world, context) = try makeWorld()
        let hero = character("Hero", in: world, context)
        let other = character("Other", in: world, context)
        event("Late", year: 30, at: nil, with: [hero], in: world, context)
        event("Early", year: 10, at: nil, with: [hero, other], in: world, context)
        event("Unknown", year: nil, at: nil, with: [hero], in: world, context)
        event("Not Theirs", year: 20, at: nil, with: [other], in: world, context)

        let stops = JourneyBuilder.stops(of: hero, calendar: world.calendar)
        #expect(stops.map(\.event.title) == ["Early", "Late", "Unknown"])
        #expect(stops.map(\.isDated) == [true, true, false])
    }

    @Test func aCharacterWithNoEventsHasNoJourney() throws {
        let (world, context) = try makeWorld()
        let hero = character("Hero", in: world, context)
        #expect(JourneyBuilder.stops(of: hero, calendar: world.calendar).isEmpty)
    }

    @Test func aStopKnowsWhereItHappened() throws {
        let (world, context) = try makeWorld()
        let hero = character("Hero", in: world, context)
        let town = place("Town", at: 10, 10, in: world, context)
        event("Arrival", year: 1, at: town, with: [hero], in: world, context)
        event("Wandering", year: 2, at: nil, with: [hero], in: world, context)

        let stops = JourneyBuilder.stops(of: hero, calendar: world.calendar)
        #expect(stops.map { $0.place?.title } == ["Town", nil])
    }

    @Test func theRouteVisitsPlacesInOrderAndSkipsStopsItCantDraw() throws {
        let (world, context) = try makeWorld()
        let map = try makeMap(in: world, context)
        let hero = character("Hero", in: world, context)
        let a = place("A", at: 10, 20, in: world, context)
        let b = place("B", at: 100, 50, in: world, context)
        let offMap = place("Far Away", at: 5_000, 5_000, in: world, context)
        event("One", year: 1, at: a, with: [hero], in: world, context)
        event("Nowhere", year: 2, at: nil, with: [hero], in: world, context)
        event("Beyond", year: 3, at: offMap, with: [hero], in: world, context)
        event("Two", year: 4, at: b, with: [hero], in: world, context)
        event("Undated", year: nil, at: a, with: [hero], in: world, context)

        let stops = JourneyBuilder.stops(of: hero, calendar: world.calendar)
        let route = JourneyBuilder.route(of: stops, on: map)
        #expect(route == [CGPoint(x: 10, y: 80), CGPoint(x: 100, y: 50)])
    }

    @Test func stayingInOnePlaceDoesntRepeatItInTheRoute() throws {
        let (world, context) = try makeWorld()
        let map = try makeMap(in: world, context)
        let hero = character("Hero", in: world, context)
        let a = place("A", at: 10, 20, in: world, context)
        let b = place("B", at: 100, 50, in: world, context)
        event("1", year: 1, at: a, with: [hero], in: world, context)
        event("2", year: 2, at: a, with: [hero], in: world, context)
        event("3", year: 3, at: b, with: [hero], in: world, context)
        event("4", year: 4, at: a, with: [hero], in: world, context)

        let route = JourneyBuilder.route(of: JourneyBuilder.stops(of: hero, calendar: world.calendar), on: map)
        #expect(route.count == 3)
        #expect(route.first == route.last)
    }
}
