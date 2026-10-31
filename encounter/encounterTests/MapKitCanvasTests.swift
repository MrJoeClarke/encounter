//
//  MapKitCanvasTests.swift
//  encounterTests
//

import Testing
import Foundation
import MapKit
import SwiftData
#if os(macOS)
import AppKit
#endif
@testable import encounter

@MainActor
struct MapKitCanvasTests {
    private func makeMap() throws -> (WorldMap, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        let map = WorldMap(name: "Map", imageData: SampleData.solidImage(width: 1500, height: 900))
        map.pixelWidth = 1500
        map.pixelHeight = 900
        context.insert(map)
        map.world = world
        map.calibration = MapCalibration(pixelA: (0, 0), pixelB: (1500, 0), distanceMetres: 600_000, imageHeight: 900)
        return (map, context)
    }

    #if os(macOS)
    @Test func rightClickingTheMapOffersToAddAPlaceWhereItWasClicked() throws {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400), styleMask: [.titled], backing: .buffered, defer: false)
        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
        window.contentView = view
        var placed: [CGPoint] = []
        view.onPlace = { placed.append($0) }

        let event = try #require(NSEvent.mouseEvent(
            with: .rightMouseDown, location: NSPoint(x: 150, y: 300), modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))

        // Not while placing is off.
        view.canPlace = false
        #expect(view.menu(for: event)?.items.contains { $0.title == String(localized: "Add Place Here…") } != true)

        view.canPlace = true
        let menu = try #require(view.menu(for: event))
        let item = try #require(menu.items.first { $0.title == String(localized: "Add Place Here…") })
        _ = item.target?.perform(item.action, with: item)
        let point = try #require(placed.first)
        let expected = view.convert(event.locationInWindow, from: nil)
        #expect(abs(point.x - expected.x) < 0.001 && abs(point.y - expected.y) < 0.001)
    }

    @Test func aClickOnTheMapGivesThePixelUnderIt() throws {
        let (map, _) = try makeMap()
        var placed: [(Double, Double)] = []
        let canvas = MapKitCanvas(map: map, canPlace: true, onPlace: { placed.append(($0, $1)) })

        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let coordinator = canvas.makeCoordinator()
        coordinator.parent = canvas
        coordinator.calibration = canvas.displayCalibration
        // Show the middle of the map, 6 degrees across.
        let middle = WebMercator.coordinate(canvas.displayCalibration.gridPoint(atX: 750, y: 450))
        view.setRegion(MKCoordinateRegion(center: middle, span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 3.2)), animated: false)

        coordinator.handle(point: CGPoint(x: 400, y: 250), in: view, place: true)
        let spot = try #require(placed.first)
        // The centre of the view is the centre of the map, give or take the rounding of MapKit's region.
        #expect(abs(spot.0 - 750) < 15 && abs(spot.1 - 450) < 15)
    }

    @Test func clickingInsideAnOutlineSelectsThatPlaceAndTheSmallestOneWins() throws {
        let (map, context) = try makeMap()
        let world = try #require(map.world)
        func shape(_ title: String, _ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) -> PlaceShape {
            let page = world.addPage(kind: .place, in: context)
            page.title = title
            let calibration = map.calibration!
            let corners = [(x1, y1), (x2, y1), (x2, y2), (x1, y2)].map { calibration.gridPoint(atX: $0.0, y: $0.1) }
            return PlaceShape(page: page, corners: corners)
        }
        let coast = shape("Coast", 100, 100, 1400, 800)
        let town = shape("Town", 600, 300, 900, 600)
        var selected: [String?] = []
        let canvas = MapKitCanvas(map: map, shapes: [coast, town], onSelect: { selected.append($0?.title) })

        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let coordinator = canvas.makeCoordinator()
        coordinator.parent = canvas
        coordinator.calibration = canvas.displayCalibration
        let middle = WebMercator.coordinate(canvas.displayCalibration.gridPoint(atX: 750, y: 450))
        view.setRegion(MKCoordinateRegion(center: middle, span: MKCoordinateSpan(latitudeDelta: 4.2, longitudeDelta: 6.5)), animated: false)

        coordinator.handle(point: CGPoint(x: 400, y: 250), in: view, place: false)   // the middle of the map: in both
        #expect(selected.last == "Town")
        coordinator.handle(point: CGPoint(x: 201, y: 250), in: view, place: false)   // a fifth of the way across: the coast only
        #expect(selected.last == "Coast")
        coordinator.handle(point: CGPoint(x: 5, y: 5), in: view, place: false)       // off the corner of the map: neither
        #expect(selected.last == .some(nil))
    }

    @Test func onlyAPlaceThatIsAPointCanBeDragged() throws {
        let (map, context) = try makeMap()
        let world = try #require(map.world)
        let tavern = world.addPage(kind: .place, in: context)
        map.position(tavern, atPixelX: 300, y: 300)
        let town = world.addPage(kind: .place, in: context)
        let calibration = try #require(map.calibration)
        var draft = OutlineDraft(page: town)
        for (x, y) in [(500.0, 400.0), (800, 400), (800, 700)] { draft.add(x: x, y: y) }
        town.setGeometry(try #require(draft.geometry(on: calibration)))

        #expect(tavern.isPoint)
        #expect(!town.isPoint)
        let outlined = try #require(map.pixel(of: town))
        #expect(abs(outlined.x - 700) < 1e-6)   // the middle of a triangle, a third of the way from its right edge
    }

    @Test func aClickOnlyMarksACalibrationPointWhileMarking() throws {
        let (map, _) = try makeMap()
        var marked = 0
        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        view.setRegion(MKCoordinateRegion(center: WebMercator.coordinate(GridPoint(easting: 300_000, northing: 180_000)), span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 3)), animated: false)

        var canvas = MapKitCanvas(map: map, isMarking: false, onTap: { _, _ in marked += 1 })
        let coordinator = canvas.makeCoordinator()
        coordinator.calibration = canvas.displayCalibration
        coordinator.parent = canvas
        coordinator.handle(point: CGPoint(x: 100, y: 100), in: view, place: false)
        #expect(marked == 0)

        canvas.isMarking = true
        coordinator.parent = canvas
        coordinator.handle(point: CGPoint(x: 100, y: 100), in: view, place: false)
        #expect(marked == 1)
    }
    #endif

    // MARK: Scene grid

    @Test func theGridCoversTheMapAndNoMore() throws {
        let squareMetres = 1.524
        let calibration = try #require(MapCalibration.scene(
            columns: 30, rows: 18, squareMetres: squareMetres, imageWidth: 1500, imageHeight: 900, centredOn: GridPoint(easting: 5_000, northing: 5_000)
        )).calibration
        let grid = SceneGridOverlay(calibration: calibration, pixelWidth: 1500, pixelHeight: 900, columns: 30, rows: 18)

        // 45.72 m by 27.43 m, near the equator where a map point is almost a metre.
        let metresPerMapPoint = MKMetersPerMapPointAtLatitude(grid.coordinate.latitude)
        #expect(abs(grid.boundingMapRect.width * metresPerMapPoint - 45.72) < 0.5)
        #expect(abs(grid.boundingMapRect.height * metresPerMapPoint - 27.43) < 0.5)
        #expect(abs(WebMercator.point(grid.coordinate).easting - 5_000) < 0.5)

        let same = SceneGridOverlay(calibration: calibration, pixelWidth: 1500, pixelHeight: 900, columns: 30, rows: 18)
        let other = SceneGridOverlay(calibration: calibration, pixelWidth: 1500, pixelHeight: 900, columns: 20, rows: 12)
        #expect(grid.matches(same) && !grid.matches(other))
    }

    @Test func anUncalibratedMapIsShownAtAMadeUpScaleAndACalibratedOneAsCalibrated() throws {
        let (map, _) = try makeMap()
        #expect(MapKitCanvas(map: map).displayCalibration == map.calibration)

        map.calibration = nil
        let provisional = MapKitCanvas(map: map).displayCalibration
        #expect(provisional.metresPerPixel == 100)
        // Bottom left at the origin, so it shows near the equator where tiles are cut.
        let corner = provisional.gridPoint(atX: 0, y: 900)
        #expect(abs(corner.easting) < 1e-6 && abs(corner.northing) < 1e-6)
    }
}
