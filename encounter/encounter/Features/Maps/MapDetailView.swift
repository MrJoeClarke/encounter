//
//  MapDetailView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// One map: its name and kind, the map itself with the places on it, and its calibration.
struct MapDetailView: View {
    @Bindable var map: WorldMap

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation
    @Query private var places: [Page]
    @State private var draft = MapCalibrationDraft()
    @State private var grid = SceneGridDraft()
    @State private var isCalibrating = false
    @State private var markingPoint = 1
    /// The image position a place is being put at, while the sheet for choosing it is open.
    @State private var placement: PlacementSpot?
    @State private var placementProblem: String?
    @State private var isConfirmingDelete = false
    /// The outline being drawn for a place, if any.
    @State private var outline: OutlineDraft?
    @State private var outlineProblem: String?
    @AppStorage("showsMapGrid") private var showsGrid = true
    @State private var selectedPlace: Page?
    /// Whether the picture is being traced for places, and what the last trace did.
    @State private var isTracing = false
    @State private var traceResult: String?
    /// The character whose journey is drawn as a line, if any.
    @State private var journeyCharacter: Page?

    private struct PlacementSpot: Identifiable {
        let id = UUID()
        let x: Double
        let y: Double
    }

    init(map: WorldMap) {
        self.map = map
        let worldID = map.world?.id
        let kindRaw = PageKind.place.rawValue
        _places = Query(filter: #Predicate<Page> { $0.world?.id == worldID && $0.kindRaw == kindRaw })
    }

    /// How the view of the map stands, for the compass rose and the scale.
    @State private var reading: MapViewReading?

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MapKitCanvas(
                map: map,
                markers: markers,
                pins: pins,
                shapes: shapes,
                lines: lines,
                draftCorners: (outline?.corners ?? []).map { CGPoint(x: $0.x, y: $0.y) },
                draftIsLine: outline?.isLine ?? false,
                route: route,
                isMarking: (isCalibrating && map.kind != .scene) || outline != nil,
                canPlace: map.isCalibrated && !isCalibrating && outline == nil,
                showsGrid: showsGrid,
                onTap: { x, y in
                    if outline != nil { outline?.add(x: x, y: y) } else { markPoint(x: x, y: y) }
                },
                onPlace: { x, y in placement = PlacementSpot(x: x, y: y) },
                onMove: { page, x, y in put(page, atPixelX: x, y: y) },
                onSelect: { selectedPlace = $0 },
                highlighted: selectedPlace,
                onReading: { reading = $0 }
            )
            .overlay {
                // The compass rose and the scale, on the sheet of a map that is drawn.
                if map.isVector, let reading {
                    SheetDecorations(style: map.style, unit: DistanceUnit.forCalibrating(map.kind), reading: reading)
                }
            }
            // A place sent here to be shown (from its page) is the one chosen.
            .onAppear { takeHighlight() }
            .onChange(of: navigation.highlightedPlace) { takeHighlight() }
            if let selectedPlace { selectedPlaceBar(selectedPlace) }
            Divider()
            if outline != nil {
                outlinePanel
            } else if map.isVector {
                Text("This map is drawn from its places. Add places by right-clicking or pressing and holding, and draw their outlines and lines. Roads and rivers are places drawn as lines.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(.bar)
            } else {
                MapCalibrationPanel(map: map, draft: $draft, grid: $grid, isCalibrating: $isCalibrating, markingPoint: $markingPoint)
            }
        }
        .navigationTitle(map.name.isEmpty ? String(localized: "Untitled Map") : map.name)
        .sheet(item: $placement) { spot in
            if let world = map.world {
                PlacePlacementSheet(world: world, onCancel: { placement = nil }) { title, placeType, existing in
                    place(title: title, placeType: placeType, existing: existing, at: spot, in: world)
                }
            }
        }
        .sheet(isPresented: $isTracing) {
            TraceMapSheet(map: map) { summary in
                isTracing = false
                if let summary {
                    traceResult = summary.replaced + summary.kept > 0
                        ? String(localized: "Added \(summary.created) places. \(summary.replaced) from the last trace were replaced, and \(summary.kept) that have been edited were kept.")
                        : String(localized: "Added \(summary.created) places over the picture.")
                }
            }
        }
        .alert("Traced the Map", isPresented: Binding(get: { traceResult != nil }, set: { if !$0 { traceResult = nil } })) {
            Button("OK") {}
        } message: {
            Text(traceResult ?? "")
        }
        .alert(
            "Couldn’t Finish the Outline",
            isPresented: Binding(get: { outlineProblem != nil }, set: { if !$0 { outlineProblem = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(outlineProblem ?? "")
        }
        .alert(
            "Couldn’t Put the Place There",
            isPresented: Binding(get: { placementProblem != nil }, set: { if !$0 { placementProblem = nil } })
        ) {
            Button("OK") {}
        } message: {
            Text(placementProblem ?? "")
        }
        // Calibrating makes no sense for a different map or kind than the one being edited.
        .onChange(of: map.kindRaw) { isCalibrating = false }
    }

    // MARK: Style

    /// Choose how this map is drawn, and how the world's maps are drawn unless they choose for themselves.
    @ViewBuilder
    private var styleMenus: some View {
        // A picture's places are drawn in a style too, over the picture or, with the picture hidden, on the style's paper.
        if map.isVector || map.imageData != nil {
            Picker("Style of This Map", selection: $map.styleID) {
                Text("World’s Style (\(MapStyle.style(id: map.world?.mapStyleID ?? "").title))").tag("")
                ForEach(MapStyle.all) { Text($0.title).tag($0.id) }
            }
            if let world = map.world {
                Picker("World’s Style", selection: Binding(get: { world.mapStyleID }, set: { world.mapStyleID = $0 })) {
                    ForEach(MapStyle.all) { Text($0.title).tag($0.id == MapStyle.defaultID ? "" : $0.id) }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $map.name, prompt: Text("Untitled Map"))
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                Menu("Map Options", systemImage: "ellipsis.circle") {
                    if map.kind == .scene {
                        Toggle("Show Grid", isOn: $showsGrid)
                    }
                    styleMenus
                    journeyMenu
                    if !map.isVector && map.imageData != nil {
                        Toggle("Show Picture", isOn: $map.showsPicture)
                    }
                    if !map.isVector && map.isCalibrated {
                        Button("Trace Features…", systemImage: "scribble.variable") { isTracing = true }
                    }
                    Button("Delete Map…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
                }
                .labelStyle(.iconOnly)
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
            breadcrumbs
            if !map.isWorldMap {
                HStack {
                    Picker("Type", selection: kindBinding) {
                        ForEach([MapKind.settlement, .scene]) { kind in
                            Label(String(localized: kind.title), systemImage: kind.systemImage).tag(kind)
                        }
                    }
                    .fixedSize()
                    Spacer()
                }
                Text(map.kind == .settlement
                     ? "A settlement map is centred on its settlement, which must already be on the map above it."
                     : "A scene map is centred on its place, such as a building, which must already be on the map above it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .confirmationDialog("Delete Map?", isPresented: $isConfirmingDelete) {
            Button("Delete Map", role: .destructive, action: deleteMap)
        } message: {
            Text("The map image will be deleted. The places on it are not deleted, and keep their positions.")
        }
    }

    /// The map's place and the places above it, each opening its own map if it has one. This is how to go back
    /// up from a building to its settlement to the world.
    private var breadcrumbs: some View {
        let chain = ((map.place?.ancestors ?? []).reversed() + [map.place].compactMap { $0 })
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(chain, id: \.id) { page in
                    let title = page.title.isEmpty ? String(localized: "Untitled") : page.title
                    if let upMap = page.sortedMaps.first, upMap !== map {
                        Button(title) { navigation.openMap(upMap) }
                            .buttonStyle(.borderless)
                    } else {
                        Text(title)
                            .foregroundStyle(page === map.place ? .primary : .secondary)
                    }
                    if page !== chain.last {
                        Image(systemName: "chevron.right")
                            .accessibilityHidden(true)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var kindBinding: Binding<MapKind> {
        Binding(get: { map.kind }, set: { map.change(to: $0) })
    }

    private func deleteMap() {
        let wasOpen = navigation.selectedMap === map
        if wasOpen { navigation.selectedMap = nil }
        modelContext.delete(map)
    }

    // MARK: Journey

    /// The world's characters, to choose whose journey to draw.
    private var characters: [Page] {
        (map.world?.pages ?? []).filter { $0.kind == .character && !$0.isDeleted }
            .sorted { $0.title.localizedLowercase < $1.title.localizedLowercase }
    }

    private var journeyMenu: some View {
        Menu("Show Journey", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
            if journeyCharacter != nil {
                Button("Hide Journey") { journeyCharacter = nil }
                Divider()
            }
            ForEach(characters) { character in
                Toggle(character.title.isEmpty ? String(localized: "Untitled") : character.title, isOn: Binding(
                    get: { journeyCharacter === character },
                    set: { journeyCharacter = $0 ? character : nil }
                ))
            }
        }
        .disabled(!map.isCalibrated || characters.isEmpty)
    }

    /// The line for the chosen character's journey, through the places of their events that are on this map.
    private var route: [CGPoint] {
        guard let journeyCharacter, !journeyCharacter.isDeleted, map.isCalibrated else { return [] }
        let stops = JourneyBuilder.stops(of: journeyCharacter, calendar: map.world?.calendar)
        return JourneyBuilder.route(of: stops, on: map)
    }

    // MARK: Pins and marks

    /// Places with an outline, which MapKit draws as shapes.
    private var shapes: [PlaceShape] {
        map.visiblePlaces(among: places).flatMap { page -> [PlaceShape] in
            // A place of several pieces, such as a realm with islands, has a shape for each.
            (page.geometry?.outlines ?? []).enumerated().map { PlaceShape(page: page, corners: $0.element, part: $0.offset) }
        }
    }

    /// Places drawn as lines, which are roads and rivers.
    private var lines: [PlaceLine] {
        map.visiblePlaces(among: places).compactMap { page in
            guard case .line(let points)? = page.geometry else { return nil }
            return PlaceLine(page: page, points: points)
        }
    }

    private func takeHighlight() {
        guard let place = navigation.highlightedPlace else { return }
        selectedPlace = place
        navigation.highlightedPlace = nil
    }

    /// What can be done with the place picked on the MapKit map, in place of the popover of the custom canvas.
    private func selectedPlaceBar(_ page: Page) -> some View {
        HStack {
            Image(systemName: page.kind.systemImage)
    .accessibilityHidden(true)
            Text(page.title.isEmpty ? String(localized: "Untitled") : page.title)
                .font(.headline)
            Spacer()
            Button("Open Place") { navigation.open(page) }
            ForEach(page.sortedMaps.filter { $0 !== map }) { other in
                Button("Open Map") { navigation.openMap(other) }
            }
            if map.isCalibrated && outline == nil {
                if !page.isLine { Button(page.isPoint ? "Draw Outline" : "Redraw Outline") { outline = OutlineDraft(page: page) } }
                Button(page.isLine ? "Redraw Line" : "Draw Line") { outline = OutlineDraft(page: page, isLine: true) }
            }
            if !page.isPoint, let centre = page.geometry?.centre {
                Button(page.isLine ? "Remove Line" : "Remove Outline") { page.setGeometry(.point(centre)) }
            }
            Button("Remove From Maps", role: .destructive) {
                selectedPlace = nil
                page.setGeometry(nil)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    /// The places that are on this map, wherever it is.
    private var pins: [PlacePin] {
        guard map.isCalibrated else { return [] }
        return map.visiblePlaces(among: places).compactMap { page in
            // Only a place with a pin kind has one: an area is named across it, a line along it, and a building is a plain shape.
            guard PlacePinKind.of(page) != nil else { return nil }
            return map.pixel(of: page).map { PlacePin(page: page, pixelX: $0.x, pixelY: $0.y, isMovable: page.isPoint) }
        }
    }

    /// The two points being marked for calibration.
    private var markers: [MapMarker] {
        if let outline {
            return outline.corners.enumerated().map { MapMarker(id: $0.offset + 1, pixelX: $0.element.x, pixelY: $0.element.y, label: String($0.offset + 1)) }
        }
        guard isCalibrating, map.kind != .scene else { return [] }
        return [(1, draft.first), (2, draft.second)].compactMap { number, point in
            guard let x = point.pixelX, let y = point.pixelY else { return nil }
            return MapMarker(id: number, pixelX: x, pixelY: y, label: String(number))
        }
    }

    /// While calibrating, a click marks the chosen point and moves on to the other one.
    private func markPoint(x: Double, y: Double) {
        guard isCalibrating, map.kind != .scene else { return }
        if markingPoint == 1 {
            draft.first.pixelX = x
            draft.first.pixelY = y
            markingPoint = 2
        } else {
            draft.second.pixelX = x
            draft.second.pixelY = y
        }
    }

    // MARK: Drawing outlines

    private var outlinePanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let outline {
                let name = outline.page.title.isEmpty ? String(localized: "Untitled") : outline.page.title
                Text(outline.isLine
                     ? String(localized: "Drawing “\(name)” as a line. Click each point in turn, along its way.")
                     : String(localized: "Drawing the outline of “\(name)”. Click each corner in turn, going round the edge. Places inside it will be put inside this place."))
                    .font(.callout)
                HStack {
                    if let calibration = map.calibration, let problem = outline.problem(on: calibration) {
                        Text(problem)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(outline.isLine ? "Undo Point" : "Undo Corner") { self.outline?.removeLast() }
                        .disabled(outline.corners.isEmpty)
                    Button("Cancel", role: .cancel) { self.outline = nil }
                    Button("Finish", action: finishOutline)
                        .buttonStyle(.borderedProminent)
                        .disabled(map.calibration.map { outline.problem(on: $0) != nil } ?? true)
                }
            }
        }
        .padding()
        .background(.bar)
    }

    private func finishOutline() {
        guard let outline, let calibration = map.calibration else { return }
        guard let shape = outline.geometry(on: calibration), outline.page.setGeometry(shape) else {
            outlineProblem = outline.problem(on: calibration) ?? String(localized: "The outline can’t be used.")
            return
        }
        self.outline = nil
    }

    // MARK: Putting places on the map

    private func place(title: String, placeType: String?, existing: Page?, at spot: PlacementSpot, in world: World) {
        if let existing {
            put(existing, atPixelX: spot.x, y: spot.y)
        } else {
            let page = world.addPage(kind: .place, in: modelContext)
            page.title = title
            if let placeType { page.setAttributeText("core.placeType", placeType) }
            // A place put on a settlement's map is inside that settlement. On the world map it is inside the
            // world, which is where it starts.
            if let shown = map.place, !shown.isWorldRoot { page.setParent(shown) }
            if !put(page, atPixelX: spot.x, y: spot.y) {
                // It couldn't be put there, so there's nothing to keep.
                modelContext.delete(page)
            }
        }
        placement = nil
    }

    /// Puts a place at an image position, telling the creator if that isn't possible. Returns whether it was.
    @discardableResult
    private func put(_ page: Page, atPixelX x: Double, y: Double) -> Bool {
        switch map.position(page, atPixelX: x, y: y) {
        case .placed:
            return true
        case .mapNotCalibrated:
            placementProblem = String(localized: "Calibrate this map first.")
        case .outsideWorld:
            placementProblem = String(localized: "That spot is off the edge of the world, where positions can’t go. Choose a spot further in, or move the place this map is centred on away from the edge.")
        case .notAPlace:
            placementProblem = String(localized: "Only places can be put on a map.")
        }
        return false
    }
}

@MainActor
private func previewMap(kind: MapKind = .world, calibrated: Bool) -> (ModelContainer, WorldMap) {
    let container = SampleData.makePreviewContainer()
    let context = container.mainContext
    let world = (try? context.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    let root = world?.rootPlace
    let map = WorldMap(name: kind == .scene ? "The Gilded Gull, cellar" : "Sword Coast", imageData: SampleData.solidImage(width: 1500, height: 900, blue: 0.8), kind: kind)
    map.pixelWidth = 1500
    map.pixelHeight = 900
    context.insert(map)
    map.world = world
    if kind == .world {
        map.place = root
    } else {
        let town = Page(title: "Brackwater", kind: .place)
        context.insert(town)
        town.world = world
        town.parent = root
        if calibrated || kind == .scene { town.setGeometry(.point(GridPoint(easting: 5_000, northing: 5_000))) }
        if kind == .scene {
            let place = Page(title: "The Gilded Gull", kind: .place)
            context.insert(place)
            place.world = world
            place.parent = town
            place.setGeometry(.point(GridPoint(easting: 5_000, northing: 5_000)))
            map.place = place
        } else {
            map.place = town
        }
    }
    if calibrated, kind == .scene {
        map.gridColumns = 30
        map.gridRows = 18
        map.calibration = MapCalibration.scene(
            columns: 30, rows: 18, squareMetres: 1.524, imageWidth: 1500, imageHeight: 900, centredOn: GridPoint(easting: 5_000, northing: 5_000)
        )?.calibration
        let cellar = Page(title: "Cellar door", kind: .place)
        context.insert(cellar)
        cellar.world = world
        map.position(cellar, atPixelX: 300, y: 700)
    } else if calibrated, kind == .world {
        map.calibration = MapCalibration(pixelA: (0, 0), pixelB: (1500, 0), distanceMetres: 600_000, imageHeight: 900)
        for (title, x, y) in [("Brackwater", 400.0, 300.0), ("Mistfen", 900.0, 600.0)] {
            let page = Page(title: title, kind: .place)
            context.insert(page)
            page.world = world
            map.position(page, atPixelX: x, y: y)
        }
    }
    return (container, map)
}

#Preview("World map, not calibrated") {
    let (container, map) = previewMap(calibrated: false)
    return MapDetailView(map: map)
        .environment(WorldNavigation())
        .frame(width: 800, height: 600)
        .modelContainer(container)
}

#Preview("World map, with places") {
    let (container, map) = previewMap(calibrated: true)
    return MapDetailView(map: map)
        .environment(WorldNavigation())
        .frame(width: 800, height: 600)
        .modelContainer(container)
}

#Preview("Scene map") {
    let (container, map) = previewMap(kind: .scene, calibrated: true)
    return MapDetailView(map: map)
        .environment(WorldNavigation())
        .frame(width: 800, height: 600)
        .modelContainer(container)
}

#Preview("Settlement not on a map yet") {
    let (container, map) = previewMap(kind: .settlement, calibrated: false)
    return MapDetailView(map: map)
        .environment(WorldNavigation())
        .frame(width: 800, height: 600)
        .modelContainer(container)
}

extension Page {
    /// Whether the place is a single point, rather than an area with an outline or a line.
    var isPoint: Bool {
        if case .point? = geometry { true } else { false }
    }

    /// Whether the place is a line, such as a road or river.
    var isLine: Bool {
        if case .line? = geometry { true } else { false }
    }
}

#Preview("Vector map") {
    let container = try! AppSchema.makeContainer(inMemory: true)
    let context = container.mainContext
    let world = World(name: "Preview")
    context.insert(world)
    let root = world.ensureRootPlace(in: context)
    let map = world.addVectorMap(named: "World", for: root, extentMetres: 400_000, in: context)!
    func area(_ title: String, _ type: String, _ corners: [(Double, Double)]) -> Page {
        let page = world.addPage(kind: .place, in: context)
        page.title = title
        page.setAttributeText("core.placeType", type)
        _ = page.setGeometry(.polygon(corners.map { GridPoint(easting: $0.0, northing: $0.1) }))
        return page
    }
    func line(_ title: String, _ type: String, _ points: [(Double, Double)]) {
        let page = world.addPage(kind: .place, in: context)
        page.title = title
        page.setAttributeText("core.placeType", type)
        _ = page.setGeometry(.line(points.map { GridPoint(easting: $0.0, northing: $0.1) }))
    }
    _ = area("Sea", "Water", [(0, 0), (400_000, 0), (400_000, 90_000), (300_000, 70_000), (200_000, 100_000), (100_000, 60_000), (0, 80_000)])
    _ = area("Greenwood", "Forest", [(60_000, 180_000), (150_000, 170_000), (170_000, 260_000), (90_000, 290_000)])
    _ = area("Ironspine", "Mountains", [(250_000, 250_000), (360_000, 230_000), (380_000, 340_000), (280_000, 370_000)])
    let town = area("Harrowgate", "Settlement", [(190_000, 150_000), (215_000, 150_000), (215_000, 175_000), (190_000, 175_000)])
    let hall = area("Guildhall", "Building", [(196_000, 156_000), (202_000, 156_000), (202_000, 162_000), (196_000, 162_000)])
    hall.parent = town
    line("The Silverrun", "River", [(120_000, 330_000), (160_000, 250_000), (200_000, 190_000), (205_000, 120_000), (230_000, 60_000)])
    line("King's Road", "Road", [(20_000, 140_000), (120_000, 160_000), (202_000, 162_000), (300_000, 200_000), (380_000, 215_000)])
    map.place = root
    return NavigationStack {
        MapDetailView(map: map)
    }
    .environment(WorldNavigation())
    .modelContainer(container)
    .frame(width: 900, height: 700)
}
