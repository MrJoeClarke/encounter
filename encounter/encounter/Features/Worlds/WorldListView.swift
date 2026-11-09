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
    @State private var searchText = ""

    /// The worlds whose names contain the search text, ignoring case and accents.
    private var shownWorlds: [World] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return worlds }
        return worlds.filter { $0.name.localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if worlds.isEmpty {
                    ContentUnavailableView {
                        ThemedEmptyLabel("No Worlds", systemImage: "globe.europe.africa")
                    } description: {
                        Text("Create a world to start building characters, places and events, or import one.")
                    } actions: {
                        Group {
                            Button("Create World") { isCreatingWorld = true }
                                .buttonStyle(.borderedProminent)
                            Button("Import World…") { isChoosingImportFile = true }
                        }
                        .emptyStateButtons()
                    }
                } else {
                    ScrollView {
                        if shownWorlds.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                                .padding(.top, 60)
                        } else {
                            // Cover art in the manner of an album grid: as many columns as fit, each cover a square.
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 20, alignment: .top)], spacing: 24) {
                                ForEach(shownWorlds) { world in
                                    NavigationLink(value: world) {
                                        WorldCover(world: world)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(20)
                            EndMarkRow()
                        }
                    }
                    .themedScreen()
                    .searchable(text: $searchText, prompt: "Search Worlds")
                }
            }
            .themedBackground()
            .themedNavigationTitle(String(localized: "Worlds"))
            .focusedSceneValue(\.worldListActions, WorldListActions(newWorld: { isCreatingWorld = true }, importWorld: { isChoosingImportFile = true }))
            .navigationDestination(for: World.self) { world in
                WorldRoot(world: world, onDelete: delete)
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

/// A world as a square cover with its name beneath, for the grid of worlds.
private struct WorldCover: View {
    @Environment(\.appTheme) private var theme
    let world: World

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Color.clear
                .aspectRatio(1, contentMode: .fit)
                .background {
                    if let data = world.defaultImage?.imageData ?? world.defaultImage?.thumbnailData {
                        DataImage(data: data)
                    } else {
                        (theme.panel?.themeColor ?? Color.secondary.opacity(0.12))
                            .overlay { SealIcon(systemName: "globe.europe.africa", size: 72) }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: theme.cornerRadius > 0 ? theme.cornerRadius : 10))
                .overlay {
                    RoundedRectangle(cornerRadius: theme.cornerRadius > 0 ? theme.cornerRadius : 10)
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.2), radius: 6, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(world.name.isEmpty ? String(localized: "Untitled World") : world.name)
                    .themedTitle(.headline)
                    .lineLimit(2)
                Text(world.systemTitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
#Preview("No worlds, Parchment and Ink") { WorldListView().modelContainer(SampleData.makePreviewContainer(populated: false)).inTheme(.parchment()) }
#Preview("Worlds, Parchment and Ink at night") { WorldListView().modelContainer(SampleData.makePreviewContainer()).inTheme(.parchment(night: true)).preferredColorScheme(.dark) }
#endif
