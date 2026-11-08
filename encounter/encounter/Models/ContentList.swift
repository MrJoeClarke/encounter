//
//  ContentList.swift
//  encounter
//

import Foundation
import SwiftData

/// Which rows of a merged list show: the world's own pages, the library's entries, or both.
enum ContentFilter: String, CaseIterable, Identifiable {
    case all
    case mine
    case library
    /// Items some character is using. Only the list of items has it.
    case active

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .all: "All Content"
        case .mine: "My Content"
        case .library: "Library"
        case .active: "In Use"
        }
    }
}

/// A list that mixes the world's own pages with the library's entries of the same kind: races, classes, items and the rest.
/// The sidebar names it by the page kind (`.kind`), or, for a kind of entry a rule system defines itself, by the library list (`.library`).
struct ContentList: Hashable {
    var pageKind: PageKind
    var libraryList: LibraryList

    /// The kinds that are merged with the library under their own page kind.
    static let kinds: [PageKind] = [.race, .characterClass, .background, .feat, .spell]

    /// The list the sidebar item shows, if it is one that mixes pages and the library.
    init?(_ item: WorldSidebarItem) {
        switch item {
        case .kind(let kind):
            guard let list = Self.libraryList(for: kind) else { return nil }
            self.init(pageKind: kind, libraryList: list)
        case .library(let list):
            guard list.kind == .entry else { return nil }
            self.init(pageKind: .contentEntry, libraryList: list)
        default:
            return nil
        }
    }

    init(pageKind: PageKind, libraryList: LibraryList) {
        self.pageKind = pageKind
        self.libraryList = libraryList
    }

    /// The list an entry of the library belongs to. Skills and conditions have none: they are part of the rule system.
    init?(entry: LibraryEntry) {
        let list = LibraryList(of: entry)
        switch list.kind {
        case .skill, .condition: return nil
        case .entry: self.init(pageKind: .contentEntry, libraryList: list)
        default:
            guard let kind = list.kind.pageKind else { return nil }
            self.init(pageKind: kind, libraryList: list)
        }
    }

    /// The list a page belongs to, if it is a page of a kind that is merged with the library.
    init?(page: Page) {
        if page.kind == .contentEntry {
            self.init(pageKind: .contentEntry, libraryList: LibraryList(.entry, subKind: page.entryKindID))
        } else if let list = Self.libraryList(for: page.kind) {
            self.init(pageKind: page.kind, libraryList: list)
        } else {
            return nil
        }
    }

    private static func libraryList(for kind: PageKind) -> LibraryList? {
        switch kind {
        case .race: LibraryList(.race)
        case .characterClass: LibraryList(.class)
        case .background: LibraryList(.background)
        case .feat: LibraryList(.feat)
        case .spell: LibraryList(.spell)
        case .item: LibraryList(.equipment)
        default: nil
        }
    }

    /// The sidebar item that shows this list.
    var sidebarItem: WorldSidebarItem {
        pageKind == .contentEntry ? .library(libraryList) : .kind(pageKind)
    }

    /// Whether this is the list of items, which can be filtered to those in use.
    var isItems: Bool { pageKind == .item }

    /// A name for this list that is safe to use in a stored key.
    var storageKey: String {
        pageKind == .contentEntry ? "entry.\(libraryList.subKind ?? "all")" : pageKind.rawValue
    }

    func title(in world: World) -> LocalizedStringResource {
        if pageKind == .item { return PageKind.item.title }
        if world.rules.contains(.library), pageKind != .contentEntry || libraryList.subKind != nil {
            return Library.shared.title(of: libraryList, in: world.edition)
        }
        return pageKind.title
    }

    func systemImage(in world: World) -> String {
        pageKind == .contentEntry && libraryList.subKind != nil
            ? Library.shared.systemImage(of: libraryList, in: world.edition)
            : pageKind.systemImage
    }

    // MARK: Which lists a world shows

    /// The lists of the Library group, in order: each kind of rules content the world uses or has pages of, then the system's own kinds of entry.
    @MainActor
    static func lists(in world: World) -> [ContentList] {
        let hasLibrary = world.rules.contains(.library)
        let visible = Set(world.visibleKinds)
        var result: [ContentList] = []
        for kind in kinds {
            guard let list = libraryList(for: kind) else { continue }
            let hasEntries = hasLibrary && !Library.shared.topLevelEntries(in: list, edition: world.edition).isEmpty
            if hasEntries || visible.contains(kind) { result.append(ContentList(pageKind: kind, libraryList: list)) }
        }
        var covered = Set<String>()
        if hasLibrary {
            for list in Library.shared.lists(in: world.edition) where list.kind == .entry {
                result.append(ContentList(pageKind: .contentEntry, libraryList: list))
                if let subKind = list.subKind { covered.insert(subKind) }
            }
        }
        // Entries the world made of a kind the library doesn't list stay together in one list of their own.
        let strays = (world.pages ?? []).filter { $0.kind == .contentEntry && !$0.isDeleted && !covered.contains($0.entryKindID ?? "") }
        if !strays.isEmpty || (visible.contains(.contentEntry) && covered.isEmpty) {
            result.append(ContentList(pageKind: .contentEntry, libraryList: LibraryList(.entry, subKind: nil)))
        }
        return result
    }

    /// The filters this list offers: all, then the world's own and the library's where the library has entries of the kind.
    @MainActor
    func filters(in world: World) -> [ContentFilter] {
        var result: [ContentFilter] = [.all]
        let hasLibraryEntries = world.rules.contains(.library) && !Library.shared.topLevelEntries(in: libraryList, edition: world.edition).isEmpty
        if hasLibraryEntries { result += [.mine, .library] }
        if isItems { result.append(.active) }
        return result.count == 1 ? [] : result
    }
}

extension Page {
    /// Which kind of entry of its rule system a content entry is, such as "daggerheart.domainCard".
    var entryKindID: String? {
        let text = attributeText(CoreAttributes.entryKindKey)
        return text.isEmpty ? nil : text
    }
}

/// One row of a merged list: a page of the world or an entry of the library.
enum ContentRow: Identifiable {
    case page(Page)
    case library(LibraryEntry)

    var id: String {
        switch self {
        case .page(let page): "page-\(page.id.uuidString)"
        case .library(let entry): "library-\(entry.key)"
        }
    }

    var name: String {
        switch self {
        case .page(let page): page.title
        case .library(let entry): entry.name
        }
    }

    /// The row's id for a page or an entry, so a selection can be matched with it.
    static func id(page: Page) -> String { "page-\(page.id.uuidString)" }
    static func id(libraryKey: String) -> String { "library-\(libraryKey)" }
}

/// The rows of a merged list, and the items some character is using.
@MainActor
enum ContentLists {
    /// The rows of the list that the filter lets through, by name.
    static func rows(in list: ContentList, world: World, filter: ContentFilter) -> [ContentRow] {
        var rows: [ContentRow] = []
        if filter != .library {
            let pages = (world.pages ?? []).filter { page in
                guard page.kind == list.pageKind, !page.isDeleted else { return false }
                return list.pageKind != .contentEntry || list.libraryList.subKind == nil || page.entryKindID == list.libraryList.subKind
            }
            rows += pages.map { .page($0) }
        }
        if filter != .mine, world.rules.contains(.library) {
            rows += Library.shared.topLevelEntries(in: list.libraryList, edition: world.edition).map { .library($0) }
        }
        if filter == .active {
            let usage = ItemUsage(world: world)
            rows = rows.filter { row in
                switch row {
                case .page(let page): usage.isInUse(page)
                case .library(let entry): usage.isInUse(named: entry.name)
                }
            }
        }
        return rows.sorted {
            let order = $0.name.localizedStandardCompare($1.name)
            return order == .orderedSame ? $0.id < $1.id : order == .orderedAscending
        }
    }

    /// How many rows the list has with nothing filtered out, for the sidebar.
    static func count(in list: ContentList, world: World) -> Int {
        rows(in: list, world: world, filter: .all).count
    }
}

/// Which items the world's characters are using: those on a character's equipment, and item pages a character links to.
@MainActor
struct ItemUsage {
    private var names: Set<String> = []
    private var linkedIDs: Set<UUID> = []

    init(world: World) {
        for character in (world.pages ?? []) where character.kind == .character && !character.isDeleted {
            for (key, value) in character.attributes {
                let lowered = key.lowercased()
                guard lowered.contains("equipment") || lowered.contains("inventory"), case .entries(let entries) = value else { continue }
                for entry in entries { names.insert(Self.normalised(entry.name)) }
            }
            for link in character.outgoingLinks ?? [] where !link.isDeleted {
                if let target = link.target, target.kind == .item { linkedIDs.insert(target.id) }
            }
        }
    }

    func isInUse(_ page: Page) -> Bool {
        linkedIDs.contains(page.id) || names.contains(Self.normalised(page.title))
    }

    func isInUse(named name: String) -> Bool {
        names.contains(Self.normalised(name))
    }

    private static func normalised(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
