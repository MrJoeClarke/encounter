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

    @Test func includedLinesBecomeRiversAndRoadsAndSwitchedOffOnesDoNot() throws {
        let (world, map, context) = try setUp()
        let path = [GridPoint(easting: 0, northing: 0), GridPoint(easting: 1000, northing: 500), GridPoint(easting: 2000, northing: 500)]
        let lines = [
            TracedLine(id: 0, kind: .river, points: path, name: "River Danus", isNamed: true),
            TracedLine(id: 1, kind: .road, points: path, name: "Road 1", isNamed: false),
            TracedLine(id: 2, kind: .road, points: path, name: "Road 2", isNamed: false, isIncluded: false),
        ]
        let summary = world.addTracedPlaces(from: [], lines: lines, for: map, in: context)
        #expect(summary.created == 2)
        let made = (world.pages ?? []).filter { $0.wasTraced }
        #expect(made.first { $0.title == "River Danus" }?.attributeText("core.placeType") == "River")
        #expect(made.first { $0.title == "Road 1" }?.attributeText("core.placeType") == "Road")
        if case .line(let points)? = made.first?.geometry { #expect(points.count == 3) } else { Issue.record("expected a line") }
    }

    @Test func includedDotsBecomeSettlementsWithTheirSize() throws {
        let (world, map, context) = try setUp()
        let dots = [
            TracedDot(id: 0, point: GridPoint(easting: 1000, northing: 1000), size: 12, name: "Smyrna", isNamed: true, kind: "city"),
            TracedDot(id: 1, point: GridPoint(easting: 2000, northing: 1000), size: 6, name: "Settlement 1", isNamed: false, kind: "village", isIncluded: false),
        ]
        let summary = world.addTracedPlaces(from: [], dots: dots, for: map, in: context)
        #expect(summary.created == 1)
        let smyrna = try #require((world.pages ?? []).first { $0.title == "Smyrna" })
        #expect(smyrna.attributeText("core.placeType") == "Settlement")
        #expect(smyrna.attributeText("gen.kind") == "city")
        if case .point(let at)? = smyrna.geometry { #expect(at.easting == 1000) } else { Issue.record("expected a point") }
    }
}
