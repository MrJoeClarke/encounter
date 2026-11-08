//
//  World+Root.swift
//  encounter
//

import Foundation
import SwiftData

extension World {
    /// The place at the top of the world's place hierarchy, named after the world. Every other place is inside it,
    /// and its map is the world map. Nil only for a world made before root places existed, until `ensureRootPlace`.
    var rootPlace: Page? {
        guard let rootPlaceID else { return nil }
        return (pages ?? []).first { $0.id == rootPlaceID && !$0.isDeleted }
    }

    /// The main map of the world: the map of its root place.
    var worldMap: WorldMap? {
        rootPlace?.sortedMaps.first
    }

    /// Makes sure the world has a root place, making one named after the world if it hasn't. A new root place
    /// takes in the places that had no parent, and any world map that had no place. Safe to call again.
    @discardableResult
    func ensureRootPlace(in context: ModelContext) -> Page {
        if let rootPlace { return rootPlace }
        let root = Page(title: name, kind: .place)
        context.insert(root)
        root.world = self
        rootPlaceID = root.id

        for page in pages ?? [] where page !== root && page.kind == .place && page.parent == nil {
            page.parent = root
            page.parentSource = .automatic
        }
        for map in maps ?? [] where map.place == nil && map.kind == .world {
            map.place = root
        }
        return root
    }

    /// Makes every world that never had one have a root place. Cheap when they all do.
    ///
    /// A world that names a root place whose page isn't here is left alone: with iCloud sync the world can arrive before its pages,
    /// and making another root place then would leave it with two.
    @MainActor
    static func ensureRootPlaces(in context: ModelContext) {
        let worlds = (try? context.fetch(FetchDescriptor<World>())) ?? []
        var changed = false
        for world in worlds where world.rootPlaceID == nil {
            world.ensureRootPlace(in: context)
            changed = true
        }
        if changed { try? context.save() }
    }

    /// After the world is renamed, renames the root place too, unless it has been given a name of its own.
    func renameRootPlace(from oldName: String) {
        guard let root = rootPlace, root.title == oldName, !name.isEmpty else { return }
        root.title = name
        MentionSync.refreshMentions(of: root)
        root.updateSearchText()
    }
}

extension Page {
    /// Whether this is the place at the top of its world's hierarchy.
    var isWorldRoot: Bool {
        guard let rootPlaceID = world?.rootPlaceID else { return false }
        return id == rootPlaceID
    }

    /// The maps of this place, oldest first.
    var sortedMaps: [WorldMap] {
        (maps ?? []).filter { !$0.isDeleted }.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
    }
}
