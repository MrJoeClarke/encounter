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
        let root = world.ensureRootPlace(in: context)
        let map = try #require(await world.addMap(named: "Coast", from: SampleData.solidImage(width: 80, height: 50, blue: 0.5), for: root, in: context))
        #expect(map.kind == .world && map.isWorldMap && map.place === root)
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
        let map = try #require(await world.addMap(named: "Huge", from: original, for: world.ensureRootPlace(in: context), in: context))
        #expect(map.pixelWidth == 5000 && map.pixelHeight == 40)
        #expect(map.imageData == original)
        #expect(ImageProcessing.pixelSize(of: try #require(map.thumbnailData))?.width ?? .max <= ImageProcessing.thumbnailDimension)

        // Other images still are reduced.
        let reduced = try #require(await ImageProcessing.prepare(original))
        #expect(ImageProcessing.pixelSize(of: reduced.imageData)?.width == ImageProcessing.maxOriginalDimension)
    }

    @Test func anImageThatCantBeReadMakesNoMap() async throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        #expect(await world.addMap(named: "Bad", from: Data("not an image".utf8), for: world.ensureRootPlace(in: context), in: context) == nil)
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
    @Test func eachKindOfMapCalibratesInItsOwnUnit() {
        #expect(DistanceUnit.forCalibrating(.world) == .miles)
        #expect(DistanceUnit.forCalibrating(.settlement) == .yards)
        #expect(DistanceUnit.forCalibrating(.scene) == .feet)
    }

    @Test func yardsAreThreeFeet() {
        #expect(DistanceUnit.yards.metres(fromValue: 1) == 0.9144)
        #expect(abs(DistanceUnit.yards.metres(fromValue: 1) - DistanceUnit.feet.metres(fromValue: 3)) < 1e-12)
        #expect(DistanceUnit.yards.format(metres: 91.44) == "100 yd")
    }

    @Test func aSettlementDistanceIsTypedInYardsAndKeptInMetres() {
        var draft = MapCalibrationDraft(unit: .forCalibrating(.settlement))
        draft.distance = 200
        #expect(abs((draft.distanceMetres ?? 0) - 182.88) < 1e-9)
        #expect(draft.distance == 200)

        draft.first = .init(pixelX: 0, pixelY: 0)
        draft.second = .init(pixelX: 400, pixelY: 0)
        let calibration = draft.calibration(kind: .settlement, imageWidth: 1000, imageHeight: 600, anchor: GridPoint(easting: 5, northing: 5))
        #expect(abs((calibration?.metresPerPixel ?? 0) - 0.4572) < 1e-9)   // 182.88 m over 400 pixels
    }

    @Test func milesConvertBothWays() {
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

@MainActor
struct MapKindsAndPlacementTests {
    private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        return (world, context)
    }

    private func place(_ title: String, in world: World, _ context: ModelContext, at point: GridPoint? = nil) -> Page {
        let page = world.addPage(kind: .place, in: context)
        page.title = title
        if let point { page.setGeometry(.point(point)) }
        return page
    }

    private func map(_ world: World, _ context: ModelContext, kind: MapKind = .world, calibrated: Bool = true) -> WorldMap {
        let map = WorldMap(name: "Map", imageData: nil, kind: kind)
        map.pixelWidth = 1000
        map.pixelHeight = 600
        context.insert(map)
        map.world = world
        if calibrated { map.calibration = MapCalibration(originEasting: 0, originNorthing: 60_000, metresPerPixel: 100) }
        return map
    }

    // MARK: Settlement and scene calibration

    @Test func aSettlementMapIsCentredOnItsSettlement() throws {
        // A 1000 by 600 map where two landmarks 400 pixels apart are 200 m apart. The settlement is at 30,000 E 40,000 N.
        let calibration = try #require(MapCalibration(
            pixelA: (100, 300), pixelB: (500, 300), distanceMetres: 200,
            imageWidth: 1000, imageHeight: 600, centredOn: p(30_000, 40_000)
        ))
        #expect(abs(calibration.metresPerPixel - 0.5) < 1e-9)
        let centre = calibration.gridPoint(atX: 500, y: 300)
        #expect(abs(centre.easting - 30_000) < 1e-6 && abs(centre.northing - 40_000) < 1e-6)
        // North is up, so the top of the image is 150 m north of the middle.
        #expect(abs(calibration.gridPoint(atX: 500, y: 0).northing - 40_150) < 1e-6)
        #expect(MapCalibration(pixelA: (1, 1), pixelB: (1, 1), distanceMetres: 5, imageWidth: 10, imageHeight: 10, centredOn: p(0, 0)) == nil)
    }

    @Test func aSceneMapIsSizedByItsSquares() throws {
        // A 30 by 18 grid of 5 ft squares on a 1500 by 900 pixel map: each square is 50 pixels.
        let squareMetres = DistanceUnit.feet.metres(fromValue: 5)
        let result = try #require(MapCalibration.scene(
            columns: 30, rows: 18, squareMetres: squareMetres, imageWidth: 1500, imageHeight: 900, centredOn: p(1_000, 2_000)
        ))
        #expect(!result.shapeMismatch)
        #expect(abs(result.calibration.metresPerPixel - squareMetres / 50) < 1e-9)
        // One square across is 5 ft.
        #expect(abs(result.calibration.distance(fromX: 0, y: 0, toX: 50, y: 0) - 1.524) < 1e-9)
        let centre = result.calibration.gridPoint(atX: 750, y: 450)
        #expect(abs(centre.easting - 1_000) < 1e-6 && abs(centre.northing - 2_000) < 1e-6)
    }

    @Test func aSceneGridThatDoesntMatchTheImageShapeIsFlagged() throws {
        let squareMetres = 1.524
        let wrong = try #require(MapCalibration.scene(
            columns: 30, rows: 30, squareMetres: squareMetres, imageWidth: 1500, imageHeight: 900, centredOn: p(0, 0)
        ))
        #expect(wrong.shapeMismatch)
        let close = try #require(MapCalibration.scene(
            columns: 30, rows: 18, squareMetres: squareMetres, imageWidth: 1500, imageHeight: 910, centredOn: p(0, 0)
        ))
        #expect(!close.shapeMismatch)
        #expect(MapCalibration.scene(columns: 0, rows: 5, squareMetres: 1, imageWidth: 10, imageHeight: 10, centredOn: p(0, 0)) == nil)
        #expect(MapCalibration.scene(columns: 5, rows: 5, squareMetres: 0, imageWidth: 10, imageHeight: 10, centredOn: p(0, 0)) == nil)
    }

    // MARK: Which place a map shows

    @Test func aSettlementOrSceneMapNeedsItsPlaceToHaveAPosition() throws {
        let (world, context) = try makeWorld()
        let town = place("Brackwater", in: world, context)
        let settlement = map(world, context, kind: .settlement, calibrated: false)
        #expect(settlement.needsPlace && !settlement.canBeCalibrated)
        settlement.place = town
        #expect(!settlement.canBeCalibrated)

        town.setGeometry(.point(p(500, 900)))
        #expect(settlement.canBeCalibrated)
        #expect(settlement.anchorPosition == p(500, 900))
        #expect(map(world, context, kind: .world, calibrated: false).canBeCalibrated)
    }

    @Test func changingASettlementMapToASceneMapDropsItsCalibration() throws {
        let (world, context) = try makeWorld()
        let town = place("Brackwater", in: world, context, at: p(500, 900))
        let map = map(world, context, kind: .settlement)
        map.place = town
        map.gridColumns = 20
        map.gridRows = 12

        map.change(to: .settlement)            // no change
        #expect(map.isCalibrated)
        map.change(to: .scene)
        #expect(map.kind == .scene && !map.isCalibrated && map.gridColumns == 0 && map.gridRows == 0)
    }

    @Test func theWorldMapStaysTheWorldMapAndNoOtherMapBecomesIt() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let town = place("Brackwater", in: world, context, at: p(500, 900))

        let worldMap = map(world, context, kind: .world)
        worldMap.place = root
        worldMap.change(to: .scene)
        #expect(worldMap.kind == .world && worldMap.isCalibrated && worldMap.isWorldMap)

        let settlement = map(world, context, kind: .settlement)
        settlement.place = town
        settlement.change(to: .world)
        #expect(settlement.kind == .settlement && settlement.isCalibrated && !settlement.isWorldMap)
    }

    // MARK: Putting places on a map

    @Test func clickingAPlaceOntoACalibratedMapGivesItAPositionAndShowsWhereItIs() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", in: world, context)
        let map = map(world, context)
        let town = place("Brackwater", in: world, context)

        #expect(map.position(town, atPixelX: 250, y: 200) == .placed)
        let spot = try #require(town.geometry?.centre)
        #expect(abs(spot.easting - 25_000) < 1e-6 && abs(spot.northing - 40_000) < 1e-6)
        let shown = try #require(map.pixel(of: town))
        #expect(abs(shown.x - 250) < 1e-6 && abs(shown.y - 200) < 1e-6)
        #expect(map.pixel(of: region) == nil)     // not placed anywhere
    }

    @Test func aPlaceOnAMapIsAdoptedByTheOutlineAroundIt() throws {
        let (world, context) = try makeWorld()
        let map = map(world, context)
        let coast = place("Coast", in: world, context)
        coast.setGeometry(.polygon([p(0, 0), p(60_000, 0), p(60_000, 60_000), p(0, 60_000)]))
        let town = place("Brackwater", in: world, context)
        map.position(town, atPixelX: 250, y: 200)
        #expect(town.parent === coast)
        #expect(town.parentSource == .automatic)
    }

    @Test func placementIsRefusedWithoutACalibrationOrOffThePlane() throws {
        let (world, context) = try makeWorld()
        let town = place("Brackwater", in: world, context)
        let person = world.addPage(kind: .character, in: context)

        #expect(map(world, context, calibrated: false).position(town, atPixelX: 10, y: 10) == .mapNotCalibrated)
        #expect(town.geometry == nil)
        #expect(map(world, context).position(person, atPixelX: 10, y: 10) == .notAPlace)

        // A scene map centred near the edge of the world reaches past it.
        let scene = map(world, context, kind: .scene, calibrated: false)
        scene.calibration = MapCalibration(anchoringPixel: (500, 300), at: p(50, 50), metresPerPixel: 1)
        #expect(scene.position(town, atPixelX: 0, y: 300) == .outsideWorld)
        #expect(town.geometry == nil)
        #expect(scene.position(town, atPixelX: 600, y: 300) == .placed)
    }

    @Test func aPlaceOffTheEdgeOfTheImageIsNotShown() throws {
        let (world, context) = try makeWorld()
        let map = map(world, context)
        let far = place("Faraway", in: world, context, at: p(500_000, 500_000))
        #expect(map.pixel(of: far) == nil)
        let near = place("Near", in: world, context, at: p(1_000, 1_000))
        #expect(map.pixel(of: near) != nil)
    }

    @Test func mapKindsGridAndPlaceSurviveExportAndImport() async throws {
        let (world, context) = try makeWorld()
        let building = place("The Gilded Gull", in: world, context, at: p(1_000, 2_000))
        let scene = map(world, context, kind: .scene)
        scene.place = building
        scene.calibration = MapCalibration(originEasting: 1, originNorthing: 2, metresPerPixel: 0.03)
        scene.gridColumns = 30
        scene.gridRows = 18

        let contents = WorldExporter.makeContents(of: world)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let copy = try #require(imported.maps?.first)
        #expect(copy.kind == .scene)
        #expect(copy.gridColumns == 30 && copy.gridRows == 18)
        #expect(copy.place?.title == "The Gilded Gull")
        #expect(copy.calibration == scene.calibration)
    }

    @Test func openingAMapShowsItOnTheWorldMapScreen() throws {
        let (world, context) = try makeWorld()
        let map = map(world, context)
        let navigation = WorldNavigation()
        navigation.searchText = "x"
        navigation.openMap(map)
        #expect(navigation.selection == .worldMap)
        #expect(navigation.selectedMap === map)
        #expect(navigation.searchText.isEmpty)

        // Choosing the world map again comes back up from a map further down.
        navigation.choose(.worldMap)
        #expect(navigation.selectedMap == nil)
    }
}
