//
//  ContentEntryTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// A pack can define its own kinds of entry, such as domain cards, with no page kind or code path for each.
@MainActor
struct ContentEntryTests {
    private let cardKind = EntryKindDefinition(id: "made.card", title: "Cards", singularTitle: "Card", systemImage: "rectangle.portrait")
    private let relicKind = EntryKindDefinition(id: "made.relic", title: "Relics", singularTitle: "Relic")

    private func makeLibrary() -> Library {
        let pack = LibraryPack(
            id: "srd51", name: "Made up", edition: "5.1", attribution: "Made up.",
            entries: [
                LibraryEntry(key: "srd51.entry.zeal", kind: .entry, name: "Zeal", summary: "Burn bright.", attributes: ["made.level": .number(2)],
                             entries: [EntryValue(name: "Effect", text: "Do more.")], subKind: "made.card"),
                LibraryEntry(key: "srd51.entry.ward", kind: .entry, name: "Ward", summary: "Block.", subKind: "made.card"),
                LibraryEntry(key: "srd51.entry.orb", kind: .entry, name: "Orb", summary: "Round.", subKind: "made.relic"),
                LibraryEntry(key: "srd51.entry.lost", kind: .entry, name: "Lost", summary: "Of a kind nobody defined.", subKind: "made.none"),
                LibraryEntry(key: "srd51.feat.tough", kind: .feat, name: "Tough", summary: "Hard."),
            ],
            entryKinds: [cardKind, relicKind, EntryKindDefinition(id: "made.empty", title: "Empty", singularTitle: "Empty")]
        )
        return Library(packs: [.srd51: pack])
    }

    @Test func eachOfThePacksKindsGetsItsOwnListAndOnlyIfItHasEntries() {
        let library = makeLibrary()
        let lists = library.lists(in: .srd51)
        #expect(lists == [LibraryList(.feat), LibraryList(.entry, subKind: "made.card"), LibraryList(.entry, subKind: "made.relic")])
        #expect(library.topLevelEntries(in: LibraryList(.entry, subKind: "made.card"), edition: .srd51).map(\.name) == ["Ward", "Zeal"])
        #expect(library.topLevelEntries(in: LibraryList(.entry, subKind: "made.relic"), edition: .srd51).map(\.name) == ["Orb"])
        #expect(library.topLevelEntries(in: LibraryList(.feat), edition: .srd51).map(\.name) == ["Tough"])
    }

    @Test func listsTakeTheirTitleAndIconFromThePack() {
        let library = makeLibrary()
        let cards = LibraryList(.entry, subKind: "made.card")
        #expect(String(localized: library.title(of: cards, in: .srd51)) == "Cards")
        #expect(library.systemImage(of: cards, in: .srd51) == "rectangle.portrait")
        #expect(library.systemImage(of: LibraryList(.entry, subKind: "made.relic"), in: .srd51) == "doc.text")
        // A kind nobody defined falls back to the general heading.
        #expect(String(localized: library.title(of: LibraryList(.entry, subKind: "made.none"), in: .srd51)) == "Entries")
        #expect(String(localized: library.title(of: LibraryList(.feat), in: .srd51)) == "Feats")
        #expect(LibraryList(of: library.entry(forKey: "srd51.entry.orb")!) == LibraryList(.entry, subKind: "made.relic"))
    }

    @Test func aCustomVersionIsAContentEntryThatRemembersItsKind() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        context.insert(world)
        let library = makeLibrary()
        let zeal = try #require(library.entry(forKey: "srd51.entry.zeal"))

        let page = try #require(library.makeCustomVersion(of: zeal, in: world, context: context))

        #expect(page.kind == .contentEntry && page.title == "Zeal" && page.basedOnKey == zeal.key)
        #expect(page.attributes[CoreAttributes.entryKindKey] == .text("made.card"))
        #expect(page.attributes["made.level"] == .number(2))
        #expect(page.attributes[CoreAttributes.detailsKey] == .entries([EntryValue(name: "Effect", text: "Do more.")]))
        let keys = RuleSystems.definitions(for: .contentEntry, system: .none).map(\.key)
        #expect(keys.contains(CoreAttributes.entryKindKey) && keys.contains(CoreAttributes.detailsKey))
    }

    @Test func aPackWithEntryKindsIsReadFromJSON() throws {
        let json = """
        {"formatVersion":1,"id":"srd51","name":"N","edition":"5.1","attribution":"A",
         "entryKinds":[{"id":"x.card","title":"Cards"}],
         "entries":[{"key":"srd51.entry.a","kind":"entry","subKind":"x.card","name":"A"}]}
        """
        let pack = try JSONDecoder().decode(LibraryPack.self, from: Data(json.utf8))
        #expect(pack.entryKinds == [EntryKindDefinition(id: "x.card", title: "Cards", singularTitle: "Cards")])
        #expect(pack.entries.first?.subKind == "x.card" && pack.entries.first?.kind == .entry)
        // The bundled packs have none, and are unchanged.
        let bundled = try #require(Library.shared.pack(for: .srd51))
        #expect(bundled.entryKinds.isEmpty && !bundled.entries.contains { $0.kind == .entry })
        #expect(Library.shared.lists(in: .srd51).allSatisfy { $0.kind != .entry })
    }

    @Test func aContentEntryPageIsInTheSidebarOnlyWhenTheWorldHasThem() {
        #expect(PageKind.contentEntry.isConditional)
        #expect(DnD5eSystem().additionalPageKinds.contains(.contentEntry) == false)
    }
}
