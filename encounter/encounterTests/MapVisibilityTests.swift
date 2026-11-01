//
//  MapVisibilityTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
import MapKit
@testable import encounter

@MainActor
struct MapVisibilityTests {
    private func makeWorld() throws -> (World, ModelContext, WorldMap) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let map = WorldMap(name: "World", kind: .world)
        map.pixelWidth = 1000
        map.pixelHeight = 1000
        // A place at easting e and northing n is at pixel (e, 1000 - n).
        map.calibration = MapCalibration(anchoringPixel: (0, 1000), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 1)
        map.world = world
        context.insert(map)
        return (world, context, map)
    }

    private func place(_ name: String, at easting: Double, _ northing: Double, inside parent: Page? = nil, in world: World, _ context: ModelContext) -> Page {
        let page = world.addPage(kind: .place, in: context)
        page.title = name
        _ = page.setGeometry(.point(GridPoint(easting: easting, northing: northing)))
        if let parent { page.parent = parent }
        return page
    }

    @Test func aPlaceInsideAnotherPlaceOnTheMapIsLeftOffIt() throws {
        let (world, context, map) = try makeWorld()
        let kingdom = place("Kingdom", at: 500, 500, in: world, context)
        let town = place("Town", at: 520, 510, inside: kingdom, in: world, context)
        let tavern = place("Tavern", at: 521, 511, inside: town, in: world, context)
        let elsewhere = place("Elsewhere", at: 100, 100, in: world, context)
        let shown = map.visiblePlaces(among: [kingdom, town, tavern, elsewhere])
        #expect(Set(shown.map(\.title)) == ["Kingdom", "Elsewhere"])
    }

    @Test func aPlaceWhoseParentIsntOnTheMapIsStillShown() throws {
        let (world, context, map) = try makeWorld()
        let region = world.addPage(kind: .place, in: context)
        region.title = "Region with no position"
        let town = place("Town", at: 520, 510, inside: region, in: world, context)
        #expect(map.visiblePlaces(among: [region, town]).map(\.title) == ["Town"])
        // Nor is it hidden when its parent is off the edge of the image.
        let far = place("Far", at: 5_000, 5_000, in: world, context)
        let near = place("Near", at: 500, 500, inside: far, in: world, context)
        #expect(map.visiblePlaces(among: [far, near]).map(\.title) == ["Near"])
    }

    @Test func theMapsOwnPlaceDoesntHideThePlacesInIt() throws {
        let (world, context, map) = try makeWorld()
        let settlement = place("Settlement", at: 500, 500, in: world, context)
        let smithy = place("Smithy", at: 510, 505, inside: settlement, in: world, context)
        map.place = settlement
        let shown = map.visiblePlaces(among: [settlement, smithy])
        #expect(shown.map(\.title) == ["Smithy"])
    }

    @Test func anOutlinedPlaceHidesWhatIsInsideItToo() throws {
        let (world, context, map) = try makeWorld()
        let district = world.addPage(kind: .place, in: context)
        district.title = "District"
        _ = district.setGeometry(.polygon([GridPoint(easting: 400, northing: 400), GridPoint(easting: 600, northing: 400), GridPoint(easting: 600, northing: 600), GridPoint(easting: 400, northing: 600)]))
        let shop = place("Shop", at: 500, 500, inside: district, in: world, context)
        #expect(map.visiblePlaces(among: [district, shop]).map(\.title) == ["District"])
    }

    @Test func theTilesGoADeeperThanTheImageButNotBeyondWhatMapKitShows() throws {
        let calibration = try #require(MapCalibration(anchoringPixel: (0, 100), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 1_000))
        let source = MapTileSource(imageData: Data(), pixelWidth: 200, pixelHeight: 100, calibration: calibration)
        #expect(source.maximumDisplayZoom == source.maximumZoom + MapTileSource.overzoom)
        #expect(MapTileOverlay(source: source).maximumZ == source.maximumDisplayZoom)
        let tiny = try #require(MapCalibration(anchoringPixel: (0, 100), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 0.01))
        let scene = MapTileSource(imageData: Data(), pixelWidth: 200, pixelHeight: 100, calibration: tiny)
        #expect(scene.maximumDisplayZoom == 21)
    }
}
