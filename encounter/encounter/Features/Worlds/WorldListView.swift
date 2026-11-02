//
//  WorldListView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The home screen: pick a world, create one, or import one. Editing, exporting and deleting a world
/// happen on the world's own home page.
struct WorldListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \World.createdAt) private var worlds: [World]

    @State private var path: [World] = []
    @State private var worldPendingDeletion: World?
    @State private var isCreatingWorld = false
    @State private var isChoosingImportFile = false
    @State private var isImporting = false
    @State private var isShowingAbout = false
    @State private var transferResult: TransferResult?

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if worlds.isEmpty {
                    ContentUnavailableView {
                        Label("No Worlds", systemImage: "globe.europe.africa")
                    } description: {
                        Text("Create a world to start building characters, places and events, or import one.")
                    } actions: {
                        Button("Create World") { isCreatingWorld = true }
                            .buttonStyle(.borderedProminent)
                        Button("Import World…") { isChoosingImportFile = true }
                    }
                } else {
                    List(worlds) { world in
                        NavigationLink(value: world) {
                            WorldRow(world: world)
                        }
                    }
                }
            }
            .navigationTitle("Worlds")
            .navigationDestination(for: World.self) { world in
                WorldShellView(world: world, onDelete: delete)
            }
            .toolbar {
                ToolbarItem {
                    Button("About", systemImage: "info.circle") { isShowingAbout = true }
                }
                ToolbarItem {
                    Button("Import World", systemImage: "square.and.arrow.down") { isChoosingImportFile = true }
                }
                ToolbarItem {
                    Button("New World", systemImage: "plus") { isCreatingWorld = true }
                }
            }
            .sheet(isPresented: $isCreatingWorld) {
                NewWorldSheet()
            }
            .sheet(isPresented: $isShowingAbout) {
                AboutView()
            }
            .fileImporter(isPresented: $isChoosingImportFile, allowedContentTypes: [.encounterWorld]) { result in
                switch result {
                case .success(let url):
                    Task { await importWorld(from: url) }
                case .failure(let error):
                    transferResult = .failed(title: "Couldn’t Import World", message: error.localizedDescription)
                }
            }
            .overlay {
                if isImporting {
                    ProgressView("Importing…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .alert(
                transferResult?.title ?? "",
                isPresented: Binding(get: { transferResult != nil }, set: { if !$0 { transferResult = nil } }),
                presenting: transferResult
            ) { _ in
                Button("OK") {}
            } message: { result in
                result.message
            }
            // The world is deleted only once its screens have gone, so nothing is left showing a deleted world.
            .onChange(of: path) {
                if path.isEmpty, let world = worldPendingDeletion {
                    worldPendingDeletion = nil
                    modelContext.delete(world)
                }
            }
        }
    }

    private func delete(_ world: World) {
        worldPendingDeletion = world
        path.removeAll()
    }

    private func importWorld(from url: URL) async {
        isImporting = true
        defer { isImporting = false }
        do {
            let contents = try await WorldPackage.read(from: url)
            let (_, summary) = await WorldImporter.importWorld(contents, into: modelContext)
            transferResult = .imported(summary)
        } catch {
            transferResult = .failed(title: "Couldn’t Import World", message: error.localizedDescription)
        }
    }
}

/// The outcome of an import, shown in an alert.
private enum TransferResult: Identifiable {
    case imported(ImportSummary)
    case failed(title: LocalizedStringKey, message: String)

    var id: String {
        switch self {
        case .imported(let summary): "imported-\(summary.worldName)"
        case .failed(_, let message): "failed-\(message)"
        }
    }

    var title: LocalizedStringKey {
        switch self {
        case .imported(let summary): summary.skippedAnything ? "World Imported With Gaps" : "World Imported"
        case .failed(let title, _): title
        }
    }

    var message: Text {
        switch self {
        case .imported(let summary):
            let overview = Text("Created “\(summary.worldName)” with ^[\(summary.pages) page](inflect: true), ^[\(summary.images) image](inflect: true) and ^[\(summary.maps) map](inflect: true).")
            guard summary.skippedAnything else { return overview }
            let gaps = Text("Left out: ^[\(summary.skippedLinks) link](inflect: true) and ^[\(summary.skippedImages) image](inflect: true) that couldn’t be read or pointed at missing pages.")
            return Text("\(overview)\n\n\(gaps)")
        case .failed(_, let message):
            return Text(message)
        }
    }
}

private struct WorldRow: View {
    let world: World

    private let thumbnailSize: CGFloat = 44

    var body: some View {
        HStack(spacing: 12) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(world.name.isEmpty ? String(localized: "Untitled World") : world.name)
                    .font(.headline)
                Text(world.systemTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The world's default image, or a globe if it has none.
    @ViewBuilder
    private var thumbnail: some View {
        if let data = world.defaultImage?.thumbnailData {
            DataImage(data: data)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Image(systemName: "globe.europe.africa")
                .foregroundStyle(.secondary)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

#Preview("Populated") {
    WorldListView()
        .modelContainer(SampleData.makePreviewContainer())
}

#Preview("Empty") {
    WorldListView()
        .modelContainer(SampleData.makePreviewContainer(populated: false))
}
