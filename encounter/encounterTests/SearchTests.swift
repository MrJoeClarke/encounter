//
//  SearchTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct SearchTests {
    private func makeWorld(system: RuleSystemID = .none) throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test", system: system)
        context.insert(world)
        return (world, context)
    }

    @discardableResult
    private func add(_ title: String, _ kind: PageKind = .place, in world: World, _ context: ModelContext,
                     summary: String = "", notes: String = "", tags: [String] = []) -> Page {
        let page = world.addPage(kind: kind, in: context)
        page.title = title
        page.summary = summary
        page.tags = tags
        if !notes.isEmpty {
            page.body = AttributedString(notes)
            page.updateSearchText()
        }
        return page
    }

    private func titles(_ query: String, _ world: World, _ context: ModelContext, scope: SearchScope = .all) -> [String] {
        WorldSearch.search(query, in: world, scope: scope, context: context).map(\.title)
    }

    // MARK: Plain text of the notes

    @Test func plainTextHasMentionsAsTheirTitlesAndNoFormatting() throws {
        let (world, context) = try makeWorld()
        let elf = add("Elf", .race, in: world, context)
        let page = add("Aria", .character, in: world, context)
        page.body = AttributedString("See ") + Mention.mention(title: elf.title, pageID: elf.id) + AttributedString(" for details")
        page.updateSearchText()
        #expect(page.bodyText == "See Elf for details")

        page.body = AttributedString()
        page.updateSearchText()
        #expect(page.bodyText == "")
    }

    @Test func plainTextSurvivesSavingAndReloading() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let world = World(name: "Test")
        context.insert(world)
        add("Saltmarch", in: world, context, notes: "A foggy harbour town")
        try context.save()

        let loaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Page>()).first)
        #expect(loaded.bodyText == "A foggy harbour town")
    }

    @Test func notesWrittenBeforePlainTextWasKeptAreFilledIn() throws {
        let (world, context) = try makeWorld()
        let old = add("Old", in: world, context)
        old.body = AttributedString("harbour lights")   // as if saved by an older version
        let empty = add("Empty", in: world, context)
        #expect(old.bodyText.isEmpty)

        Page.backfillSearchText(in: context)
        #expect(old.bodyText == "harbour lights")
        #expect(empty.bodyText.isEmpty)
    }

    @Test func plainTextFollowsEveryWayTheNotesChange() async throws {
        let (world, context) = try makeWorld()
        let target = add("Elf", .race, in: world, context)
        let source = add("Aria", .character, in: world, context)
        source.body = AttributedString("Born ") + Mention.mention(title: "Elf", pageID: target.id)
        source.updateSearchText()
        MentionSync.sync(source, in: context)
        try context.save()

        // Renaming the page updates the mention's text in other pages.
        target.title = "Elven"
        MentionSync.refreshMentions(of: target)
        #expect(source.bodyText == "Born Elven")

        // Deleting it turns the mention into plain text, still readable.
        MentionSync.delete(target, in: context)
        #expect(source.bodyText == "Born Elven")

        // A spell's custom version holds its description in the notes.
        let spell = try #require(Library.shared.allEntries(in: .srd52).first { $0.kind == .spell })
        let custom = try #require(Library.shared.makeCustomVersion(of: spell, in: world, context: context))
        #expect(!custom.bodyText.isEmpty)
        #expect(custom.bodyText == String(custom.body.characters))

        // Import rebuilds it.
        let contents = WorldExporter.makeContents(of: world)
        let target2 = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target2)
        for page in imported.pages ?? [] {
            #expect(page.bodyText == String(page.body.characters))
        }
    }

    // MARK: Finding and ranking

    @Test func aSearchFindsTitlesSummariesTagsAndNotes() throws {
        let (world, context) = try makeWorld()
        add("Harbour", in: world, context)
        add("Lighthouse", in: world, context, summary: "Guards the harbour mouth")
        add("Tidewatch", .organisation, in: world, context, tags: ["Harbour Guild"])
        add("Fogbell", .item, in: world, context, notes: "Rung when fog hides the harbour.")
        add("Mountain", in: world, context, notes: "Cold and distant.")

        #expect(Set(titles("harbour", world, context)) == ["Harbour", "Lighthouse", "Tidewatch", "Fogbell"])
        #expect(titles("zzz", world, context).isEmpty)
        #expect(titles("   ", world, context).isEmpty)
    }

    @Test func titlesRankAboveTagsSummariesAndNotes() throws {
        let (world, context) = try makeWorld()
        add("Cold Notes", in: world, context, notes: "the harbour")
        add("Cold Summary", in: world, context, summary: "the harbour")
        add("Cold Tag", in: world, context, tags: ["harbour"])
        add("Old Harbour", in: world, context)
        add("Harbour Road", in: world, context)
        add("Harbour", in: world, context)
        add("Seaharbourside", in: world, context)

        #expect(titles("harbour", world, context) == [
            "Harbour", "Harbour Road", "Old Harbour", "Seaharbourside", "Cold Tag", "Cold Summary", "Cold Notes",
        ])
    }

    @Test func everyWordMustMatchButNotInTheSameField() throws {
        let (world, context) = try makeWorld()
        add("Saltmarch", in: world, context, summary: "A harbour town", notes: "Home of the fog bell")
        add("Saltpan", in: world, context, summary: "A flat")

        #expect(titles("salt harbour", world, context) == ["Saltmarch"])
        #expect(titles("harbour fog", world, context) == ["Saltmarch"])
        #expect(titles("salt dragon", world, context).isEmpty)
    }

    @Test func caseAndAccentsAreIgnored() throws {
        let (world, context) = try makeWorld()
        add("Café Noir", in: world, context)
        add("Tavern", in: world, context, notes: "Serves ÉCLAIRS")

        #expect(titles("cafe", world, context) == ["Café Noir"])
        #expect(titles("eclairs", world, context) == ["Tavern"])
    }

    @Test func aMentionMakesAPageFindableByTheMentionedTitle() throws {
        let (world, context) = try makeWorld()
        let elf = add("Elf", .race, in: world, context)
        let aria = add("Aria", .character, in: world, context)
        aria.body = AttributedString("Born ") + Mention.mention(title: "Elf", pageID: elf.id)
        aria.updateSearchText()

        #expect(titles("elf", world, context) == ["Elf", "Aria"])
    }

    @Test func aScopeNarrowsTheResults() throws {
        let (world, context) = try makeWorld()
        add("Harbour", .place, in: world, context)
        add("Harbour Guild", .organisation, in: world, context)

        #expect(titles("harbour", world, context, scope: .kind(.organisation)) == ["Harbour Guild"])
        #expect(titles("harbour", world, context, scope: .kind(.place)) == ["Harbour"])
        #expect(titles("harbour", world, context, scope: .library).isEmpty)
    }

    @Test func otherWorldsAreNeverSearched() throws {
        let (world, context) = try makeWorld()
        let other = World(name: "Other")
        context.insert(other)
        add("Harbour", in: world, context)
        add("Harbour Two", in: other, context)

        #expect(titles("harbour", world, context) == ["Harbour"])
    }

    @Test func aSnippetShowsTheMatchingText() throws {
        let (world, context) = try makeWorld()
        add("Fogbell", .item, in: world, context, notes: "Rung when fog hides the harbour.")
        let hit = try #require(WorldSearch.search("harbour", in: world, context: context).first)
        #expect(hit.field == .notes)
        #expect(hit.snippet == "Rung when fog hides the harbour.")

        let long = String(repeating: "word ", count: 40) + "harbour" + String(repeating: " word", count: 40)
        let snippet = try #require(WorldSearch.snippet(in: long, around: "harbour"))
        #expect(snippet.hasPrefix("…") && snippet.hasSuffix("…") && snippet.contains("harbour"))
        #expect(snippet.count < 130)
    }

    // MARK: Library

    @Test func searchAlsoFindsLibraryEntriesOfTheWorldsEdition() throws {
        let (world, context) = try makeWorld(system: .dnd5e)
        world.edition = .srd52
        add("Fireball Alley", in: world, context)

        let hits = WorldSearch.search("fireball", in: world, context: context)
        let keys = hits.compactMap { hit -> String? in
            if case .library(let entry) = hit.target { entry.key } else { nil }
        }
        #expect(keys.contains("srd52.spell.fireball"))
        #expect(keys.allSatisfy { $0.hasPrefix("srd52.") })
        // The world's own page ranks with the library's, by how well the title matches.
        #expect(hits.contains { if case .page = $0.target { true } else { false } })

        let libraryOnly = WorldSearch.search("fireball", in: world, scope: .library, context: context)
        #expect(libraryOnly.allSatisfy { if case .library = $0.target { true } else { false } })
        #expect(WorldSearch.search("fireball", in: world, scope: .kind(.place), context: context).count == 1)
    }

    @Test func aWorldWithoutALibraryNeverShowsLibraryEntries() throws {
        let (world, context) = try makeWorld(system: .none)
        #expect(titles("fireball", world, context).isEmpty)
    }

    @Test func searchingNavigatesAndClearsTheSearch() throws {
        let (world, context) = try makeWorld()
        let page = add("Harbour", in: world, context)
        let navigation = WorldNavigation()
        navigation.searchText = "harbour"
        navigation.open(page)
        #expect(navigation.searchText.isEmpty)
        #expect(navigation.selectedPage === page)

        navigation.searchText = "x"
        navigation.choose(.home)
        #expect(navigation.searchText.isEmpty)
    }
}
