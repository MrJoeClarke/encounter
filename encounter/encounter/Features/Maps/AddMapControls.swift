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

    var body: some View {
        HStack {
            Button("Add Map…", systemImage: "map") { isChoosingFiles = true }
            PhotosPicker(selection: $photoSelection, maxSelectionCount: 1, matching: .images) {
                Label("From Photos", systemImage: "photo.on.rectangle")
            }
            if isImporting {
                ProgressView().controlSize(.small)
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
