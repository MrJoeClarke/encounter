//
//  MapTileTests.swift
//  encounterTests
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
import MapKit
@testable import encounter

@MainActor
struct MapTileTests {
    // MARK: Projection

    @Test func theProjectionRoundTripsAndKeepsNorthUp() {
        for point in [GridPoint(easting: 0, northing: 0), GridPoint(easting: 250_000, northing: 40_000), GridPoint(easting: 1_000_000, northing: 1_300_000)] {
            let coordinate = WebMercator.coordinate(point)
            let back = WebMercator.point(coordinate)
            #expect(abs(back.easting - point.easting) < 1e-4 && abs(back.northing - point.northing) < 1e-4)
        }
        let a = WebMercator.coordinate(GridPoint(easting: 0, northing: 0))
        let b = WebMercator.coordinate(GridPoint(easting: 100_000, northing: 100_000))
        #expect(abs(a.latitude) < 1e-9 && abs(a.longitude) < 1e-9)
        #expect(b.latitude > a.latitude && b.longitude > a.longitude)
        // About 0.9 degrees for 100 km at the equator.
        #expect(abs(b.longitude - 0.8983) < 0.001)
    }

    @Test func tilesAreNumberedFromTheTopLeftOfTheWorld() {
        let whole = WebMercator.bounds(zoom: 0, x: 0, y: 0)
        #expect(abs(whole.minEasting + WebMercator.worldSize / 2) < 1e-6)
        #expect(abs(whole.maxNorthing - WebMercator.worldSize / 2) < 1e-6)
        #expect(abs(whole.maxEasting - whole.minEasting - WebMercator.worldSize) < 1e-6)

        // At zoom 1, tile 1,1 is the south east quarter, which starts at the origin.
        let quarter = WebMercator.bounds(zoom: 1, x: 1, y: 1)
        #expect(abs(quarter.minEasting) < 1e-6 && abs(quarter.maxNorthing) < 1e-6)
    }

    @Test func theMostDetailedZoomMatchesTheImagesResolution() {
        // A tile pixel at zoom z covers 40,075,017 / (512 · 2^z) metres.
        #expect(WebMercator.zoom(forMetresPerPixel: 25) == 12)
        #expect(WebMercator.tileMetres(zoom: 12) / WebMercator.tileSize <= 25)
        #expect(WebMercator.tileMetres(zoom: 11) / WebMercator.tileSize > 25)
        #expect(WebMercator.zoom(forMetresPerPixel: 0.0001) == 21)
        #expect(WebMercator.zoom(forMetresPerPixel: 1e9) == 0)
        #expect(WebMercator.zoom(forMetresPerPixel: 0) == 0)
    }

    @Test func aReducedCopyIsChosenSoATilePixelIsNeverFinerThanTheCopy() {
        #expect(MapTileSource.reduction(forTilePixelMetres: 10, imagePixelMetres: 25) == 1)
        #expect(MapTileSource.reduction(forTilePixelMetres: 25, imagePixelMetres: 25) == 1)
        #expect(MapTileSource.reduction(forTilePixelMetres: 100, imagePixelMetres: 25) == 4)
        #expect(MapTileSource.reduction(forTilePixelMetres: 120, imagePixelMetres: 25) == 4)
        #expect(MapTileSource.reduction(forTilePixelMetres: 200, imagePixelMetres: 25) == 8)
    }

    // MARK: Tiles

    /// A 200 by 100 pixel red map at 1000 m a pixel, with its bottom left corner at the plane's origin.
    private func redMap() -> MapTileSource {
        MapTileSource(
            imageData: SampleData.solidImage(width: 200, height: 100, red: 1, green: 0, blue: 0),
            pixelWidth: 200, pixelHeight: 100,
            calibration: MapCalibration(anchoringPixel: (0, 100), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 1_000)!
        )
    }

    /// The colour of a pixel of a PNG, with the position as fractions of the tile from its left and top.
    private func pixel(of png: Data, left: Double, top: Double) throws -> (r: Int, g: Int, b: Int) {
        let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
        let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
        var bytes = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &bytes, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: -left * Double(image.width), y: -(1 - top) * Double(image.height) + 1 - 1, width: Double(image.width), height: Double(image.height)))
        return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]))
    }

    @Test func aTileHoldsTheMapWhereItLiesAndTheBackgroundWhereItDoesnt() throws {
        let source = redMap()
        // At zoom 6 a tile is about 626 km across. Tile 32,31 is the one just north east of the origin, so the
        // map fills its bottom left: 200 km of the 626 across, and 100 km of the 626 up.
        let tile = try #require(source.tile(zoom: 6, x: 32, y: 31))
        let inside = try pixel(of: tile, left: 0.1, top: 0.92)
        #expect(inside.r > 200 && inside.g < 60 && inside.b < 60)
        let outside = try pixel(of: tile, left: 0.8, top: 0.2)
        #expect(outside.r < 60 && outside.g < 60 && outside.b < 60)
        // Just beyond the map's top edge, and just beyond its right edge.
        let above = try pixel(of: tile, left: 0.1, top: 0.7)
        #expect(above.r < 60)
        let beside = try pixel(of: tile, left: 0.4, top: 0.95)
        #expect(beside.r < 60)
    }

    @Test func aTileTheMapDoesntTouchIsTheSamePlainBackgroundEveryTime() throws {
        let source = redMap()
        let first = try #require(source.tile(zoom: 6, x: 10, y: 10))
        let second = try #require(source.tile(zoom: 8, x: 3, y: 200))
        #expect(first == second)
        let colour = try pixel(of: first, left: 0.5, top: 0.5)
        #expect(colour.r < 60 && colour.g < 60 && colour.b < 60)
    }

    @Test func aTurnedMapIsDrawnTurned() throws {
        // A map turned a quarter circle anticlockwise about the origin: what was along the bottom now runs up.
        let calibration = try #require(MapCalibration(anchoringPixel: (0, 100), at: GridPoint(easting: 200_000, northing: 0), metresPerPixel: 1_000, rotation: .pi / 2))
        let source = MapTileSource(
            imageData: SampleData.solidImage(width: 200, height: 100, red: 1, green: 0, blue: 0),
            pixelWidth: 200, pixelHeight: 100, calibration: calibration
        )
        // The image now covers 100 km west to east (x from 100 to 200 km) and 200 km north.
        let bounds = source.bounds
        #expect(abs(bounds.minEasting - 100_000) < 1e-6 && abs(bounds.maxEasting - 200_000) < 1e-6)
        #expect(abs(bounds.minNorthing) < 1e-6 && abs(bounds.maxNorthing - 200_000) < 1e-6)

        let tile = try #require(source.tile(zoom: 6, x: 32, y: 31))
        let tall = try pixel(of: tile, left: 0.24, top: 1 - 150_000 / 626_172)   // 150 km east, 150 km north
        #expect(tall.r > 200)
        let wide = try pixel(of: tile, left: 0.6, top: 1 - 50_000 / 626_172)     // 375 km east: outside
        #expect(wide.r < 60)
    }

    @Test func theOverlayCoversTheWholeWorldAndStopsAtTheMapsDetail() {
        let overlay = MapTileOverlay(source: redMap())
        #expect(overlay.canReplaceMapContent)
        #expect(overlay.minimumZ == 0)
        #expect(overlay.maximumZ == WebMercator.zoom(forMetresPerPixel: 1_000) + MapTileSource.overzoom)
        #expect(overlay.tileSize == CGSize(width: 512, height: 512))
    }
}
