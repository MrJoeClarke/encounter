//
//  PlayerPreview.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A world as its players see it: only the published pages, each as it was published, with no DM Notes. It is made as a copy of the world
/// in memory, from the same archive that exports a world, so the screens it is shown on are the ordinary ones and nothing in it is kept.
@MainActor
enum PlayerView {
    /// The archive of the world with everything players mustn't see taken out and each page put back as it was published.
    static func contents(for world: World) -> WorldPackageContents {
        var contents = WorldExporter.makeContents(of: world)
        let pages = Dictionary((world.pages ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var shown: [UUID: PublishedPage] = [:]
        for (id, page) in pages {
            if let version = page.versionForPlayers { shown[id] = version }
        }

        var records: [PageRecord] = []
        for var record in contents.archive.pages {
            guard let version = shown[record.id] else { continue }
            record.title = version.title
            record.summary = version.summary
            record.body = version.body
            record.attributes = version.attributes
            record.tags = version.tags
            record.characterRole = version.characterRoleRaw
            record.eventOrigin = version.eventOriginRaw
            record.startDate = version.startDate
            record.endDate = version.endDate
            record.isPublished = true
            record.publishedData = nil
            record.dmNotes = nil
            // A place whose parent is hidden sits under the nearest parent that isn't.
            var parentID = record.parentID
            while let id = parentID, shown[id] == nil {
                parentID = pages[id]?.parent?.id
            }
            record.parentID = parentID
            records.append(record)
        }
        contents.archive.pages = records
        contents.archive.links = contents.archive.links.filter { shown[$0.sourceID] != nil && shown[$0.targetID] != nil }
        // The maps of places players can't see go with them. The world's own map belongs to the world's own place, which is always shown.
        contents.archive.maps = contents.archive.maps.filter { $0.placeID == nil || shown[$0.placeID!] != nil }
        return contents
    }

    /// The world as its players see it, in a store of its own.
    static func make(for world: World) async throws -> PlayerPreview {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = container.mainContext
        let (copy, _) = await WorldImporter.importWorld(contents(for: world), into: context)
        return PlayerPreview(container: container, world: copy)
    }
}

/// A world made for looking at as a player, and the store it lives in.
final class PlayerPreview {
    let container: ModelContainer
    let world: World

    init(container: ModelContainer, world: World) {
        self.container = container
        self.world = world
    }
}

extension EnvironmentValues {
    /// Set inside the player's view of a world, where nothing is edited and nothing is kept.
    @Entry var isPlayerPreview = false
    /// Opens the player's view of the world that is showing. Nil where there isn't one to open.
    @Entry var startPlayerPreview: (() -> Void)?
}

/// A world's screens, with a way into the player's view of it and back out.
struct WorldRoot: View {
    let world: World
    let onDelete: (World) -> Void

    @State private var preview: PlayerPreview?
    @State private var isBuilding = false
    @State private var failed = false

    var body: some View {
        Group {
            if let preview {
                PlayerWorldView(preview: preview) { self.preview = nil }
            } else {
                WorldShellView(world: world, onDelete: onDelete)
                    .environment(\.startPlayerPreview) { start() }
                    .overlay {
                        if isBuilding {
                            ProgressView("Preparing the player’s view…")
                                .padding()
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .alert("Couldn’t Show the Player’s View", isPresented: $failed) { Button("OK") {} }
            }
        }
    }

    private func start() {
        guard !isBuilding else { return }
        isBuilding = true
        Task {
            defer { isBuilding = false }
            do {
                preview = try await PlayerView.make(for: world)
            } catch {
                failed = true
            }
        }
    }
}

/// The player's view of a world: the ordinary screens on a copy with only what players see, under a bar that says so.
struct PlayerWorldView: View {
    let preview: PlayerPreview
    let onExit: () -> Void

    var body: some View {
        WorldShellView(world: preview.world, onDelete: nil, isPlayerPreview: true)
            .modelContainer(preview.container)
            .environment(\.isPlayerPreview, true)
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Label("Viewing as a player. Nothing here is kept.", systemImage: "person.2")
                        .font(.subheadline)
                    Spacer()
                    Button("Exit", action: onExit)
                        .buttonStyle(.borderedProminent)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.bar)
            }
    }
}
