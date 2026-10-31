//
//  MapCalibrationTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
import CoreGraphics
@testable import encounter

@MainActor
struct MapCalibrationTests {
    private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

    private func expectClose(_ a: GridPoint, _ b: GridPoint, tolerance: Double = 1e-6, sourceLocation: SourceLocation = #_sourceLocation) {
        #expect(abs(a.easting - b.easting) < tolerance && abs(a.northing - b.northing) < tolerance,
                "\(a) is not \(b)", sourceLocation: sourceLocation)
    }

    @Test func twoPointsAndADistanceGiveTheScaleAndPlaceTheMapAtTheOrigin() throws {
        // A 1000 by 600 pixel map. Two towns 300 pixels apart across it are known to be 30 km apart.
        let calibration = try #require(MapCalibration(
            pixelA: (100, 200), pixelB: (400, 200), distanceMetres: 30_000, imageHeight: 600
        ))
        #expect(abs(calibration.metresPerPixel - 100) < 1e-9)
        #expect(calibration.rotation == 0)
        // North is up and the bottom left corner is the origin, so everything on the map is zero or more.
        expectClose(calibration.gridPoint(atX: 0, y: 600), p(0, 0))
        expectClose(calibration.gridPoint(atX: 1000, y: 600), p(100_000, 0))
        expectClose(calibration.gridPoint(atX: 0, y: 0), p(0, 60_000))
        expectClose(calibration.gridPoint(atX: 1000, y: 0), p(100_000, 60_000))
        #expect(calibration.gridPoint(atX: 400, y: 200).isValid)
    }

    @Test func theMarkedPointsAreTheGivenDistanceApartWhicheverWayTheyAreMarked() throws {
        let calibration = try #require(MapCalibration(
            pixelA: (700, 100), pixelB: (100, 900), distanceMetres: 5_000, imageHeight: 1000
        ))
        let a = calibration.gridPoint(atX: 700, y: 100)
        let b = calibration.gridPoint(atX: 100, y: 900)
        #expect(abs(a.distance(to: b) - 5_000) < 1e-6)
    }

    @Test func positionsRoundTripThroughAnyScaleAndTurn() throws {
        let turned = try #require(MapCalibration(anchoringPixel: (120, 80), at: p(5_000, 7_000), metresPerPixel: 37.5, rotation: 1.1))
        for pixel in [(0.0, 0.0), (300.5, 12.25), (2_000.0, 3_000.0), (-40.0, 90.0)] {
            let point = turned.gridPoint(atX: pixel.0, y: pixel.1)
            let back = turned.pixel(at: point)
            #expect(abs(back.x - pixel.0) < 1e-6 && abs(back.y - pixel.1) < 1e-6)
        }
        expectClose(turned.gridPoint(atX: 120, y: 80), p(5_000, 7_000))
        // Distances don't depend on the turn.
        #expect(abs(turned.distance(fromX: 0, y: 0, toX: 30, y: 40) - 50 * 37.5) < 1e-9)
    }

    @Test func aMapTurnedASixthOfACircleSendsEastAlongItsOwnDirection() throws {
        let calibration = try #require(MapCalibration(anchoringPixel: (0, 0), at: p(0, 0), metresPerPixel: 1, rotation: .pi / 3))
        // 100 pixels along the image's top edge is 100 m, 60 degrees anticlockwise from east.
        expectClose(calibration.gridPoint(atX: 100, y: 0), p(50, 86.60254037844386))
    }

    @Test func northIsUpTheImageWithoutATurn() throws {
        let calibration = try #require(MapCalibration(anchoringPixel: (0, 100), at: p(0, 0), metresPerPixel: 1))
        let up = calibration.pixel(at: p(0, 100))
        #expect(abs(up.x) < 1e-9 && abs(up.y) < 1e-9)
    }

    @Test func pointsThatDontDefineAScaleAreRefused() {
        #expect(MapCalibration(pixelA: (5, 5), pixelB: (5, 5), distanceMetres: 100, imageHeight: 100) == nil)
        #expect(MapCalibration(pixelA: (0, 0), pixelB: (50, 50), distanceMetres: 0, imageHeight: 100) == nil)
        #expect(MapCalibration(pixelA: (0, 0), pixelB: (50, 50), distanceMetres: -3, imageHeight: 100) == nil)
        #expect(MapCalibration(pixelA: (0, 0), pixelB: (50, 50), distanceMetres: .nan, imageHeight: 100) == nil)
        #expect(MapCalibration(pixelA: (0, 0), pixelB: (50, 50), distanceMetres: 100, imageHeight: 0) == nil)
        #expect(MapCalibration(anchoringPixel: (0, 0), at: p(0, 0), metresPerPixel: 0) == nil)
        #expect(MapCalibration(anchoringPixel: (0, 0), at: p(0, 0), metresPerPixel: -2) == nil)
    }

    @Test func aMapCentredOnAPlaceHasThatPlaceAtItsCentre() throws {
        let calibration = try #require(MapCalibration(anchoringPixel: (500, 400), at: p(3_000, 4_000), metresPerPixel: 0.5))
        expectClose(calibration.gridPoint(atX: 500, y: 400), p(3_000, 4_000))
        expectClose(calibration.gridPoint(atX: 600, y: 300), p(3_050, 4_050))   // right and up
    }

    @Test func calibrationSurvivesSavingReloadingAndExport() async throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let world = World(name: "Test")
        context.insert(world)
        let map = try #require(await world.addMap(named: "Coast", from: SampleData.solidImage(width: 80, height: 50, blue: 0.5), in: context))
        #expect(map.pixelWidth == 80 && map.pixelHeight == 50)
        #expect(map.thumbnailData != nil)
        #expect(!map.isCalibrated)
        map.calibration = MapCalibration(originEasting: 1, originNorthing: 2, metresPerPixel: 3, rotation: 0.25)
        map.kind = .settlement
        try context.save()

        let loaded = try #require(try ModelContext(container).fetch(FetchDescriptor<WorldMap>()).first)
        #expect(loaded.calibration == MapCalibration(originEasting: 1, originNorthing: 2, metresPerPixel: 3, rotation: 0.25))
        #expect(loaded.kind == .settlement)

        let contents = WorldExporter.makeContents(of: world)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let copy = try #require(imported.maps?.first)
        #expect(copy.calibration == map.calibration)
        #expect(copy.kind == .settlement)
        #expect(copy.pixelWidth == 80 && copy.pixelHeight == 50)
        #expect(copy.thumbnailData != nil)
    }

    @Test func aLargeMapIsKeptAtFullSize() async throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        // Wider than the 4096 pixels other images are reduced to.
        let original = SampleData.solidImage(width: 5000, height: 40, blue: 0.5)
        let map = try #require(await world.addMap(named: "Huge", from: original, in: context))
        #expect(map.pixelWidth == 5000 && map.pixelHeight == 40)
        #expect(map.imageData == original)
        #expect(ImageProcessing.pixelSize(of: try #require(map.thumbnailData))?.width ?? .max <= ImageProcessing.thumbnailDimension)

        // Other images still are reduced.
        let reduced = try #require(await ImageProcessing.prepare(original))
        #expect(ImageProcessing.pixelSize(of: reduced.imageData)?.width == ImageProcessing.maxOriginalDimension)

        // Showing a very large map decodes a smaller copy and never enlarges a small one.
        let shown = try #require(await ImageProcessing.downsampled(original, maxPixelSize: 1000))
        #expect(shown.width == 1000)
        let small = try #require(await ImageProcessing.downsampled(original, maxPixelSize: 100_000))
        #expect(small.width == 5000)
    }

    @Test func anImageThatCantBeReadMakesNoMap() async throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        #expect(await world.addMap(named: "Bad", from: Data("not an image".utf8), in: context) == nil)
        #expect((world.maps ?? []).isEmpty)
    }
}

@MainActor
struct MapCalibrationDraftTests {
    @Test func aDraftSaysWhatIsStillNeeded() {
        var draft = MapCalibrationDraft()
        #expect(draft.metresPerPixel == nil)
        #expect(draft.problem == String(localized: "Click the map to mark both points."))

        draft.first = .init(pixelX: 100, pixelY: 200)
        draft.second = .init(pixelX: 400, pixelY: 200)
        #expect(draft.problem == String(localized: "Enter the distance between the two points."))

        draft.distance = 18.6411   // miles
        #expect(draft.problem == nil)
        #expect(abs((draft.metresPerPixel ?? 0) - 100) < 0.01)
        #expect(draft.worldCalibration(imageHeight: 600) != nil)
    }

    @Test func theDistanceIsTypedInMilesAndKeptInMetres() {
        var draft = MapCalibrationDraft()
        draft.distance = 1
        #expect(draft.distanceMetres == 1609.344)
        draft.distanceMetres = 3218.688
        #expect(draft.distance == 2)
        draft.distance = nil
        #expect(draft.distanceMetres == nil)
    }

    @Test func twoPointsInTheSamePlaceOrNoDistanceAreNotAScale() {
        var draft = MapCalibrationDraft()
        draft.first = .init(pixelX: 10, pixelY: 10)
        draft.second = .init(pixelX: 10, pixelY: 10)
        draft.distance = 5
        #expect(draft.worldCalibration(imageHeight: 100) == nil)
        #expect(draft.problem == String(localized: "The points must be in different places, and the distance more than zero."))

        draft.second.pixelX = 500
        draft.distance = 0
        #expect(draft.problem != nil)
        #expect(draft.worldCalibration(imageHeight: 100) == nil)
    }
}

struct DistanceUnitTests {
    @Test func milesAreTheDefaultAndConvertBothWays() {
        #expect(DistanceUnit.preferred == .miles)
        #expect(DistanceUnit.miles.metres(fromValue: 1) == 1609.344)
        #expect(abs(DistanceUnit.miles.value(fromMetres: 8046.72) - 5) < 1e-12)
        for unit in DistanceUnit.allCases {
            #expect(abs(unit.value(fromMetres: unit.metres(fromValue: 12.5)) - 12.5) < 1e-9)
        }
    }

    @Test func distancesReadWithAboutThreeFigures() {
        #expect(DistanceUnit.miles.format(metres: 500_000) == "311 mi")
        #expect(DistanceUnit.miles.format(metres: 1609.344) == "1 mi")
        #expect(DistanceUnit.kilometres.format(metres: 12_345) == "12.3 km")
        #expect(DistanceUnit.feet.format(metres: 1.524) == "5 ft")
    }
}
