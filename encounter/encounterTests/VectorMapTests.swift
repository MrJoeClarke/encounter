//
//  VectorMapTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

private func p(_ e: Double, _ n: Double) -> GridPoint { GridPoint(easting: e, northing: n) }

@MainActor
struct LineGeometryTests {
    @Test func aLineNeedsTwoPlacedPointsAndALength() {
        #expect(PlaceGeometry.line([p(0, 0), p(10, 0)]).isValid)
        #expect(PlaceGeometry.line([p(0, 0), p(10, 5), p(20, 0), p(10, -0)]).isValid)
        #expect(!PlaceGeometry.line([p(0, 0)]).isValid)
        #expect(!PlaceGeometry.line([]).isValid)
        #expect(!PlaceGeometry.line([p(5, 5), p(5, 5)]).isValid)
        #expect(!PlaceGeometry.line([p(0, 0), p(-1, 4)]).isValid)
        // A line may cross itself, as a road can at a junction.
        #expect(PlaceGeometry.line([p(0, 0), p(10, 10), p(10, 0), p(0, 10)]).isValid)
    }

    @Test func aLineHasALengthAndNoArea() {
        let line = PlaceGeometry.line([p(0, 0), p(3, 4), p(3, 14)])
        #expect(line.length == 15 && line.area == 0)
        #expect(PlaceGeometry.point(p(1, 1)).length == 0 && PlaceGeometry.polygon([p(0, 0), p(1, 0), p(0, 1)]).length == 0)
    }

    @Test func theCentreOfALineIsHalfWayAlongIt() {
        #expect(PlaceGeometry.line([p(0, 0), p(10, 0)]).centre == p(5, 0))
        // 15 metres long, so 7.5 along: 5 metres up the first bend, then 2.5 of the second.
        let bent = PlaceGeometry.line([p(0, 0), p(3, 4), p(3, 14)])
        #expect(bent.centre == p(3, 6.5))
        // On the line even where the average of its points isn't.
        let u = PlaceGeometry.line([p(0, 0), p(0, 10), p(10, 10), p(10, 0)])
        #expect(u.centre == p(5, 10))
    }

    @Test func theDistanceToALineIsToTheNearestPartOfIt() {
        let line = PlaceGeometry.line([p(0, 0), p(10, 0), p(10, 10)])
        #expect(line.distance(toPoint: p(5, 3)) == 3)
        #expect(line.distance(toPoint: p(13, 5)) == 3)
        #expect(line.distance(toPoint: p(-4, 3)) == 5)
        #expect(PlaceGeometry.polygon([p(0, 0), p(1, 0), p(0, 1)]).distance(toPoint: p(0, 0)) == nil)
    }

    @Test func anOutlineHoldsALineOnlyWhenAllOfItIsInside() {
        let region = PlaceGeometry.polygon([p(0, 0), p(100, 0), p(100, 100), p(0, 100)])
        #expect(region.contains(.line([p(10, 10), p(50, 60), p(90, 20)])))
        #expect(!region.contains(.line([p(10, 10), p(150, 50)])))
        #expect(!region.contains(.line([p(-5, 50), p(50, 50)])))
        // Out and back in again isn't held, even with every point inside.
        let notch = PlaceGeometry.polygon([p(0, 0), p(100, 0), p(100, 40), p(60, 40), p(60, 60), p(100, 60), p(100, 100), p(0, 100)])
        #expect(!notch.contains(.line([p(80, 20), p(80, 80)])))
        // A line holds nothing.
        #expect(!PlaceGeometry.line([p(0, 0), p(10, 0)]).contains(p(5, 0)))
        #expect(!PlaceGeometry.line([p(0, 0), p(10, 0)]).contains(.point(p(5, 0))))
    }

    @Test func aLineIsKeptAsAPlacesShape() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let river = world.addPage(kind: .place, in: context)
        #expect(river.setGeometry(.line([p(0, 0), p(50, 10)])))
        #expect(river.geometry == .line([p(0, 0), p(50, 10)]) && river.isLine && !river.isPoint)
        #expect(!river.setGeometry(.line([p(0, 0)])))
        try context.save()
    }

    @Test func aRiverInsideARegionBecomesPartOfItAutomatically() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let region = world.addPage(kind: .place, in: context)
        _ = region.setGeometry(.polygon([p(0, 0), p(1000, 0), p(1000, 1000), p(0, 1000)]))
        let river = world.addPage(kind: .place, in: context)
        _ = river.setGeometry(.line([p(100, 100), p(500, 600), p(900, 900)]))
        let leaving = world.addPage(kind: .place, in: context)
        _ = leaving.setGeometry(.line([p(100, 100), p(2000, 600)]))
        #expect(river.parent === region)
        #expect(leaving.parent !== region)
    }
}

struct PlaceStyleTests {
    @Test func everyPlaceTypeHasAStyleAndTheOrderPutsAreasUnderBuildingsUnderLines() {
        let order = ["Water", "Region", "Wilderness", "Forest", "Mountains", "Settlement", "Building", "River", "Road"].map { PlaceStyle.style(forPlaceType: $0).drawOrder }
        #expect(order == order.sorted() && Set(order).count == order.count)
        for type in PlaceStyle.types { #expect(PlaceStyle.style(forPlaceType: type).lineWidth > 0) }
    }

    @Test func linesAreNotFilledAndAreasAre() {
        #expect(PlaceStyle.style(forPlaceType: "River").fill == nil && PlaceStyle.style(forPlaceType: "Road").fill == nil)
        for type in ["Water", "Forest", "Settlement", "Building", "Region", "District"] { #expect(PlaceStyle.style(forPlaceType: type).fill != nil) }
        #expect(PlaceStyle.isLineType("River") && PlaceStyle.isLineType("Road") && !PlaceStyle.isLineType("Water") && !PlaceStyle.isLineType(nil))
    }

    @Test func anUntypedPlaceKeepsTheOldRedOutline() {
        #expect(PlaceStyle.style(forPlaceType: nil) == .plain && PlaceStyle.style(forPlaceType: "") == .plain)
        #expect(PlaceStyle.style(forPlaceType: "Something Else") == .plain)
    }

    @Test func thePlaceTypeChoicesAreTheTypesTheMapDraws() {
        let definition = CoreAttributes.all.first { $0.key == "core.placeType" }
        guard case .choice(let choices)? = definition?.type else { Issue.record("Expected a choice"); return }
        #expect(choices == PlaceStyle.types)
        #expect(choices.contains("Settlement") && choices.contains("River") && choices.contains("Building"))
    }
}

@MainActor
struct VectorMapTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        return (world, context)
    }

    @Test func aWorldVectorMapIsCalibratedFromTheStart() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let map = try #require(world.addVectorMap(named: "World", for: root, extentMetres: 1_609_344, in: context))
        #expect(map.isVector && map.isCalibrated && map.kind == .world && map.isWorldMap && map.place === root)
        #expect(map.imageData == nil && map.pixelWidth == 1_609_344 && map.pixelHeight == 1_609_344)
        // The south-west corner of the plane is the bottom left of the map.
        let corner = try #require(map.calibration).gridPoint(atX: 0, y: Double(map.pixelHeight))
        #expect(corner == p(0, 0))
        let town = world.addPage(kind: .place, in: context)
        _ = town.setGeometry(.point(p(804_672, 804_672)))
        let pixel = try #require(map.pixel(of: town))
        #expect(pixel.x == 804_672 && pixel.y == 804_672)
    }

    @Test func aSettlementVectorMapIsCentredOnItsPlace() throws {
        let (world, context) = try makeWorld()
        let town = world.addPage(kind: .place, in: context)
        _ = town.setGeometry(.point(p(50_000, 60_000)))
        let map = try #require(world.addVectorMap(named: "Town", for: town, extentMetres: 2_000, in: context))
        #expect(map.kind == .settlement && !map.isWorldMap)
        let middle = try #require(map.calibration).gridPoint(atX: 1_000, y: 1_000)
        #expect(middle == p(50_000, 60_000))
        // Near the edge of the plane the map is kept on it, rather than going negative.
        let corner = world.addPage(kind: .place, in: context)
        _ = corner.setGeometry(.point(p(300, 400)))
        let cornerMap = try #require(world.addVectorMap(named: "Corner", for: corner, extentMetres: 2_000, in: context))
        #expect(try #require(cornerMap.calibration).gridPoint(atX: 0, y: 2_000) == p(0, 0))
    }

    @Test func aTinyOrBrokenSizeMakesNoMap() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        #expect(world.addVectorMap(named: "x", for: root, extentMetres: 5, in: context) == nil)
        #expect(world.addVectorMap(named: "x", for: root, extentMetres: .nan, in: context) == nil)
        #expect(world.addVectorMap(named: "x", for: root, extentMetres: .infinity, in: context) == nil)
        #expect((world.maps ?? []).isEmpty)
    }

    @Test func aMapWithNoPictureHasPlainTilesEverywhere() throws {
        let calibration = try #require(MapCalibration(anchoringPixel: (0, 1000), at: p(0, 0), metresPerPixel: 1))
        let source = MapTileSource(imageData: Data(), pixelWidth: 1000, pixelHeight: 1000, calibration: calibration)
        let inside = try #require(source.tile(zoom: 20, x: 0, y: 0))
        let outside = try #require(source.tile(zoom: 3, x: 1, y: 1))
        #expect(!inside.isEmpty && inside == outside)
        #expect(inside == source.tile(zoom: 12, x: 2_048, y: 2_048))
    }

    @Test func linesAndOutlinesAreShownAndALineGetsNoPin() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let map = try #require(world.addVectorMap(named: "World", for: root, extentMetres: 100_000, in: context))
        let lake = world.addPage(kind: .place, in: context)
        _ = lake.setGeometry(.polygon([p(10_000, 10_000), p(20_000, 10_000), p(20_000, 20_000), p(10_000, 20_000)]))
        let river = world.addPage(kind: .place, in: context)
        _ = river.setGeometry(.line([p(0, 5_000), p(50_000, 40_000)]))
        let shown = map.visiblePlaces(among: [lake, river])
        #expect(Set(shown.map(\.id)) == Set([lake.id, river.id]))
        // A line's centre is on the map, and so it counts, but the map draws it as its line.
        #expect(river.isLine && map.pixel(of: river) != nil)
    }

    @Test func aVectorMapSurvivesExportAndImport() async throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let map = try #require(world.addVectorMap(named: "World", for: root, extentMetres: 500_000, in: context))
        let road = world.addPage(kind: .place, in: context)
        road.title = "King's Road"
        road.setAttributeText("core.placeType", "Road")
        _ = road.setGeometry(.line([p(1_000, 2_000), p(250_000, 300_000), p(400_000, 90_000)]))
        try context.save()

        let wrapper = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))
        let contents = try WorldPackage.contents(of: wrapper)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, summary) = await WorldImporter.importWorld(contents, into: target)
        #expect(summary.maps == 1)
        let copy = try #require((imported.maps ?? []).first)
        #expect(copy.isVector && copy.isCalibrated && copy.pixelWidth == 500_000 && copy.pixelHeight == 500_000 && copy.imageData == nil)
        #expect(copy.calibration == map.calibration)
        let importedRoad = try #require((imported.pages ?? []).first { $0.title == "King's Road" })
        #expect(importedRoad.geometry == .line([p(1_000, 2_000), p(250_000, 300_000), p(400_000, 90_000)]))
        #expect(importedRoad.attributeText("core.placeType") == "Road")
    }

    @Test func anOldMapRecordImportsAsAPictureMap() async throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Old"}"#
        let record = try JSONDecoder().decode(MapRecord.self, from: Data(json.utf8))
        #expect(record.isVector == nil && record.extentMetres == nil)
    }
}

@MainActor
struct LineDraftTests {
    /// The context is returned too, since a page doesn't outlive it.
    private func page() throws -> (Page, MapCalibration, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        return (world.addPage(kind: .place, in: context), try #require(MapCalibration(anchoringPixel: (0, 100), at: p(0, 0), metresPerPixel: 10)), context)
    }

    @Test func aLineNeedsTwoPointsNotThree() throws {
        let (page, calibration, _) = try page()
        var draft = OutlineDraft(page: page, isLine: true)
        #expect(draft.geometry(on: calibration) == nil && draft.problem(on: calibration)?.contains("at least two") == true)
        draft.add(x: 10, y: 90)
        #expect(draft.geometry(on: calibration) == nil)
        draft.add(x: 40, y: 50)
        #expect(draft.problem(on: calibration) == nil)
        #expect(draft.geometry(on: calibration) == .line([p(100, 100), p(400, 500)]))
        draft.add(x: 70, y: 20)
        #expect(draft.geometry(on: calibration)?.length ?? 0 > 600)
    }

    @Test func anOutlineStillNeedsThreeCorners() throws {
        let (page, calibration, _) = try page()
        var draft = OutlineDraft(page: page)
        draft.add(x: 10, y: 90)
        draft.add(x: 40, y: 90)
        #expect(draft.geometry(on: calibration) == nil)
        draft.add(x: 40, y: 50)
        guard case .polygon? = draft.geometry(on: calibration) else { Issue.record("Expected a polygon"); return }
    }

    @Test func aLinePastTheEdgeOfTheWorldIsRefused() throws {
        let (page, calibration, _) = try page()
        var draft = OutlineDraft(page: page, isLine: true)
        draft.add(x: 10, y: 90)
        draft.add(x: -50, y: 50)
        #expect(draft.geometry(on: calibration) == nil && draft.problem(on: calibration)?.contains("edge of the world") == true)
    }
}

#if os(macOS)
import AppKit
import MapKit

@MainActor
struct VectorCanvasTests {
    private struct Fixture {
        let map: WorldMap
        let context: ModelContext
        let world: World
        let sea: Page, town: Page, hall: Page, river: Page
    }

    private func fixture() throws -> Fixture {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let root = world.ensureRootPlace(in: context)
        let map = try #require(world.addVectorMap(named: "World", for: root, extentMetres: 400_000, in: context))
        func area(_ title: String, _ type: String, _ box: (Double, Double, Double, Double)) -> Page {
            let page = world.addPage(kind: .place, in: context)
            page.title = title
            page.setAttributeText("core.placeType", type)
            _ = page.setGeometry(.polygon([p(box.0, box.1), p(box.2, box.1), p(box.2, box.3), p(box.0, box.3)]))
            return page
        }
        let sea = area("Sea", "Water", (0, 0, 400_000, 90_000))
        let town = area("Town", "Settlement", (190_000, 150_000, 215_000, 175_000))
        let hall = area("Hall", "Building", (196_000, 156_000, 202_000, 162_000))
        let river = world.addPage(kind: .place, in: context)
        river.title = "River"
        river.setAttributeText("core.placeType", "River")
        _ = river.setGeometry(.line([p(100_000, 330_000), p(200_000, 190_000), p(230_000, 60_000)]))
        return Fixture(map: map, context: context, world: world, sea: sea, town: town, hall: hall, river: river)
    }

    private func shapes(_ map: WorldMap, _ pages: [Page]) -> (shapes: [PlaceShape], lines: [PlaceLine]) {
        let shown = map.visiblePlaces(among: pages)
        let shapes = shown.compactMap { page -> PlaceShape? in
            if case .polygon(let corners)? = page.geometry { PlaceShape(page: page, corners: corners) } else { nil }
        }
        let lines = shown.compactMap { page -> PlaceLine? in
            if case .line(let points)? = page.geometry { PlaceLine(page: page, points: points) } else { nil }
        }
        return (shapes, lines)
    }

    private func sync(_ f: Fixture, _ view: PlacingMapView, _ coordinator: MapKitCanvas.Coordinator, _ canvas: MapKitCanvas) {
        coordinator.sync(markers: [], pins: [], shapes: canvas.shapes, draft: [], draftIsLine: false, route: [], lines: canvas.lines, grid: nil, in: view)
    }

    @Test func areasAndLinesAreDrawnFromTheBottomUp() throws {
        let f = try fixture()
        let (areas, lines) = shapes(f.map, [f.sea, f.town, f.hall, f.river])
        // The hall is inside the town, so only the town is drawn.
        #expect(Set(areas.map(\.page.title)) == ["Sea", "Town"] && lines.map(\.page.title) == ["River"])
        let canvas = MapKitCanvas(map: f.map, shapes: areas, lines: lines)
        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let coordinator = canvas.makeCoordinator()
        coordinator.parent = canvas
        coordinator.calibration = canvas.displayCalibration
        sync(f, view, coordinator, canvas)
        let drawn = view.overlays.compactMap { overlay -> String? in
            (overlay as? PlaceOverlay)?.page.title ?? (overlay as? PlaceLineOverlay)?.page.title
        }
        #expect(drawn == ["Sea", "Town", "River"])
    }

    @Test func eachTypeIsDrawnInItsOwnStyle() throws {
        let f = try fixture()
        let (areas, lines) = shapes(f.map, [f.sea, f.town, f.river])
        let canvas = MapKitCanvas(map: f.map, shapes: areas, lines: lines)
        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let coordinator = canvas.makeCoordinator()
        coordinator.parent = canvas
        coordinator.calibration = canvas.displayCalibration
        sync(f, view, coordinator, canvas)
        let sea = try #require(view.overlays.compactMap { $0 as? PlaceOverlay }.first { $0.page.title == "Sea" })
        let seaRenderer = try #require(coordinator.mapView(view, rendererFor: sea) as? MKPolygonRenderer)
        #expect(seaRenderer.fillColor != nil && seaRenderer.lineWidth == PlaceStyle.style(forPlaceType: "Water").lineWidth)
        let river = try #require(view.overlays.compactMap { $0 as? PlaceLineOverlay }.first)
        let riverRenderer = try #require(coordinator.mapView(view, rendererFor: river) as? MKPolylineRenderer)
        #expect(riverRenderer.lineWidth == 3.5 && riverRenderer.strokeColor != nil)
    }

    @Test func nothingIsRedrawnWhenNothingChangedButAChangeOfTypeRedrawsIt() throws {
        let f = try fixture()
        let (areas, lines) = shapes(f.map, [f.sea, f.town, f.river])
        let canvas = MapKitCanvas(map: f.map, shapes: areas, lines: lines)
        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let coordinator = canvas.makeCoordinator()
        coordinator.parent = canvas
        coordinator.calibration = canvas.displayCalibration
        sync(f, view, coordinator, canvas)
        let before = view.overlays.map { ObjectIdentifier($0) }
        sync(f, view, coordinator, canvas)
        #expect(view.overlays.map { ObjectIdentifier($0) } == before)
        // A place made into a lake is a new overlay with a new look.
        f.town.setAttributeText("core.placeType", "Water")
        sync(f, view, coordinator, canvas)
        #expect(view.overlays.map { ObjectIdentifier($0) } != before)
        #expect(view.overlays.count == before.count)
    }

    @Test func clickingOnARoadSelectsItAndClickingFarFromItDoesNot() throws {
        let f = try fixture()
        let (areas, lines) = shapes(f.map, [f.river])
        var selected: [String?] = []
        let canvas = MapKitCanvas(map: f.map, shapes: areas, lines: lines, onSelect: { selected.append($0?.title) })
        let view = PlacingMapView(frame: NSRect(x: 0, y: 0, width: 800, height: 500))
        let coordinator = canvas.makeCoordinator()
        coordinator.parent = canvas
        coordinator.calibration = canvas.displayCalibration
        // The view shows the river from 60 to 330 km north and 90 to 240 km east.
        let centre = WebMercator.coordinate(p(165_000, 195_000))
        view.setRegion(MKCoordinateRegion(center: centre, span: MKCoordinateSpan(latitudeDelta: 3, longitudeDelta: 4.2)), animated: false)
        let onLine = view.convert(WebMercator.coordinate(p(150_000, 260_000)), toPointTo: view)
        coordinator.handle(point: onLine, in: view, place: false)
        #expect(selected.last == "River")
        selected.removeAll()
        coordinator.handle(point: CGPoint(x: onLine.x + 80, y: onLine.y), in: view, place: false)
        #expect(selected == [nil])
    }
}
#endif
