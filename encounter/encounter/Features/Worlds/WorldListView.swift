//
//  WorldListView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The home screen: pick a world, or create, edit and delete worlds.
struct WorldListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \World.createdAt) private var worlds: [World]

    @State private var editorMode: WorldEditorMode?
    @State private var worldToDelete: World?

    var body: some View {
        NavigationStack {
            Group {
                if worlds.isEmpty {
                    ContentUnavailableView {
                        Label("No Worlds", systemImage: "globe.europe.africa")
                    } description: {
                        Text("Create a world to start building characters, places and events.")
                    } actions: {
                        Button("Create World") { editorMode = .create }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(worlds) { world in
                            NavigationLink(value: world) {
                                WorldRow(world: world)
                            }
                            .contextMenu {
                                Button("Edit…", systemImage: "pencil") { editorMode = .edit(world) }
                                Button("Delete…", systemImage: "trash", role: .destructive) { worldToDelete = world }
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { worldToDelete = world }
                                Button("Edit", systemImage: "pencil") { editorMode = .edit(world) }
                                    .tint(.blue)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Worlds")
            .navigationDestination(for: World.self) { world in
                WorldShellView(world: world)
            }
            .toolbar {
                ToolbarItem {
                    Button("New World", systemImage: "plus") { editorMode = .create }
                }
            }
            .sheet(item: $editorMode) { mode in
                WorldEditorSheet(mode: mode)
            }
            .alert(
                "Delete World?",
                isPresented: Binding(get: { worldToDelete != nil }, set: { if !$0 { worldToDelete = nil } }),
                presenting: worldToDelete
            ) { world in
                Button("Delete", role: .destructive) { modelContext.delete(world) }
                Button("Cancel", role: .cancel) {}
            } message: { world in
                Text("“\(world.name)” and all of its pages, maps and campaigns will be deleted. This can’t be undone.")
            }
        }
    }
}

private struct WorldRow: View {
    let world: World

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(world.name)
                .font(.headline)
            Text(world.system.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
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
