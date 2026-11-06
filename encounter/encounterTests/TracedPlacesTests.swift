//
//  TracedPlacesTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct TracedPlacesTests {
    private func square(_ x: Double, _ y: Double, _ side: Double = 1000) -> [GridPoint] {
        [GridPoint(easting: x, northing: y), GridPoint(easting: x + side, northing: y), GridPoint(easting: x + side, northing: y + side), GridPoint(easting: x, northing: y + side)]
    }

    private func colour(_ id: Int, _ type: TracedType, _ name: String, _ outlines: [[GridPoint]]) -> TracedColour {
        TracedColour(id: id, red: 0.5, green: 0.5, blue: 0.5, share: 0.2, isThin: false, type: type, name: name, outlines: outlines)
    }

    private func setUp() throws -> (World, WorldMap, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let root = world.ensureRootPlace(in: context)
        let map = WorldMap(name: "Picture", imageData: Data(), kind: .world)
        map.world = world
        map.place = root
        context.insert(map)
        return (world, map, context)
    }

    @Test func eachAreaWithATypeBecomesAMarkedPlaceAndLeftOutOnesDoNot() throws {
        let (world, map, context) = try setUp()
        let colours = [
            colour(0, .water, "The Sea", [square(0, 0, 9000)]),
            colour(1, .region, "Arden", [square(1000, 1000), square(4000, 4000)]),
            colour(2, .ignore, "", [square(2000, 2000)]),
        ]
        let summary = world.addTracedPlaces(from: colours, for: map, in: context)
        #expect(summary.created == 2)
        let made = (world.pages ?? []).filter { $0.wasTraced }
        #expect(made.count == 2)
        let arden = try #require(made.first { $0.title == "Arden" })
        #expect(arden.attributeText("core.placeType") == "Region")
        #expect(arden.wasGenerated(by: map))
        // An area of two pieces is one place of two pieces.
        if case .multiPolygon(let pieces)? = arden.geometry { #expect(pieces.count == 2) } else { Issue.record("expected pieces") }
        #expect(made.first { $0.title == "The Sea" }?.attributeText("core.placeType") == "Water")
    }

    @Test func tracingAgainReplacesWhatWasMadeAndKeepsWhatWasEdited() throws {
        let (world, map, context) = try setUp()
        let colours = [colour(0, .region, "Arden", [square(0, 0)]), colour(1, .forest, "Thornwood", [square(3000, 3000)])]
        world.addTracedPlaces(from: colours, for: map, in: context)
        let arden = try #require((world.pages ?? []).first { $0.title == "Arden" })
        arden.title = "Arden, renamed"
        let summary = world.addTracedPlaces(from: colours, for: map, in: context)
        #expect(summary.replaced == 1)
        #expect(summary.kept == 1)
        let titles = (world.pages ?? []).filter { !$0.isDeleted && $0.wasTraced }.map(\.title).sorted()
        #expect(titles == ["Arden", "Arden, renamed", "Thornwood"])
    }
}
