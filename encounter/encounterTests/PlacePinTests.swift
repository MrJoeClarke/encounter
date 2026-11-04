//
//  PlacePinTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct PlacePinTests {
    private func page(type: String, kind: String = "", geometry: PlaceGeometry?) throws -> Page {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let page = world.addPage(kind: .place, in: context)
        page.attributes["core.placeType"] = .text(type)
        if !kind.isEmpty { page.attributes["gen.kind"] = .text(kind) }
        page.geometry = geometry
        return page
    }

    private let spot = GridPoint(easting: 10, northing: 10)
    private var square: [GridPoint] { [GridPoint(easting: 0, northing: 0), GridPoint(easting: 10, northing: 0), GridPoint(easting: 10, northing: 10), GridPoint(easting: 0, northing: 10)] }

    @Test func pointsHavePinsByKindAndSizeAndCapitalsWinThePlace() throws {
        #expect(PlacePinKind.of(try page(type: "Settlement", kind: "capital", geometry: .point(spot))) == .capital)
        #expect(PlacePinKind.of(try page(type: "Settlement", kind: "city", geometry: .point(spot))) == .city)
        #expect(PlacePinKind.of(try page(type: "Settlement", kind: "village", geometry: .point(spot))) == .village)
        // One whose size is not recorded is a town, and any other point is a plain pin.
        #expect(PlacePinKind.of(try page(type: "Settlement", geometry: .point(spot))) == .town)
        #expect(PlacePinKind.of(try page(type: "Point of Interest", geometry: .point(spot))) == .place)
        #expect(PlacePinKind.of(try page(type: "", geometry: .point(spot))) == .place)
        #expect(PlacePinKind.capital.size > PlacePinKind.city.size && PlacePinKind.city.size > PlacePinKind.town.size && PlacePinKind.town.size > PlacePinKind.village.size)
        #expect(PlacePinKind.capital.priority > PlacePinKind.city.priority && PlacePinKind.city.priority > PlacePinKind.village.priority)
    }

    @Test func landmarksHaveTheirOwnIconsAndEveryKindHasAnIcon() throws {
        #expect(PlacePinKind.of(try page(type: "Landmark", kind: "castle", geometry: .polygon(square))) == .castle)
        #expect(PlacePinKind.of(try page(type: "Landmark", kind: "cathedral", geometry: .polygon(square))) == .cathedral)
        #expect(PlacePinKind.of(try page(type: "Landmark", geometry: .polygon(square))) == .landmark)
        for kind in [PlacePinKind.capital, .city, .town, .village, .cathedral, .castle, .university, .library, .guildhall, .arena, .infirmary, .wizardsTower, .prison, .landmark, .place] {
            #expect(!kind.symbol.isEmpty)
        }
        #expect(Set([PlacePinKind.capital, .city, .town, .village, .cathedral, .castle, .library].map(\.symbol)).count == 7)
    }

    @Test func areasLinesAndBuildingsHaveNoPin() throws {
        for type in ["Region", "District", "Forest", "Mountains", "Lake", "Water", "Building", "Garden", "Square"] {
            #expect(PlacePinKind.of(try page(type: type, geometry: .polygon(square))) == nil, Comment(rawValue: type))
        }
        for type in ["River", "Road", "Street", "Wall"] {
            #expect(PlacePinKind.of(try page(type: type, geometry: .line([spot, GridPoint(easting: 20, northing: 20)]))) == nil, Comment(rawValue: type))
        }
        // A settlement with an outline keeps its pin, in the middle of it.
        #expect(PlacePinKind.of(try page(type: "Settlement", kind: "town", geometry: .polygon(square))) == .town)
    }

    @Test func areasAreNamedAcrossAndLinesAlongAndOthersNotAtAll() {
        for type in ["Region", "District", "Forest", "Mountains", "Water", "Lake"] { #expect(PlaceLabelKind.of(type: type) == .area, Comment(rawValue: type)) }
        for type in ["River", "Road", "Street", "Wall"] { #expect(PlaceLabelKind.of(type: type) == .line, Comment(rawValue: type)) }
        for type in ["Building", "Room", "Door", "Settlement", "Landmark"] { #expect(PlaceLabelKind.of(type: type) == nil, Comment(rawValue: type)) }
        #expect(PlaceLabelKind.priority(type: "Region") > PlaceLabelKind.priority(type: "River") && PlaceLabelKind.priority(type: "River") > PlaceLabelKind.priority(type: "Street"))
    }

    @Test func textAlongALineStaysUprightAndSitsInTheMiddle() throws {
        let east = try #require(MapKitCanvas.Coordinator.alongLine([GridPoint(easting: 0, northing: 0), GridPoint(easting: 100, northing: 0)]))
        #expect(east.point == GridPoint(easting: 50, northing: 0) && abs(east.degrees) < 1e-9)
        // A line running west is read from the other end, not upside down.
        let west = try #require(MapKitCanvas.Coordinator.alongLine([GridPoint(easting: 100, northing: 0), GridPoint(easting: 0, northing: 0)]))
        #expect(abs(west.degrees) < 1e-9)
        let north = try #require(MapKitCanvas.Coordinator.alongLine([GridPoint(easting: 0, northing: 0), GridPoint(easting: 0, northing: 100)]))
        #expect(abs(north.degrees - 90) < 1e-9)
        let south = try #require(MapKitCanvas.Coordinator.alongLine([GridPoint(easting: 0, northing: 100), GridPoint(easting: 0, northing: 0)]))
        #expect(abs(south.degrees - 90) < 1e-9)
        for degrees in [east.degrees, west.degrees, north.degrees, south.degrees] { #expect(degrees > -90 && degrees <= 90) }
        // The middle is by length, so a bend in an uneven line does not move it to the middle point.
        let bent = try #require(MapKitCanvas.Coordinator.alongLine([GridPoint(easting: 0, northing: 0), GridPoint(easting: 10, northing: 0), GridPoint(easting: 10, northing: 90)]))
        #expect(bent.point == GridPoint(easting: 10, northing: 40))
        #expect(MapKitCanvas.Coordinator.alongLine([spot]) == nil)
    }

    @Test func aGeneratedMapRecordsWhatKindOfPlaceEachIsForItsPin() async throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Aldara")
        context.insert(world)
        world.ensureRootPlace(in: context)
        var options = WorldOptions()
        options.seed = 3
        options.width = 300_000
        _ = try #require(await world.generateWorld(options: options, in: context))
        let settlements = (world.pages ?? []).filter { $0.attributeText("core.placeType") == "Settlement" }
        #expect(!settlements.isEmpty)
        let kinds = Set(settlements.compactMap { PlacePinKind.of($0) })
        #expect(kinds.contains(.capital) && kinds.contains(.village))
        // Realms, forests and the sea are drawn as areas and so have no pin.
        let areas = (world.pages ?? []).filter { ["Region", "Forest", "Mountains", "Lake", "Water"].contains($0.attributeText("core.placeType")) }
        #expect(!areas.isEmpty && areas.allSatisfy { PlacePinKind.of($0) == nil })
    }
}
