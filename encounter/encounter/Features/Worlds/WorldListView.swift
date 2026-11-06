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
    /// The world this window had open, kept by the system for it, so it comes back to the same world after the app has been closed.
    @SceneStorage("openWorldID") private var openWorldID = ""
    @State private var hasRestoredWorld = false
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
                        .themedRow()
                    }
                    .themedScreen()
                }
            }
            .themedNavigationTitle(String(localized: "Worlds"))
            .focusedSceneValue(\.worldListActions, WorldListActions(newWorld: { isCreatingWorld = true }, importWorld: { isChoosingImportFile = true }))
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
            // The world this window had open comes back, once the worlds are there to find it in.
            .onChange(of: worlds.count, initial: true) {
                guard !hasRestoredWorld, !worlds.isEmpty else { return }
                hasRestoredWorld = true
                if path.isEmpty, let world = worlds.first(where: { $0.id.uuidString == openWorldID }) { path = [world] }
            }
            // The world is deleted only once its screens have gone, so nothing is left showing a deleted world.
            .onChange(of: path) {
                if hasRestoredWorld { openWorldID = path.last?.id.uuidString ?? "" }
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
            ThemedThumbnail(data: world.defaultImage?.thumbnailData, systemName: "globe.europe.africa", size: thumbnailSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(world.name.isEmpty ? String(localized: "Untitled World") : world.name)
                    .themedTitle(.headline)
                Text(world.systemTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
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

#if DEBUG
#Preview("Worlds, Parchment and Ink") { WorldListView().modelContainer(SampleData.makePreviewContainer()).inTheme(.parchment()) }
#Preview("Worlds, Parchment and Ink at night") { WorldListView().modelContainer(SampleData.makePreviewContainer()).inTheme(.parchment(night: true)).preferredColorScheme(.dark) }
#endif
