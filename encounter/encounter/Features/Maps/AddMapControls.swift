//
//  AddMapControls.swift
//  encounter
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// Buttons that add a map to a place, from a file or from Photos, and accept image files dropped on them.
/// Opens the new map when it is added.
struct AddMapControls: View {
    let place: Page

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isChoosingFiles = false
    @State private var isImporting = false
    @State private var failedImportCount = 0
    @State private var isAddingVectorMap = false
    @State private var isGeneratingSettlement = false
    @State private var isGeneratingWorld = false
    @State private var isGeneratingScene = false

    /// A world can be generated when it has no map, or only a map that was generated.
    private var canGenerateWorld: Bool {
        guard place.isWorldRoot else { return false }
        let maps = place.sortedMaps
        return maps.isEmpty || maps.allSatisfy { $0.isVector && $0.generatorData != nil }
    }

    var body: some View {
        HStack {
            Button("Add Map…", systemImage: "map") { isChoosingFiles = true }
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 1, matching: .images) {
                Label("From Photos", systemImage: "photo.on.rectangle")
            }
            Button("Blank Vector Map…", systemImage: "scribble.variable") { isAddingVectorMap = true }
            if !place.isWorldRoot {
                // A building is already as small as a settlement gets, so it only has scenes.
                if place.canHaveSettlementMap {
                    Button("Generate Settlement…", systemImage: "building.2") { isGeneratingSettlement = true }
                }
                Button("Generate Scene…", systemImage: "square.grid.3x3") { isGeneratingScene = true }
            } else if canGenerateWorld {
                Button("Generate World…", systemImage: "globe.europe.africa") { isGeneratingWorld = true }
            }
            if isImporting {
                ProgressView().controlSize(.small)
            }
        }
        .sheet(isPresented: $isGeneratingSettlement) {
            GenerateSettlementSheet(place: place) { map in
                isGeneratingSettlement = false
                if let map { navigation.openMap(map) }
            }
        }
        .sheet(isPresented: $isGeneratingScene) {
            GenerateSceneSheet(place: place) { map in
                isGeneratingScene = false
                if let map { navigation.openMap(map) }
            }
        }
        .sheet(isPresented: $isGeneratingWorld) {
            if let world = place.world {
                GenerateWorldSheet(world: world) { map in
                    isGeneratingWorld = false
                    if let map { navigation.openMap(map) }
                }
            }
        }
        .sheet(isPresented: $isAddingVectorMap) {
            NewVectorMapSheet(place: place) { map in
                isAddingVectorMap = false
                if let map { navigation.openMap(map) }
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
            "Some Maps Couldn’t Be Added",
            isPresented: Binding(get: { failedImportCount > 0 }, set: { if !$0 { failedImportCount = 0 } })
        ) {
            Button("OK") {}
        } message: {
            Text("^[\(failedImportCount) file](inflect: true) couldn’t be read as an image.")
        }
    }

    private func importFiles(_ urls: [URL]) async {
        guard let world = place.world else { return }
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            guard let data = await ImageProcessing.loadData(from: url),
                  let map = await world.addMap(named: url.deletingPathExtension().lastPathComponent, from: data, for: place, in: modelContext)
            else {
                failedImportCount += 1
                continue
            }
            navigation.openMap(map)
            // The world has a single map, so extra files are ignored.
            if place.isWorldRoot { break }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        guard let world = place.world else { return }
        isImporting = true
        defer { isImporting = false }
        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self),
                  let map = await world.addMap(named: place.title.isEmpty ? String(localized: "Imported Map") : place.title, from: data, for: place, in: modelContext)
            else {
                failedImportCount += 1
                continue
            }
            navigation.openMap(map)
        }
    }
}

/// Asks how big a map with no picture is, in the unit the kind of map is measured in, and makes it.
struct NewVectorMapSheet: View {
    let place: Page
    let onDone: (WorldMap?) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var name = ""
    @State private var width = 0.0

    private var kind: MapKind { place.isWorldRoot ? .world : .settlement }
    private var unit: DistanceUnit { .forCalibrating(kind) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name, prompt: Text(place.title.isEmpty ? "Untitled Map" : "\(place.title) Map"))
                    LabeledContent("Width and Height") {
                        HStack {
                            TextField("Size", value: $width, format: .number)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                            Text(unit.name)
                        }
                    }
                } footer: {
                    Text("A map with no picture. Its places are drawn on it, and it is as sharp as you zoom. A settlement map is centred on its place.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New Vector Map")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { onDone(nil) } }
                ToolbarItem(placement: .confirmationAction) { Button("Add", action: add).disabled(width < 1) }
            }
            .onAppear { if width == 0 { width = kind == .world ? 1_000 : 2_000 } }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 240)
        #endif
    }

    private func add() {
        guard let world = place.world else { return }
        let title = name.trimmingCharacters(in: .whitespaces)
        let map = world.addVectorMap(
            named: title.isEmpty ? (place.title.isEmpty ? String(localized: "Untitled Map") : "\(place.title) Map") : title,
            for: place, extentMetres: width * unit.metres, in: modelContext
        )
        onDone(map)
    }
}
