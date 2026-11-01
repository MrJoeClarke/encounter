//
//  MapKitCanvas.swift
//  encounter
//

import SwiftUI
import MapKit
import SwiftData
#if os(macOS)
import AppKit
typealias PlatformViewRepresentable = NSViewRepresentable
#else
import UIKit
typealias PlatformViewRepresentable = UIViewRepresentable
#endif

/// A numbered mark drawn on the map at an image position, such as a calibration point.
struct MapMarker: Identifiable {
    let id: Int
    let pixelX: Double
    let pixelY: Double
    let label: String
}

/// A place drawn on the map at its position in the image.
struct PlacePin: Identifiable {
    let page: Page
    let pixelX: Double
    let pixelY: Double
    /// Whether it can be dragged. A place with an outline is drawn at the middle of it, and moving that would
    /// lose the outline, so it is redrawn instead.
    var isMovable = true
    var id: UUID { page.id }
}

/// A place outline drawn on the map.
struct PlaceShape: Identifiable {
    let page: Page
    let corners: [GridPoint]
    var id: UUID { page.id }
}

/// Shows a map with MapKit. The image is cut into tiles that replace the base map, places are annotations that
/// cluster when they crowd, outlines are polygons, and zooming, panning and scrolling come from MapKit. Positions
/// are given and reported in pixels of the full image, and turned into the world's plane through the calibration.
struct MapKitCanvas: PlatformViewRepresentable {
    let map: WorldMap
    var markers: [MapMarker] = []
    var pins: [PlacePin] = []
    var shapes: [PlaceShape] = []
    /// The corners of an outline being drawn, in image pixels.
    var draftCorners: [CGPoint] = []
    /// A character's journey as a line through these image positions, in order.
    var route: [CGPoint] = []
    /// Whether a click on the map is wanted as a point (a calibration point or the corner of an outline), rather
    /// than selecting a place.
    var isMarking = false
    var canPlace = false
    /// Whether a scene map's grid of squares is drawn.
    var showsGrid = true
    var onTap: ((_ pixelX: Double, _ pixelY: Double) -> Void)?
    var onPlace: ((_ pixelX: Double, _ pixelY: Double) -> Void)?
    var onMove: ((_ page: Page, _ pixelX: Double, _ pixelY: Double) -> Void)?
    var onSelect: ((_ page: Page?) -> Void)?

    // MARK: The map as MapKit shows it

    /// How the image lines up with the plane. An uncalibrated map is shown at a made-up scale, so it can be
    /// looked at and marked for calibration.
    var displayCalibration: MapCalibration {
        map.calibration ?? MapCalibration(
            anchoringPixel: (0, Double(max(map.pixelHeight, 1))), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 100
        ) ?? MapCalibration(originEasting: 0, originNorthing: 0, metresPerPixel: 100)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    #if os(macOS)
    func makeNSView(context: Context) -> MKMapView { makeMapView(context) }
    func updateNSView(_ view: MKMapView, context: Context) { update(view, context) }
    #else
    func makeUIView(context: Context) -> MKMapView { makeMapView(context) }
    func updateUIView(_ view: MKMapView, context: Context) { update(view, context) }
    #endif

    private func makeMapView(_ context: Context) -> MKMapView {
        #if os(macOS)
        let view = PlacingMapView()
        #else
        let view = MKMapView()
        #endif
        let coordinator = context.coordinator
        view.delegate = coordinator
        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        view.preferredConfiguration = configuration
        view.isRotateEnabled = false
        view.isPitchEnabled = false
        view.showsCompass = false
        #if os(macOS)
        view.showsZoomControls = true
        // A right-click (or control-click) opens a menu, which is where a place is added.
        view.onPlace = { [weak coordinator, weak view] point in
            guard let coordinator, let view else { return }
            coordinator.handle(point: point, in: view, place: true)
        }
        let leftClick = NSClickGestureRecognizer(target: coordinator, action: #selector(Coordinator.clicked(_:)))
        leftClick.delegate = coordinator
        view.addGestureRecognizer(leftClick)
        #else
        let press = UILongPressGestureRecognizer(target: coordinator, action: #selector(Coordinator.pressed(_:)))
        press.delegate = coordinator
        let tap = UITapGestureRecognizer(target: coordinator, action: #selector(Coordinator.clicked(_:)))
        tap.delegate = coordinator
        view.addGestureRecognizer(press)
        view.addGestureRecognizer(tap)
        #endif
        return view
    }

    private func update(_ view: MKMapView, _ context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self
        let calibration = displayCalibration
        coordinator.calibration = calibration

        // The tiles are rebuilt when the map or its calibration changes.
        let key = "\(map.id)|\(map.pixelWidth)x\(map.pixelHeight)|\(calibration.originEasting),\(calibration.originNorthing),\(calibration.metresPerPixel),\(calibration.rotation)"
        if coordinator.tileKey != key, let data = map.imageData, map.pixelWidth > 0 {
            if let old = coordinator.overlay { view.removeOverlay(old) }
            let source = MapTileSource(imageData: data, pixelWidth: map.pixelWidth, pixelHeight: map.pixelHeight, calibration: calibration)
            let overlay = MapTileOverlay(source: source)
            view.insertOverlay(overlay, at: 0, level: .aboveLabels)
            coordinator.overlay = overlay
            if coordinator.mapID != map.id { coordinator.show(source, in: view) }
            coordinator.mapID = map.id
            coordinator.tileKey = key
        }

        #if os(macOS)
        (view as? PlacingMapView)?.canPlace = canPlace
        #endif
        coordinator.sync(markers: markers, pins: pins, shapes: shapes, draft: draftCorners, route: route, grid: showsGrid ? sceneGrid : nil, in: view)
    }

    /// The grid of squares to draw, for a scene map that has one.
    private var sceneGrid: SceneGridOverlay? {
        guard map.kind == .scene, map.isCalibrated, map.gridColumns > 0, map.gridRows > 0 else { return nil }
        return SceneGridOverlay(
            calibration: displayCalibration, pixelWidth: map.pixelWidth, pixelHeight: map.pixelHeight,
            columns: map.gridColumns, rows: map.gridRows
        )
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: MapKitCanvas?
        var calibration = MapCalibration(originEasting: 0, originNorthing: 0, metresPerPixel: 1)
        var overlay: MapTileOverlay?
        var tileKey = ""
        var mapID: UUID?
        private var pinAnnotations: [UUID: PlaceAnnotation] = [:]
        private var markAnnotations: [MarkAnnotation] = []
        private var shapeOverlays: [UUID: PlaceOverlay] = [:]
        private var isDragging = false

        /// Fits the whole map in view and keeps the camera near it.
        func show(_ source: MapTileSource, in view: MKMapView) {
            let b = source.bounds
            let southWest = WebMercator.coordinate(easting: b.minEasting, northing: b.minNorthing)
            let northEast = WebMercator.coordinate(easting: b.maxEasting, northing: b.maxNorthing)
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (southWest.latitude + northEast.latitude) / 2, longitude: (southWest.longitude + northEast.longitude) / 2),
                span: MKCoordinateSpan(latitudeDelta: (northEast.latitude - southWest.latitude) * 1.05, longitudeDelta: (northEast.longitude - southWest.longitude) * 1.05)
            )
            view.setRegion(region, animated: false)
            let wide = MKCoordinateRegion(
                center: region.center,
                span: MKCoordinateSpan(latitudeDelta: region.span.latitudeDelta * 2, longitudeDelta: region.span.longitudeDelta * 2)
            )
            view.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: wide), animated: false)
            let diagonal = hypot(b.maxEasting - b.minEasting, b.maxNorthing - b.minNorthing)
            view.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: max(diagonal / 5000, 2), maxCenterCoordinateDistance: diagonal * 3), animated: false)
        }

        private var gridOverlay: SceneGridOverlay?

        private var draftOverlay: DraftOutline?
        private var draftCorners: [CGPoint] = []
        private var journeyOverlay: JourneyLine?
        private var journeyRoute: [CGPoint] = []

        func sync(markers: [MapMarker], pins: [PlacePin], shapes: [PlaceShape], draft: [CGPoint], route: [CGPoint], grid: SceneGridOverlay?, in view: MKMapView) {
            // The outline being drawn is replaced as corners are added.
            if draft != draftCorners {
                draftCorners = draft
                if let draftOverlay { view.removeOverlay(draftOverlay) }
                draftOverlay = nil
                if draft.count >= 2 {
                    // Closed up once it could be a shape, so it shows what finishing it would give.
                    let path = (draft + (draft.count >= 3 ? [draft[0]] : [])).map {
                        WebMercator.coordinate(calibration.gridPoint(atX: $0.x, y: $0.y))
                    }
                    let overlay = DraftOutline(coordinates: path, count: path.count)
                    draftOverlay = overlay
                    view.addOverlay(overlay, level: .aboveLabels)
                }
            }

            // A character's journey is replaced when it changes.
            if route != journeyRoute {
                journeyRoute = route
                if let journeyOverlay { view.removeOverlay(journeyOverlay) }
                journeyOverlay = nil
                if route.count >= 2 {
                    let path = route.map { WebMercator.coordinate(calibration.gridPoint(atX: $0.x, y: $0.y)) }
                    let line = JourneyLine(coordinates: path, count: path.count)
                    journeyOverlay = line
                    view.addOverlay(line, level: .aboveLabels)
                }
            }

            // The grid is replaced when it changes, and sits above the map but below outlines and pins.
            let unchanged = gridOverlay.map { old in grid.map(old.matches) ?? false } ?? (grid == nil)
            if !unchanged {
                if let gridOverlay { view.removeOverlay(gridOverlay) }
                gridOverlay = grid
                if let grid { view.insertOverlay(grid, above: overlay ?? grid) }
            }

            // Places. A pin being dragged is left alone.
            if !isDragging {
                let wanted = Dictionary(uniqueKeysWithValues: pins.map { ($0.id, $0) })
                for (id, annotation) in pinAnnotations where wanted[id] == nil {
                    view.removeAnnotation(annotation)
                    pinAnnotations[id] = nil
                }
                for pin in pins {
                    let point = calibration.gridPoint(atX: pin.pixelX, y: pin.pixelY)
                    let coordinate = WebMercator.coordinate(point)
                    if let annotation = pinAnnotations[pin.id] {
                        annotation.title = pin.page.title
                        annotation.isMovable = pin.isMovable
                        view.view(for: annotation)?.isDraggable = pin.isMovable
                        if annotation.coordinate.latitude != coordinate.latitude || annotation.coordinate.longitude != coordinate.longitude {
                            annotation.coordinate = coordinate
                        }
                    } else {
                        let annotation = PlaceAnnotation(page: pin.page, coordinate: coordinate)
                        annotation.isMovable = pin.isMovable
                        pinAnnotations[pin.id] = annotation
                        view.addAnnotation(annotation)
                    }
                }
            }

            // Calibration marks are replaced each time, since there are at most two.
            view.removeAnnotations(markAnnotations)
            markAnnotations = markers.map { marker in
                MarkAnnotation(label: marker.label, coordinate: WebMercator.coordinate(calibration.gridPoint(atX: marker.pixelX, y: marker.pixelY)))
            }
            view.addAnnotations(markAnnotations)

            // Outlines are replaced when they change.
            let wanted = Dictionary(uniqueKeysWithValues: shapes.map { ($0.id, $0) })
            for (id, overlay) in shapeOverlays where wanted[id] == nil || overlay.corners != wanted[id]?.corners {
                view.removeOverlay(overlay)
                shapeOverlays[id] = nil
            }
            for shape in shapes where shapeOverlays[shape.id] == nil {
                let overlay = PlaceOverlay(page: shape.page, corners: shape.corners)
                shapeOverlays[shape.id] = overlay
                view.addOverlay(overlay, level: .aboveLabels)
            }
        }

        // MARK: Positions

        private func pixel(for coordinate: CLLocationCoordinate2D) -> (x: Double, y: Double) {
            calibration.pixel(at: WebMercator.point(coordinate))
        }

        // MARK: Delegate

        func mapView(_ mapView: MKMapView, rendererFor overlay: any MKOverlay) -> MKOverlayRenderer {
            if let tiles = overlay as? MKTileOverlay { return MKTileOverlayRenderer(tileOverlay: tiles) }
            if let grid = overlay as? SceneGridOverlay { return SceneGridRenderer(grid: grid) }
            if overlay is JourneyLine {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = PlatformColor.systemPurple
                renderer.lineWidth = 3
                renderer.lineJoin = .round
                renderer.lineCap = .round
                return renderer
            }
            if overlay is DraftOutline {
                let renderer = MKPolylineRenderer(overlay: overlay)
                renderer.strokeColor = PlatformColor.systemBlue
                renderer.lineWidth = 2.5
                renderer.lineDashPattern = [6, 4]
                return renderer
            }
            if let shape = overlay as? PlaceOverlay {
                let renderer = MKPolygonRenderer(polygon: shape)
                renderer.fillColor = PlatformColor.systemRed.withAlphaComponent(0.18)
                renderer.strokeColor = PlatformColor.systemRed
                renderer.lineWidth = 2
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let place = annotation as? PlaceAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "place") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: place, reuseIdentifier: "place")
                view.annotation = place
                view.clusteringIdentifier = "place"
                view.markerTintColor = .systemRed
                view.glyphImage = Self.symbol(place.page.kind.systemImage)
                view.canShowCallout = true
                view.isDraggable = place.isMovable
                view.titleVisibility = .adaptive
                return view
            }
            if let mark = annotation as? MarkAnnotation {
                let view = (mapView.dequeueReusableAnnotationView(withIdentifier: "mark") as? MKMarkerAnnotationView)
                    ?? MKMarkerAnnotationView(annotation: mark, reuseIdentifier: "mark")
                view.annotation = mark
                view.markerTintColor = .systemBlue
                view.glyphText = mark.label
                view.displayPriority = .required
                view.canShowCallout = false
                return view
            }
            return nil   // clusters use the default look
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            if let place = view.annotation as? PlaceAnnotation { parent?.onSelect?(place.page) }
        }

        func mapView(_ mapView: MKMapView, didDeselect view: MKAnnotationView) {
            if view.annotation is PlaceAnnotation { parent?.onSelect?(nil) }
        }

        func mapView(_ mapView: MKMapView, annotationView view: MKAnnotationView, didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            switch newState {
            case .starting, .dragging:
                isDragging = true
            case .ending, .canceling:
                isDragging = false
                view.dragState = .none
                if newState == .ending, let place = view.annotation as? PlaceAnnotation {
                    let p = pixel(for: place.coordinate)
                    parent?.onMove?(place.page, p.x, p.y)
                }
            default:
                break
            }
        }

        // MARK: Clicks

        func handle(point: CGPoint, in view: MKMapView, place: Bool) {
            let coordinate = view.convert(point, toCoordinateFrom: view)
            let p = pixel(for: coordinate)
            if place {
                parent?.onPlace?(p.x, p.y)
            } else if parent?.isMarking == true {
                parent?.onTap?(p.x, p.y)
            } else if let hit = outline(at: WebMercator.point(coordinate)) {
                parent?.onSelect?(hit)
            } else if view.selectedAnnotations.isEmpty {
                parent?.onSelect?(nil)
            }
        }

        /// The place whose outline holds a position, the smallest if several do.
        private func outline(at point: GridPoint) -> Page? {
            (parent?.shapes ?? [])
                .filter { PlaceGeometry.polygon($0.corners).contains(point) }
                .min { PlaceGeometry.polygon($0.corners).area < PlaceGeometry.polygon($1.corners).area }?
                .page
        }

        #if os(macOS)
        @objc func clicked(_ recognizer: NSClickGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view as? MKMapView else { return }
            handle(point: recognizer.location(in: view), in: view, place: false)
        }
        #else
        @objc func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began, parent?.canPlace == true, let view = recognizer.view as? MKMapView else { return }
            handle(point: recognizer.location(in: view), in: view, place: true)
        }

        @objc func clicked(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, let view = recognizer.view as? MKMapView else { return }
            handle(point: recognizer.location(in: view), in: view, place: false)
        }
        #endif

        private static func symbol(_ name: String) -> PlatformImage? {
            #if os(macOS)
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
            #else
            UIImage(systemName: name)
            #endif
        }
    }
}

#if os(macOS)
typealias PlatformColor = NSColor
typealias PlatformImage = NSImage
extension MapKitCanvas.Coordinator: NSGestureRecognizerDelegate {
    // MapKit has recognizers of its own, which have to keep working beside these.
    nonisolated func gestureRecognizer(_ gestureRecognizer: NSGestureRecognizer, shouldRecognizeSimultaneouslyWith other: NSGestureRecognizer) -> Bool { true }
}
#else
typealias PlatformColor = UIColor
typealias PlatformImage = UIImage
extension MapKitCanvas.Coordinator: UIGestureRecognizerDelegate {
    nonisolated func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
}
#endif

/// A place pin on the MapKit map.
final class PlaceAnnotation: NSObject, MKAnnotation {
    let page: Page
    @objc dynamic var coordinate: CLLocationCoordinate2D
    var title: String?
    var isMovable = true

    init(page: Page, coordinate: CLLocationCoordinate2D) {
        self.page = page
        self.coordinate = coordinate
        self.title = page.title
    }
}

/// A numbered calibration mark on the MapKit map.
final class MarkAnnotation: NSObject, MKAnnotation {
    let label: String
    let coordinate: CLLocationCoordinate2D
    var title: String? { nil }

    init(label: String, coordinate: CLLocationCoordinate2D) {
        self.label = label
        self.coordinate = coordinate
    }
}

/// A place outline on the MapKit map.
final class PlaceOverlay: MKPolygon {
    private(set) var page: Page!
    private(set) var corners: [GridPoint] = []

    convenience init(page: Page, corners: [GridPoint]) {
        var coordinates = corners.map(WebMercator.coordinate)
        self.init(coordinates: &coordinates, count: coordinates.count)
        self.page = page
        self.corners = corners
    }
}

#Preview("MapKit canvas") {
    let container = SampleData.makePreviewContainer()
    let context = container.mainContext
    let world = (try? context.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    let map = WorldMap(name: "Sword Coast", imageData: SampleData.solidImage(width: 1500, height: 900, red: 0.35, green: 0.5, blue: 0.4))
    map.pixelWidth = 1500
    map.pixelHeight = 900
    context.insert(map)
    map.world = world
    map.place = world?.rootPlace
    map.calibration = MapCalibration(pixelA: (0, 0), pixelB: (1500, 0), distanceMetres: 600_000, imageHeight: 900)
    var pins: [PlacePin] = []
    for (title, x, y) in [("Brackwater", 400.0, 300.0), ("Mistfen", 900.0, 600.0), ("Saltpan", 420.0, 310.0), ("Gull Rock", 405.0, 295.0)] {
        let page = Page(title: title, kind: .place)
        context.insert(page)
        page.world = world
        map.position(page, atPixelX: x, y: y)
        pins.append(PlacePin(page: page, pixelX: x, pixelY: y))
    }
    let coast = Page(title: "Coast", kind: .place)
    context.insert(coast)
    coast.world = world
    let shape = PlaceShape(page: coast, corners: [GridPoint(easting: 150_000, northing: 100_000), GridPoint(easting: 350_000, northing: 100_000), GridPoint(easting: 350_000, northing: 250_000), GridPoint(easting: 150_000, northing: 250_000)])
    return MapKitCanvas(map: map, pins: pins, shapes: [shape])
        .environment(WorldNavigation())
        .frame(width: 800, height: 520)
        .modelContainer(container)
}

#if os(macOS)
/// A map view that offers "Add Place Here…" when it is right-clicked, remembering where the click was.
final class PlacingMapView: MKMapView {
    var canPlace = false
    var onPlace: ((CGPoint) -> Void)?

    override func menu(for event: NSEvent) -> NSMenu? {
        guard canPlace else { return super.menu(for: event) }
        let menu = NSMenu()
        let item = NSMenuItem(title: String(localized: "Add Place Here…"), action: #selector(addPlaceHere(_:)), keyEquivalent: "")
        item.target = self
        item.image = NSImage(systemSymbolName: "mappin.and.ellipse", accessibilityDescription: nil)
        item.representedObject = NSValue(point: convert(event.locationInWindow, from: nil))
        menu.addItem(item)
        return menu
    }

    @objc private func addPlaceHere(_ item: NSMenuItem) {
        guard let point = (item.representedObject as? NSValue)?.pointValue else { return }
        onPlace?(point)
    }
}
#endif

/// The grid of squares on a scene map, which MapKit draws over the map.
final class SceneGridOverlay: NSObject, MKOverlay {
    let calibration: MapCalibration
    let pixelWidth: Int
    let pixelHeight: Int
    let columns: Int
    let rows: Int
    let coordinate: CLLocationCoordinate2D
    let boundingMapRect: MKMapRect

    init(calibration: MapCalibration, pixelWidth: Int, pixelHeight: Int, columns: Int, rows: Int) {
        self.calibration = calibration
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.columns = columns
        self.rows = rows
        let corners = [(0.0, 0.0), (Double(pixelWidth), 0), (0, Double(pixelHeight)), (Double(pixelWidth), Double(pixelHeight))]
            .map { MKMapPoint(WebMercator.coordinate(calibration.gridPoint(atX: $0.0, y: $0.1))) }
        let minX = corners.map(\.x).min() ?? 0, maxX = corners.map(\.x).max() ?? 0
        let minY = corners.map(\.y).min() ?? 0, maxY = corners.map(\.y).max() ?? 0
        boundingMapRect = MKMapRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        coordinate = MKMapPoint(x: (minX + maxX) / 2, y: (minY + maxY) / 2).coordinate
    }

    /// The same grid on the same map, so MapKit needn't redraw it.
    func matches(_ other: SceneGridOverlay) -> Bool {
        calibration == other.calibration && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
            && columns == other.columns && rows == other.rows
    }
}

final class SceneGridRenderer: MKOverlayRenderer {
    private let grid: SceneGridOverlay

    init(grid: SceneGridOverlay) {
        self.grid = grid
        super.init(overlay: grid)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        func mapPoint(_ x: Double, _ y: Double) -> CGPoint {
            point(for: MKMapPoint(WebMercator.coordinate(grid.calibration.gridPoint(atX: x, y: y))))
        }
        let width = Double(grid.pixelWidth), height = Double(grid.pixelHeight)
        context.setLineWidth(1 / zoomScale)
        context.setStrokeColor(CGColor(gray: 1, alpha: 0.5))
        for column in 0...grid.columns {
            let x = width * Double(column) / Double(grid.columns)
            context.move(to: mapPoint(x, 0))
            context.addLine(to: mapPoint(x, height))
        }
        for row in 0...grid.rows {
            let y = height * Double(row) / Double(grid.rows)
            context.move(to: mapPoint(0, y))
            context.addLine(to: mapPoint(width, y))
        }
        context.strokePath()
    }
}

/// The outline being drawn on the MapKit map, as a dashed line.
final class DraftOutline: MKPolyline {}

/// The line a character's journey draws on the map.
final class JourneyLine: MKPolyline {}
