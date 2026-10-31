//
//  Library.swift
//  encounter
//

import Foundation
import SwiftData

/// The bundled, read-only content library: one pack per edition.
///
/// Worlds don't store this content. They refer to entries by key, so an update to a pack reaches every world.
final class Library {
    static let shared = Library()

    private var packs: [LibraryEdition: LibraryPack] = [:]
    private var attemptedEditions: Set<LibraryEdition> = []
    private let isPreloaded: Bool

    /// Loads packs from the app bundle as they're first needed.
    private init() {
        isPreloaded = false
    }

    /// A library holding only the given packs, for tests and previews.
    init(packs: [LibraryEdition: LibraryPack]) {
        self.packs = packs
        isPreloaded = true
    }

    func pack(for edition: LibraryEdition) -> LibraryPack? {
        if let pack = packs[edition] { return pack }
        guard !isPreloaded, attemptedEditions.insert(edition).inserted else { return nil }
        guard let url = Bundle(for: LibraryBundleToken.self).url(forResource: edition.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let pack = Self.decodePack(from: data)
        else { return nil }
        packs[edition] = pack
        return pack
    }

    /// Reads a pack. Returns nil if it can't be read, or was written for a newer version of the app.
    static func decodePack(from data: Data) -> LibraryPack? {
        guard let pack = try? JSONDecoder().decode(LibraryPack.self, from: data),
              pack.formatVersion <= LibraryPack.supportedFormatVersion
        else { return nil }
        return pack
    }

    /// Every entry of a list's kind in an edition, subraces and subclasses included, sorted by name.
    func entries(_ kind: LibraryKind, in edition: LibraryEdition) -> [LibraryEntry] {
        (pack(for: edition)?.entries ?? [])
            .filter { $0.kind.listKind == kind }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The entries of a list that don't belong to another entry: races and classes, without their children.
    func topLevelEntries(_ kind: LibraryKind, in edition: LibraryEdition) -> [LibraryEntry] {
        entries(kind, in: edition).filter { $0.parent == nil }
    }

    /// The lists to show in the Library for an edition: those that have entries, in order.
    func listKinds(in edition: LibraryEdition) -> [LibraryKind] {
        LibraryKind.listKinds.filter { !topLevelEntries($0, in: edition).isEmpty }
    }

    /// The subraces of a race or subclasses of a class.
    func children(of entry: LibraryEntry, in edition: LibraryEdition) -> [LibraryEntry] {
        (pack(for: edition)?.entries ?? [])
            .filter { $0.parent == entry.key }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The entry with the key, from any edition. Keys include the pack they belong to, so they're unique across packs.
    func entry(forKey key: String) -> LibraryEntry? {
        for edition in LibraryEdition.allCases {
            if let entry = pack(for: edition)?.entries.first(where: { $0.key == key }) {
                return entry
            }
        }
        return nil
    }

    /// Entries of any kind whose name matches the search, for mentioning from notes. An empty search matches all.
    func mentionableEntries(matching search: String, in edition: LibraryEdition, limit: Int) -> [LibraryEntry] {
        let matches = (pack(for: edition)?.entries ?? []).filter { search.isEmpty || $0.name.localizedStandardContains(search) }
        return Array(
            matches
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(limit)
        )
    }

    func attribution(for edition: LibraryEdition) -> String? {
        pack(for: edition)?.attribution
    }
}

/// Lets `Library` find the bundle that holds the packs, whether it's running in the app or in tests hosted by it.
private final class LibraryBundleToken {}

// MARK: Create Custom Version

extension Library {
    /// Makes an editable page in the world from a library entry, a variant to change as the creator likes.
    ///
    /// A subrace becomes a complete race: the parent's attributes and traits, then its own. A class includes the
    /// features of its subclasses, each named after its subclass. The page remembers the entry it came from.
    /// Subclasses can't be copied on their own. Returns nil for them.
    @discardableResult
    func makeCustomVersion(of entry: LibraryEntry, in world: World, context: ModelContext) -> Page? {
        guard let pageKind = entry.kind.pageKind else { return nil }
        // The entry's own edition, which may differ from the world's if it was chosen before the edition changed.
        let edition = LibraryEdition(key: entry.key) ?? world.edition

        var attributes: [String: AttributeValue] = [:]
        var entries: [EntryValue] = []

        switch entry.kind {
        case .race:
            if let parentKey = entry.parent, let parent = self.entry(forKey: parentKey) {
                attributes.merge(parent.attributes) { $1 }
                entries += parent.entries
            }
            attributes.merge(entry.attributes) { $1 }
            entries += entry.entries
        case .class:
            attributes = entry.attributes
            entries = entry.entries
            for subclass in children(of: entry, in: edition) {
                entries += subclass.entries.map { feature in
                    EntryValue(name: "\(subclass.name): \(feature.name)", level: feature.level, text: feature.text)
                }
            }
        case .background, .feat:
            attributes = entry.attributes
            entries = entry.entries
        case .subclass, .skill, .equipment, .spell:
            return nil
        }

        let page = Page(title: entry.name, kind: pageKind, summary: entry.summary)
        context.insert(page)
        page.world = world
        page.basedOnKey = entry.key
        if !entries.isEmpty {
            attributes[entriesKey(for: pageKind)] = .entries(entries)
        }
        page.attributes = attributes
        return page
    }

    /// The attribute that holds a kind's traits or features.
    private func entriesKey(for kind: PageKind) -> String {
        switch kind {
        case .characterClass: CoreAttributes.featuresKey
        case .background, .feat: CoreAttributes.detailsKey
        default: CoreAttributes.traitsKey
        }
    }
}


extension LibraryEntry {
    /// What to call this entry: a class, subclass, subrace, or the edition's word for a race or species.
    var kindTitle: LocalizedStringResource {
        let edition = LibraryEdition(key: key) ?? .default
        switch kind {
        case .race: return parent == nil ? edition.raceTermSingular : "Subrace"
        case .class: return "Class"
        case .subclass: return "Subclass"
        case .skill: return "Skill"
        case .background: return "Background"
        case .feat: return "Feat"
        case .equipment: return "Equipment"
        case .spell: return "Spell"
        }
    }
}
