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

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            MapCanvas(
                map: map,
                markers: markers,
                pins: pins,
                canPlace: map.isCalibrated && !isCalibrating,
                onTap: { x, y in markPoint(x: x, y: y) },
                onPlace: { x, y in placement = PlacementSpot(x: x, y: y) },
                onMove: { page, x, y in put(page, atPixelX: x, y: y) }
            )
            Divider()
            MapCalibrationPanel(map: map, draft: $draft, grid: $grid, isCalibrating: $isCalibrating, markingPoint: $markingPoint)
        }
        .navigationTitle(map.name.isEmpty ? String(localized: "Untitled Map") : map.name)
        .sheet(item: $placement) { spot in
            if let world = map.world {
                PlacePlacementSheet(world: world, onCancel: { placement = nil }) { title, placeType, existing in
                    place(title: title, placeType: placeType, existing: existing, at: spot, in: world)
                }
            }
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

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField("Name", text: $map.name, prompt: Text("Untitled Map"))
                    .font(.title2.weight(.semibold))
                    .textFieldStyle(.plain)
                Menu("Map Options", systemImage: "ellipsis.circle") {
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
                            .buttonStyle(.link)
                    } else {
                        Text(title)
                            .foregroundStyle(page === map.place ? .primary : .secondary)
                    }
                    if page !== chain.last {
                        Image(systemName: "chevron.right")
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

    // MARK: Pins and marks

    /// The places that are on this map, wherever it is.
    private var pins: [PlacePin] {
        guard map.isCalibrated else { return [] }
        return places.filter { $0 !== map.place }.compactMap { page in
            map.pixel(of: page).map { PlacePin(page: page, pixelX: $0.x, pixelY: $0.y) }
        }
    }

    /// The two points being marked for calibration.
    private var markers: [MapMarker] {
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
