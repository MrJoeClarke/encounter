//
//  SheetTests.swift
//  encounterTests
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
import MapKit
import SwiftData
@testable import encounter

@MainActor
struct SheetTests {
    @Test func theSeaIsCutRoundTheLand() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let page = world.addPage(kind: .place, in: context)
        let sea = [GridPoint(easting: 0, northing: 0), GridPoint(easting: 1000, northing: 0), GridPoint(easting: 1000, northing: 1000), GridPoint(easting: 0, northing: 1000)]
        let land = [GridPoint(easting: 200, northing: 200), GridPoint(easting: 600, northing: 200), GridPoint(easting: 400, northing: 600)]
        let overlay = PlaceOverlay(page: page, corners: sea, holes: [land])
        #expect(overlay.interiorPolygons?.count == 1)
        #expect(PlaceOverlay(page: page, corners: sea).interiorPolygons == nil)
    }

    @Test func everyStyleHasASurroundAndTheFramedOnesHaveALine() {
        for style in MapStyle.all {
            #expect(style.surround != style.background, Comment(rawValue: style.id))
            if let frame = style.frame { #expect(frame.outer > 0, Comment(rawValue: style.id)) }
        }
        #expect(MapStyle.parchment.frame != nil)
    }

    @Test func aMapWithNoPictureIsASheetOnItsSurround() throws {
        let calibration = try #require(MapCalibration(anchoringPixel: (0, 1000), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 1))
        let source = MapTileSource(imageData: Data(), pixelWidth: 1000, pixelHeight: 1000, calibration: calibration)
        source.background = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        source.surround = CGColor(red: 0, green: 0, blue: 0, alpha: 1)
        // Zoom 0 is the whole world in one tile, so the sheet is a speck in the middle of it; a tile far from the sheet is all surround.
        let outside = try #require(source.tile(zoom: 12, x: 0, y: 0))
        let image = try #require(CGImageSourceCreateWithData(outside as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == Int(WebMercator.tileSize))
        let raw = try #require(image.dataProvider?.data)
        let pixel = Array((raw as Data).prefix(3))
        #expect(pixel.allSatisfy { $0 < 30 })
    }

    @Test func handDrawnStylesWobbleOnlyWhatIsNatural() {
        #expect(MapStyle.parchment.hand != nil && MapStyle.watercolour.hand != nil)
        #expect(MapStyle.dark.hand == nil)
        // A survey is drawn with the same renderer but with a straight, even pen.
        #expect(MapStyle.survey.hand?.amplitude == 0 && MapStyle.survey.hand?.weight == 0)
        #expect((MapStyle.parchment.hand?.amplitude ?? 0) > 0 && (MapStyle.watercolour.hand?.amplitude ?? 0) > 0)
        let types = MapStyle.HandDrawn.types
        for natural in ["Water", "Region", "Forest", "Mountains", "River", "Road"] { #expect(types.contains(natural), Comment(rawValue: natural)) }
        for crisp in ["Building", "Room", "Corridor", "Door", "Landmark"] { #expect(!types.contains(crisp), Comment(rawValue: crisp)) }
    }

    @Test func eachStyleHasItsOwnKindOfSymbol() {
        #expect(MapStyle.parchment.symbols != nil)
        #expect(MapStyle.dark.symbols == nil)
        // Each of the others has its own kind: a survey's are tidy signs and contours, a watercolour's soft dabs.
        #expect(MapStyle.survey.symbols?.regular == true && MapStyle.survey.symbols?.contours == true && MapStyle.survey.symbols?.shore == nil)
        #expect(MapStyle.watercolour.symbols?.soft == true && MapStyle.watercolour.symbols?.shore != nil)
        #expect(MapStyle.parchment.symbols?.regular == false && MapStyle.parchment.symbols?.soft == false)
        // The washes under the symbols are light, as the symbols say what the place is.
        let forest = MapStyle.parchment.style(forPlaceType: "Forest").fill
        let mountains = MapStyle.parchment.style(forPlaceType: "Mountains").fill
        #expect((forest?.alpha ?? 1) < 0.3 && (mountains?.alpha ?? 1) < 0.3)
    }
}
