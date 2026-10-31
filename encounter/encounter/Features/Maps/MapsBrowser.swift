//
//  MapsBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// A world's maps: the list beside the selected map.
struct MapsBrowser: View {
    let world: World

    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        #if os(macOS)
        HSplitView {
            MapsListView(world: world, selection: selectedMap)
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
                .layoutPriority(-1)
            detail
                .frame(minWidth: 360, idealWidth: 800, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        NavigationSplitView {
            MapsListView(world: world, selection: selectedMap)
        } detail: {
            detail
        }
        #endif
    }

    private var selectedMap: Binding<WorldMap?> {
        Binding(get: { navigation.selectedMap }, set: { navigation.selectedMap = $0 })
    }

    @ViewBuilder
    private var detail: some View {
        if let map = navigation.selectedMap {
            MapDetailView(map: map)
                .id(map.id)
        } else {
            ContentUnavailableView("No Map Selected", systemImage: "map")
        }
    }
}

/// The world's maps, with import and delete.
struct MapsListView: View {
    let world: World
    @Binding var selection: WorldMap?

    @Environment(\.modelContext) private var modelContext
    @Query private var maps: [WorldMap]
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isChoosingFiles = false
    @State private var isImporting = false
    @State private var failedImportCount = 0
    @State private var mapToDelete: WorldMap?

    init(world: World, selection: Binding<WorldMap?>) {
        self.world = world
        _selection = selection
        let worldID = world.id
        _maps = Query(filter: #Predicate<WorldMap> { $0.world?.id == worldID }, sort: \WorldMap.name)
    }

    var body: some View {
        Group {
            if maps.isEmpty {
                ContentUnavailableView {
                    Label("Maps", systemImage: "map")
                } description: {
                    Text("Import a map image to start. Drop image files here, or use Import Map.")
                } actions: {
                    Button("Import Map…") { isChoosingFiles = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selection) {
                    ForEach(maps) { map in
                        MapRow(map: map)
                            .tag(map)
                            .contextMenu {
                                Button("Delete…", systemImage: "trash", role: .destructive) { mapToDelete = map }
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { mapToDelete = map }
                            }
                    }
                }
            }
        }
        .navigationTitle("Maps")
        .toolbar {
            ToolbarItem {
                Menu("Import Map", systemImage: "plus") {
                    Button("From Files…", systemImage: "folder") { isChoosingFiles = true }
                }
            }
            ToolbarItem {
                PhotosPicker(selection: $photoSelection, maxSelectionCount: 1, matching: .images) {
                    Label("Import from Photos", systemImage: "photo.on.rectangle")
                }
            }
            if isImporting {
                ToolbarItem { ProgressView().controlSize(.small) }
            }
        }
        .dropDestination(for: URL.self) { urls, _ in
            Task { await importFiles(urls) }
            return !urls.isEmpty
        }
        .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await importFiles(urls) }
        }
        .onChange(of: photoSelection) {
            let items = photoSelection
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await importPhotos(items) }
        }
        .alert(
            "Delete Map?",
            isPresented: Binding(get: { mapToDelete != nil }, set: { if !$0 { mapToDelete = nil } }),
            presenting: mapToDelete
        ) { map in
            Button("Delete", role: .destructive) { delete(map) }
            Button("Cancel", role: .cancel) {}
        } message: { map in
            Text("“\(map.name.isEmpty ? String(localized: "Untitled Map") : map.name)” will be deleted. The places on it are not deleted. This can’t be undone.")
        }
        .alert(
            "Some Maps Couldn’t Be Added",
            isPresented: Binding(get: { failedImportCount > 0 }, set: { if !$0 { failedImportCount = 0 } })
        ) {
            Button("OK") {}
        } message: {
            Text("^[\(failedImportCount) file](inflect: true) couldn’t be read as an image.")
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            guard let data = await ImageProcessing.loadData(from: url),
                  let map = await world.addMap(named: url.deletingPathExtension().lastPathComponent, from: data, in: modelContext)
            else {
                failedImportCount += 1
                continue
            }
            selection = map
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let map = await world.addMap(named: String(localized: "Imported Map"), from: data, in: modelContext)
            else {
                failedImportCount += 1
                continue
            }
            selection = map
        }
    }

    private func delete(_ map: WorldMap) {
        // Clear the selection first so the detail pane never shows a deleted map.
        if selection == map { selection = nil }
        modelContext.delete(map)
    }
}

private struct MapRow: View {
    let map: WorldMap

    private var subtitle: String {
        let kind = String(localized: map.kind.title)
        return map.isCalibrated ? kind : kind + " · " + String(localized: "Not calibrated")
    }

    var body: some View {
        HStack(spacing: 10) {
            DataImage(data: map.thumbnailData ?? map.imageData)
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 2) {
                Text(map.name.isEmpty ? String(localized: "Untitled Map") : map.name)
                Label {
                    Text(subtitle)
                } icon: {
                    Image(systemName: map.isCalibrated ? map.kind.systemImage : "exclamationmark.triangle")
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
    }
}

/// One map: its name, the map itself, and its calibration.
struct MapDetailView: View {
    @Bindable var map: WorldMap

    @State private var draft = MapCalibrationDraft()
    @State private var isCalibrating = false
    @State private var markingPoint = 1

    var body: some View {
        VStack(spacing: 0) {
            TextField("Name", text: $map.name, prompt: Text("Untitled Map"))
                .font(.title2.weight(.semibold))
                .textFieldStyle(.plain)
                .padding()
            Divider()
            MapCanvas(map: map, markers: markers) { x, y in
                markPoint(x: x, y: y)
            }
            Divider()
            MapCalibrationPanel(map: map, draft: $draft, isCalibrating: $isCalibrating, markingPoint: $markingPoint)
        }
        .navigationTitle(map.name.isEmpty ? String(localized: "Untitled Map") : map.name)
    }

    /// The two points being marked for calibration.
    private var markers: [MapMarker] {
        guard isCalibrating else { return [] }
        return [(1, draft.first), (2, draft.second)].compactMap { number, point in
            guard let x = point.pixelX, let y = point.pixelY else { return nil }
            return MapMarker(id: number, pixelX: x, pixelY: y, label: String(number))
        }
    }

    /// While calibrating, a click marks the chosen point and moves on to the other one.
    private func markPoint(x: Double, y: Double) {
        guard isCalibrating else { return }
        if markingPoint == 1 {
            draft.first.pixelX = x
            draft.first.pixelY = y
            markingPoint = 2
        } else {
            draft.second.pixelX = x
            draft.second.pixelY = y
        }
    }
}

@MainActor
private func previewMap(calibrated: Bool) -> (ModelContainer, WorldMap) {
    let container = SampleData.makePreviewContainer()
    let context = container.mainContext
    let world = (try? context.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    let map = WorldMap(name: "Sword Coast", imageData: SampleData.solidImage(width: 1600, height: 1000, blue: 0.8))
    map.pixelWidth = 1600
    map.pixelHeight = 1000
    context.insert(map)
    map.world = world
    if calibrated {
        map.calibration = MapCalibration(originEasting: 100_000, originNorthing: 300_000, metresPerPixel: 25)
    }
    return (container, map)
}

#Preview("Not calibrated") {
    let (container, map) = previewMap(calibrated: false)
    return MapDetailView(map: map)
        .frame(width: 800, height: 600)
        .modelContainer(container)
}

#Preview("Calibrated") {
    let (container, map) = previewMap(calibrated: true)
    return MapDetailView(map: map)
        .frame(width: 800, height: 600)
        .modelContainer(container)
}
