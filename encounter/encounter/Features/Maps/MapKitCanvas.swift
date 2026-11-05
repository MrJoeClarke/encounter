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

/// A place drawn as a line on the map: a road or a river.
struct PlaceLine: Identifiable {
    let page: Page
    let points: [GridPoint]
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
    var lines: [PlaceLine] = []
    /// The corners of an outline being drawn, in image pixels.
    var draftCorners: [CGPoint] = []
    /// Whether the draft is a line, which is left open, rather than an outline, which is closed.
    var draftIsLine = false
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
        let key = "\(map.id)|\(map.pixelWidth)x\(map.pixelHeight)|\(calibration.originEasting),\(calibration.originNorthing),\(calibration.metresPerPixel),\(calibration.rotation)|\(map.style.id)"
        if coordinator.tileKey != key, let data = map.imageData ?? (map.isVector ? Data() : nil), map.pixelWidth > 0 {
            if let old = coordinator.overlay { view.removeOverlay(old) }
            let source = MapTileSource(imageData: data, pixelWidth: map.pixelWidth, pixelHeight: map.pixelHeight, calibration: calibration)
            // What the map is drawn on comes from its style.
            let ground = map.style.background
            source.background = CGColor(red: ground.red, green: ground.green, blue: ground.blue, alpha: ground.alpha)
            source.paper = map.style.paper
            if map.isVector {
                let around = map.style.surround
                source.surround = CGColor(red: around.red, green: around.green, blue: around.blue, alpha: around.alpha)
            }
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
        coordinator.syncFrame(in: view)
        coordinator.sync(markers: markers, pins: pins, shapes: shapes, draft: draftCorners, draftIsLine: draftIsLine, route: route, lines: lines, grid: showsGrid ? sceneGrid : nil, in: view)
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
        /// The style the shapes and lines were last drawn in, so they are drawn again when it changes.
        var drawnStyleID = ""
        var mapID: UUID?
        private var pinAnnotations: [UUID: PlaceAnnotation] = [:]
        private var markAnnotations: [MarkAnnotation] = []
        private var shapeOverlays: [UUID: PlaceOverlay] = [:]
        private var lineOverlays: [UUID: PlaceLineOverlay] = [:]
        private var isDragging = false
        /// The ruled border round the sheet, and the sheet's own place in MapKit's points.
        private var frameOverlay: SheetFrameOverlay?
        private var frameKey = ""
        private var sheetRect = MKMapRect.null
        /// The pins and names that are on the map now; the rest are held back until the view is close enough.
        private var shown = Set<ObjectIdentifier>()
        /// How wide the whole map is, in MapKit's points, and so how much of it is in view.
        private var mapWidth = 0.0
        private var mapHeight = 0.0
        private var isLeavingTheMap = false
        private var viewShare = 1.0

        /// Draws the ruled border of the style round the sheet, or takes it away, when the style or the map changes.
        func syncFrame(in view: MKMapView) {
            let style = parent?.map.style ?? .dark
            let wanted = (parent?.map.isVector ?? false) ? style.frame : nil
            let key = wanted == nil ? "" : "\(style.id)|\(mapID?.uuidString ?? "")"
            guard key != frameKey else { return }
            frameKey = key
            if let frameOverlay { view.removeOverlay(frameOverlay) }
            frameOverlay = nil
            if let wanted, !sheetRect.isNull {
                let overlay = SheetFrameOverlay(sheet: sheetRect, frame: wanted)
                view.addOverlay(overlay, level: .aboveLabels)
                frameOverlay = overlay
            }
        }

        /// Puts the pin or name on the map if the view is close enough for it, and takes it off if not.
        private func present<A: MKAnnotation & AnyObject>(_ annotation: A, maxView: Double, fits: Bool = true, in view: MKMapView) {
            let id = ObjectIdentifier(annotation)
            if maxView >= effectiveView && fits {
                if shown.insert(id).inserted { view.addAnnotation(annotation) }
            } else if shown.remove(id) != nil {
                view.removeAnnotation(annotation)
            }
        }

        private func drop<A: MKAnnotation & AnyObject>(_ annotation: A, from view: MKMapView) {
            if shown.remove(ObjectIdentifier(annotation)) != nil { view.removeAnnotation(annotation) }
        }

        private var effectiveView: Double { ZoomRules.view(share: viewShare, on: parent?.map.kind ?? .world) }

        /// Shows the pins and names the zoom allows, as the view moves in and out.
        func applyZoom(in view: MKMapView) {
            if mapWidth > 0 { viewShare = min(view.visibleMapRect.width / mapWidth, 1) }   // further out than the whole map is still the whole map
            for annotation in pinAnnotations.values { present(annotation, maxView: annotation.maxView, in: view) }
            // The name of an area needs room across it: where the area is too small on screen to hold its name, it is left out.
            let pointsPerMapPoint = view.visibleMapRect.width > 0 ? Double(view.bounds.width) / view.visibleMapRect.width : 0
            for annotation in labelAnnotations {
                let fits = annotation.extent <= 0 || annotation.extent * pointsPerMapPoint >= annotation.textWidth
                present(annotation, maxView: annotation.maxView, fits: fits, in: view)
            }
        }

        /// The deepest zoom the tiles go to. Past it MapKit stops drawing the map and shows the world beneath, so the
        /// camera is held to it.
        private var deepestZoom = 21.0

        /// Fits the whole map in view and keeps the camera near it.
        func show(_ source: MapTileSource, in view: MKMapView) {
            deepestZoom = Double(source.maximumDisplayZoom)
            let b = source.bounds
            let southWest = WebMercator.coordinate(easting: b.minEasting, northing: b.minNorthing)
            let northEast = WebMercator.coordinate(easting: b.maxEasting, northing: b.maxNorthing)
            mapWidth = abs(MKMapPoint(northEast).x - MKMapPoint(southWest).x)
            let corner = MKMapPoint(southWest), far = MKMapPoint(northEast)
            sheetRect = MKMapRect(x: min(corner.x, far.x), y: min(corner.y, far.y), width: abs(far.x - corner.x), height: abs(far.y - corner.y))
            let region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: (southWest.latitude + northEast.latitude) / 2, longitude: (southWest.longitude + northEast.longitude) / 2),
                span: MKCoordinateSpan(latitudeDelta: (northEast.latitude - southWest.latitude) * 1.05, longitudeDelta: (northEast.longitude - southWest.longitude) * 1.05)
            )
            view.setRegion(region, animated: false)
            // The map is the sheet: the centre can't leave it, and the view can't go out much past the whole of it.
            view.setCameraBoundary(MKMapView.CameraBoundary(coordinateRegion: region), animated: false)
            let diagonal = hypot(b.maxEasting - b.minEasting, b.maxNorthing - b.minNorthing)
            view.setCameraZoomRange(MKMapView.CameraZoomRange(minCenterCoordinateDistance: max(diagonal / 5000, 2), maxCenterCoordinateDistance: diagonal * 3), animated: false)
            mapHeight = abs(MKMapPoint(northEast).y - MKMapPoint(southWest).y)
        }

        private var gridOverlay: SceneGridOverlay?

        private var draftOverlay: DraftOutline?
        private var draftIsLine = false
        private var draftCorners: [CGPoint] = []
        private var journeyOverlay: JourneyLine?
        private var journeyRoute: [CGPoint] = []

        /// The names on the map: across areas, along lines and under pins.
        private var labelAnnotations: [PlaceLabelAnnotation] = []
        private var drawnLabelKey = ""

        /// Names the places that are named on the map, again whenever one of them, or the style, changes.
        private func syncLabels(in view: MKMapView, pins: [PlacePin], shapes: [PlaceShape], lines: [PlaceLine]) {
            let styleID = parent?.map.style.id ?? ""
            var key = styleID
            for shape in shapes { key += "|\(shape.id)\(shape.page.title)\(shape.page.attributeText("core.placeType"))\(shape.corners.count)" }
            for line in lines { key += "|\(line.id)\(line.page.title)\(line.page.attributeText("core.placeType"))\(line.points.count)" }
            for pin in pins { key += "|\(pin.id)\(pin.page.title)\(PlacePinKind.of(pin.page)?.rawValue ?? "")" }
            guard key != drawnLabelKey else { return }
            drawnLabelKey = key
            for old in labelAnnotations { drop(old, from: view) }
            let zoom = (parent?.map.style ?? .dark).zoom
            let pinSpots = pins.map { calibration.gridPoint(atX: $0.pixelX, y: $0.pixelY) }
            var made: [PlaceLabelAnnotation] = []
            for shape in shapes where !shape.page.title.isEmpty {
                let type = shape.page.attributeText("core.placeType")
                guard PlaceLabelKind.of(type: type) == .area else { continue }
                // Well inside the area and away from its pins; the sea's name goes out on the open water and not where the land is.
                let spot: GridPoint
                if type == "Water" {
                    let land = shapes.filter { $0.page.attributeText("core.placeType") == "Region" }.map(\.corners)
                    let low = GridPoint(easting: shape.corners.map(\.easting).min() ?? 0, northing: shape.corners.map(\.northing).min() ?? 0)
                    let high = GridPoint(easting: shape.corners.map(\.easting).max() ?? 0, northing: shape.corners.map(\.northing).max() ?? 0)
                    spot = LabelSpot.openWater(from: low, to: high, land: land)
                } else {
                    spot = LabelSpot.inside(shape.corners, avoiding: pinSpots)
                }
                let label = PlaceLabelAnnotation(
                    text: shape.page.title, type: type, coordinate: WebMercator.coordinate(spot), angle: 0, priority: PlaceLabelKind.priority(type: type)
                )
                label.maxView = zoom.name(ofType: type)
                // A realm or sea is always named and never moved aside by anything else, so the realms are the first names to appear.
                label.ignoresCollisions = type == "Region" || type == "Water"
                if !label.ignoresCollisions {
                    let xs = shape.corners.map { MKMapPoint(WebMercator.coordinate($0)).x }
                    label.extent = (xs.max() ?? 0) - (xs.min() ?? 0)
                }
                label.textWidth = Double(MapGlyphs.label(shape.page.title, type: type, style: parent?.map.style ?? .dark)?.size.width ?? 0)
                made.append(label)
            }
            for line in lines where !line.page.title.isEmpty && line.points.count >= 2 {
                let type = line.page.attributeText("core.placeType")
                guard PlaceLabelKind.of(type: type) == .line, let spot = Self.alongLine(line.points) else { continue }
                let label = PlaceLabelAnnotation(
                    text: line.page.title, type: type, coordinate: WebMercator.coordinate(spot.point), angle: spot.degrees, priority: PlaceLabelKind.priority(type: type)
                )
                label.maxView = zoom.name(ofType: type)
                made.append(label)
            }
            for pin in pins where !pin.page.title.isEmpty {
                guard let kind = PlacePinKind.of(pin.page) else { continue }
                let point = calibration.gridPoint(atX: pin.pixelX, y: pin.pixelY)
                let label = PlaceLabelAnnotation(
                    text: pin.page.title, type: kind == .capital ? "PinCapital" : "Pin", coordinate: WebMercator.coordinate(point), angle: 0, priority: kind.priority - 50
                )
                label.offset = CGPoint(x: 0, y: kind.size / 2 + 9)
                label.maxView = zoom.pinName(kind)
                made.append(label)
            }
            labelAnnotations = made
            for label in made { present(label, maxView: label.maxView, in: view) }
        }

        /// The middle of a line, by its length, and the angle of the text along it, in degrees anticlockwise from east, turned so
        /// that it never reads upside down.
        static func alongLine(_ points: [GridPoint]) -> (point: GridPoint, degrees: Double)? {
            let lengths = zip(points, points.dropFirst()).map { $0.0.distance(to: $0.1) }
            let total = lengths.reduce(0, +)
            guard total > 0 else { return nil }
            var remaining = total / 2
            for (index, length) in lengths.enumerated() {
                if remaining <= length || index == lengths.count - 1 {
                    let a = points[index], b = points[index + 1]
                    let t = length > 0 ? min(remaining / length, 1) : 0
                    var degrees = atan2(b.northing - a.northing, b.easting - a.easting) * 180 / .pi
                    if degrees > 90 { degrees -= 180 } else if degrees <= -90 { degrees += 180 }
                    return (GridPoint(easting: a.easting + (b.easting - a.easting) * t, northing: a.northing + (b.northing - a.northing) * t), degrees)
                }
                remaining -= length
            }
            return nil
        }

        func sync(markers: [MapMarker], pins: [PlacePin], shapes: [PlaceShape], draft: [CGPoint], draftIsLine: Bool, route: [CGPoint], lines: [PlaceLine], grid: SceneGridOverlay?, in view: MKMapView) {
            // The outline being drawn is replaced as corners are added.
            if draft != draftCorners || draftIsLine != self.draftIsLine {
                draftCorners = draft
                self.draftIsLine = draftIsLine
                if let draftOverlay { view.removeOverlay(draftOverlay) }
                draftOverlay = nil
                if draft.count >= 2 {
                    // Closed up once it could be a shape, so it shows what finishing it would give.
                    let path = (draft + (draft.count >= 3 && !draftIsLine ? [draft[0]] : [])).map {
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
                    drop(annotation, from: view)
                    pinAnnotations[id] = nil
                }
                for pin in pins {
                    let point = calibration.gridPoint(atX: pin.pixelX, y: pin.pixelY)
                    let coordinate = WebMercator.coordinate(point)
                    let kind = PlacePinKind.of(pin.page) ?? .place
                    let styleID = parent?.map.style.id ?? ""
                    // A pin whose kind or style has changed is made again, with the right picture.
                    if let annotation = pinAnnotations[pin.id], annotation.kind != kind || annotation.styleID != styleID {
                        drop(annotation, from: view)
                        pinAnnotations[pin.id] = nil
                    }
                    if let annotation = pinAnnotations[pin.id] {
                        annotation.title = pin.page.title
                        annotation.isMovable = pin.isMovable
                        view.view(for: annotation)?.isDraggable = pin.isMovable
                        if annotation.coordinate.latitude != coordinate.latitude || annotation.coordinate.longitude != coordinate.longitude {
                            annotation.coordinate = coordinate
                        }
                    } else {
                        let annotation = PlaceAnnotation(page: pin.page, coordinate: coordinate)
                        annotation.kind = kind
                        annotation.styleID = styleID
                        annotation.isMovable = pin.isMovable
                        annotation.maxView = (parent?.map.style ?? .dark).zoom.pin(kind)
                        pinAnnotations[pin.id] = annotation
                        present(annotation, maxView: annotation.maxView, in: view)
                    }
                }
            }

            syncLabels(in: view, pins: pins, shapes: shapes, lines: lines)
            applyZoom(in: view)

            // Calibration marks are replaced each time, since there are at most two.
            view.removeAnnotations(markAnnotations)
            markAnnotations = markers.map { marker in
                MarkAnnotation(label: marker.label, coordinate: WebMercator.coordinate(calibration.gridPoint(atX: marker.pixelX, y: marker.pixelY)))
            }
            view.addAnnotations(markAnnotations)

            // Outlines and lines are replaced when they change, and drawn from the bottom up: seas under settlements,
            // buildings above those, roads and rivers over all. Anything that changes redraws them all in that order.
            let wantedShapes = Dictionary(uniqueKeysWithValues: shapes.map { ($0.id, $0.corners) })
            let wantedLines = Dictionary(uniqueKeysWithValues: lines.map { ($0.id, $0.points) })
            let overlaysUnchanged = wantedShapes.count == shapeOverlays.count && wantedLines.count == lineOverlays.count
                && shapeOverlays.allSatisfy { wantedShapes[$0.key] == $0.value.corners && $0.value.styleType == $0.value.page.attributeText("core.placeType") }
                && lineOverlays.allSatisfy { wantedLines[$0.key] == $0.value.points && $0.value.styleType == $0.value.page.attributeText("core.placeType") }
                && drawnStyleID == (parent?.map.style.id ?? "")
            if !overlaysUnchanged {
                for overlay in shapeOverlays.values { view.removeOverlay(overlay) }
                for overlay in lineOverlays.values { view.removeOverlay(overlay) }
                shapeOverlays = [:]
                lineOverlays = [:]
                drawnStyleID = parent?.map.style.id ?? ""
                func order(_ page: Page) -> Int { PlaceStyle.style(forPlaceType: page.attributeText("core.placeType")).drawOrder }
                // Bigger areas go under smaller ones of the same kind.
                let sortedShapes = shapes.sorted { (order($0.page), -PlaceGeometry.polygon($0.corners).area) < (order($1.page), -PlaceGeometry.polygon($1.corners).area) }
                let sortedLines = lines.sorted { order($0.page) < order($1.page) }
                var layers: [(order: Int, add: () -> Void)] = []
                for shape in sortedShapes {
                    layers.append((order(shape.page), { [unowned self] in
                        // The sea is cut round the land, so the land is the ground itself and not sea under a faint tint.
                        let holes = shape.page.attributeText("core.placeType") == "Water"
                            ? shapes.filter { $0.page.attributeText("core.placeType") == "Region" }.map(\.corners) : []
                        let overlay = PlaceOverlay(page: shape.page, corners: shape.corners, holes: holes)
                        self.shapeOverlays[shape.id] = overlay
                        view.addOverlay(overlay, level: .aboveLabels)
                    }))
                }
                for line in sortedLines {
                    layers.append((order(line.page), { [unowned self] in
                        let overlay = PlaceLineOverlay(page: line.page, points: line.points)
                        self.lineOverlays[line.id] = overlay
                        view.addOverlay(overlay, level: .aboveLabels)
                    }))
                }
                for layer in layers.sorted(by: { $0.order < $1.order }) { layer.add() }
                // The draft and the journey stay on top of what they are drawn over.
                if let draftOverlay { view.removeOverlay(draftOverlay); view.addOverlay(draftOverlay, level: .aboveLabels) }
                if let journeyOverlay { view.removeOverlay(journeyOverlay); view.addOverlay(journeyOverlay, level: .aboveLabels) }
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
            if let frame = overlay as? SheetFrameOverlay { return SheetFrameRenderer(frame: frame) }
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
                let mapStyle = parent?.map.style ?? MapStyle.dark
                let type = shape.page.attributeText("core.placeType")
                let style = mapStyle.style(forPlaceType: type)
                if let hand = mapStyle.hand, MapStyle.HandDrawn.types.contains(type) {
                    return InkRenderer(
                        polygon: shape, fill: style.fill.map { PlatformColor(style: $0).cgColor }, stroke: PlatformColor(style: style.stroke).cgColor,
                        width: style.lineWidth, dash: style.isDashed ? (style.dashPattern ?? [6, 4]) : nil, hand: hand
                    )
                }
                let renderer = MKPolygonRenderer(polygon: shape)
                renderer.fillColor = style.fill.map(PlatformColor.init(style:))
                renderer.strokeColor = PlatformColor(style: style.stroke)
                renderer.lineWidth = style.lineWidth
                if style.isDashed { renderer.lineDashPattern = (style.dashPattern ?? [6, 4]).map { NSNumber(value: $0) } }
                return renderer
            }
            if let line = overlay as? PlaceLineOverlay {
                let mapStyle = parent?.map.style ?? MapStyle.dark
                let type = line.page.attributeText("core.placeType")
                let style = mapStyle.style(forPlaceType: type)
                if let hand = mapStyle.hand, MapStyle.HandDrawn.types.contains(type) {
                    return InkRenderer(
                        line: line, stroke: PlatformColor(style: style.stroke).cgColor, width: style.lineWidth,
                        dash: style.isDashed ? (style.dashPattern ?? [6, 4]) : nil, hand: hand
                    )
                }
                let renderer = MKPolylineRenderer(overlay: line)
                renderer.strokeColor = PlatformColor(style: style.stroke)
                renderer.lineWidth = style.lineWidth
                renderer.lineJoin = .round
                renderer.lineCap = .round
                if style.isDashed { renderer.lineDashPattern = (style.dashPattern ?? [6, 4]).map { NSNumber(value: $0) } }
                return renderer
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            if let place = annotation as? PlaceAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "place") ?? MKAnnotationView(annotation: place, reuseIdentifier: "place")
                view.annotation = place
                view.clusteringIdentifier = "place"
                // A small round pin with the icon of what it is, in the style's colours.
                view.image = MapGlyphs.pin(place.kind, style: MapStyle.style(id: place.styleID))
                view.canShowCallout = true
                view.isDraggable = place.isMovable
                view.displayPriority = MKFeatureDisplayPriority(rawValue: place.kind.priority)
                view.collisionMode = .circle
                return view
            }
            if let name = annotation as? PlaceLabelAnnotation {
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: "label") ?? MKAnnotationView(annotation: name, reuseIdentifier: "label")
                view.annotation = name
                let style = parent?.map.style ?? .dark
                view.image = MapGlyphs.label(name.text, type: name.type, style: style, degrees: name.angle)
                view.canShowCallout = false
                view.isEnabled = false
                view.centerOffset = name.offset
                view.displayPriority = MKFeatureDisplayPriority(rawValue: name.priority)
                view.collisionMode = name.ignoresCollisions ? .none : .rectangle
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

        /// Stops the camera going closer than the deepest tiles. The first time it does, the distance it was put back
        /// to becomes the closest the camera may be, so the gesture meets a limit rather than being pushed back.
        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            applyZoom(in: mapView)
            // Not out past the map: once the whole of it is in view with room to spare on every side, the camera is brought back in.
            if mapWidth > 0, mapHeight > 0, !isLeavingTheMap {
                let rect = mapView.visibleMapRect
                let spare = min(rect.width / mapWidth, rect.height / mapHeight)
                if spare > 1.2, let camera = mapView.camera.copy() as? MKMapCamera {
                    isLeavingTheMap = true
                    camera.centerCoordinateDistance /= spare / 1.15
                    mapView.setCamera(camera, animated: false)
                    isLeavingTheMap = false
                }
            }
            let width = Double(mapView.bounds.width)
            let delta = mapView.region.span.longitudeDelta
            guard width > 0, delta > 0 else { return }
            // MapKit's tiles are 256 points across, and a zoom level halves the longitude each tile covers.
            let zoom = log2(360 * width / (WebMercator.tileSize * delta))
            guard zoom > deepestZoom + 0.25 else { return }
            guard let camera = mapView.camera.copy() as? MKMapCamera else { return }
            camera.centerCoordinateDistance *= pow(2, zoom - deepestZoom)
            mapView.setCamera(camera, animated: false)
            mapView.setCameraZoomRange(
                MKMapView.CameraZoomRange(minCenterCoordinateDistance: camera.centerCoordinateDistance,
                                          maxCenterCoordinateDistance: mapView.cameraZoomRange.maxCenterCoordinateDistance),
                animated: false
            )
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
            } else if let hit = line(near: point, in: view) {
                parent?.onSelect?(hit)
            } else if let hit = outline(at: WebMercator.point(coordinate)) {
                parent?.onSelect?(hit)
            } else if view.selectedAnnotations.isEmpty {
                parent?.onSelect?(nil)
            }
        }

        /// The road or river a click is on or close to, the nearest if several are. The distance is in points on the
        /// screen, so a line can be picked at any zoom.
        private func line(near point: CGPoint, in view: MKMapView, within tolerance: CGFloat = 8) -> Page? {
            var best: (page: Page, distance: CGFloat)?
            for line in parent?.lines ?? [] {
                let screen = line.points.map { view.convert(WebMercator.coordinate($0), toPointTo: view) }
                for (a, b) in zip(screen, screen.dropFirst()) {
                    let dx = b.x - a.x, dy = b.y - a.y
                    let lengthSquared = dx * dx + dy * dy
                    let t = lengthSquared > 0 ? max(0, min(1, ((point.x - a.x) * dx + (point.y - a.y) * dy) / lengthSquared)) : 0
                    let distance = hypot(point.x - (a.x + t * dx), point.y - (a.y + t * dy))
                    if distance <= tolerance, distance < (best?.distance ?? .infinity) { best = (line.page, distance) }
                }
            }
            return best?.page
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
    /// What kind of pin it is, and the style it was drawn in, so it is drawn again when either changes.
    var kind = PlacePinKind.place
    var styleID = ""
    /// The most of the map that may be in view for the pin to show (see `ZoomRules`).
    var maxView = ZoomRules.always

    init(page: Page, coordinate: CLLocationCoordinate2D) {
        self.page = page
        self.coordinate = coordinate
        self.title = page.title
    }
}

/// A name on the MapKit map, across an area, along a line or under a pin. It has no pin of its own and can't be selected, and names
/// that crowd each other give way, the less important first.
final class PlaceLabelAnnotation: NSObject, MKAnnotation {
    let text: String
    let type: String
    let coordinate: CLLocationCoordinate2D
    /// In degrees anticlockwise from east.
    let angle: Double
    let priority: Float
    /// The most of the map that may be in view for the name to show (see `ZoomRules`).
    var maxView = ZoomRules.always
    /// For the name of an area, how wide the area is in MapKit's points, and how wide the name is on screen, in points. The name is
    /// shown only where the area is at least as wide as the name. Zero for any other name.
    var extent = 0.0
    /// Whether the name is drawn whatever is under it and without moving anything else aside.
    var ignoresCollisions = false
    var textWidth = 0.0
    /// How far from its coordinate it is drawn, in points, down and across.
    var offset = CGPoint.zero
    var title: String? { nil }

    init(text: String, type: String, coordinate: CLLocationCoordinate2D, angle: Double, priority: Float) {
        self.text = text
        self.type = type
        self.coordinate = coordinate
        self.angle = angle
        self.priority = priority
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

extension PlatformColor {
    convenience init(style color: StyleColor) {
        self.init(red: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

/// A road or river on the MapKit map.
final class PlaceLineOverlay: MKPolyline {
    private(set) var page: Page!
    private(set) var points: [GridPoint] = []
    /// The place type it was drawn for, so a change of type redraws it.
    private(set) var styleType = ""

    convenience init(page: Page, points: [GridPoint]) {
        var coordinates = points.map(WebMercator.coordinate)
        self.init(coordinates: &coordinates, count: coordinates.count)
        self.page = page
        self.points = points
        self.styleType = page.attributeText("core.placeType")
    }
}

/// A place outline on the MapKit map.
final class PlaceOverlay: MKPolygon {
    private(set) var page: Page!
    private(set) var corners: [GridPoint] = []
    private(set) var styleType = ""

    convenience init(page: Page, corners: [GridPoint], holes: [[GridPoint]] = []) {
        var coordinates = corners.map(WebMercator.coordinate)
        let inside = holes.map { hole -> MKPolygon in
            var points = hole.map(WebMercator.coordinate)
            return MKPolygon(coordinates: &points, count: points.count)
        }
        self.init(coordinates: &coordinates, count: coordinates.count, interiorPolygons: inside.isEmpty ? nil : inside)
        self.page = page
        self.corners = corners
        self.styleType = page.attributeText("core.placeType")
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
