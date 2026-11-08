//
//  ContentListTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct ContentListTests {
    private func makeWorld(system: RuleSystemID = .dnd5e) throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: system)
        world.edition = .srd51
        context.insert(world)
        return (world, context)
    }

    @Test func aSidebarItemOrAPageOrAnEntryNamesItsList() throws {
        let race = ContentList(.kind(.race))
        #expect(race?.pageKind == .race)
        #expect(race?.libraryList == LibraryList(.race))
        #expect(ContentList(.kind(.item))?.libraryList == LibraryList(.equipment))
        #expect(ContentList(.kind(.character)) == nil)
        #expect(ContentList(.home) == nil)
        // Skills and conditions are part of the rule system and have no list.
        #expect(ContentList(.library(LibraryList(.skill))) == nil)
        let skill = try #require(Library.shared.topLevelEntries(.skill, in: .srd51).first)
        #expect(ContentList(entry: skill) == nil)
        let elf = try #require(Library.shared.topLevelEntries(.race, in: .srd51).first)
        #expect(ContentList(entry: elf)?.sidebarItem == .kind(.race))
    }

    @Test func theListsFollowTheEditionAndTheKindsTheWorldUses() throws {
        let (world, _) = try makeWorld()
        let kinds = ContentList.lists(in: world).map(\.pageKind)
        #expect(kinds == [.race, .characterClass, .background, .feat, .spell])

        // Without a rule system there is no library, so only the kinds a world always shows remain.
        let (plain, _) = try makeWorld(system: .none)
        #expect(ContentList.lists(in: plain).map(\.pageKind) == [.race])
    }

    @Test func aMergedListHasThePagesAndTheLibraryEntriesByName() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .race, in: context)
        page.title = "Aardling"
        let list = try #require(ContentList(.kind(.race)))

        let all = ContentLists.rows(in: list, world: world, filter: .all)
        let mine = ContentLists.rows(in: list, world: world, filter: .mine)
        let library = ContentLists.rows(in: list, world: world, filter: .library)
        #expect(mine.count == 1 && mine.first?.name == "Aardling")
        #expect(library.count == Library.shared.topLevelEntries(.race, in: .srd51).count)
        #expect(all.count == mine.count + library.count)
        #expect(all.map(\.name) == all.map(\.name).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test func aCopyAndItsOriginalBothShow() throws {
        let (world, context) = try makeWorld()
        let elf = try #require(Library.shared.topLevelEntries(.race, in: .srd51).first { $0.name == "Elf" })
        let copy = world.addPage(kind: .race, in: context)
        copy.title = "Elf"
        copy.basedOnKey = elf.key
        let list = try #require(ContentList(.kind(.race)))
        let names = ContentLists.rows(in: list, world: world, filter: .all).map(\.name).filter { $0 == "Elf" }
        #expect(names.count == 2)
    }

    @Test func onlyTheListOfItemsCanBeFilteredToThoseInUse() throws {
        let (world, _) = try makeWorld()
        #expect(ContentList(.kind(.item))?.filters(in: world) == [.all, .mine, .library, .active])
        #expect(ContentList(.kind(.race))?.filters(in: world) == [.all, .mine, .library])

        let (plain, _) = try makeWorld(system: .none)
        // A world with no library has nothing to filter between.
        #expect(ContentList(.kind(.race))?.filters(in: plain) == [])
    }

    @Test func anItemIsInUseWhenACharacterListsItOrLinksToIt() throws {
        let (world, context) = try makeWorld()
        let hero = world.addPage(kind: .character, in: context)
        hero.attributes["dnd5e.equipment"] = .entries([EntryValue(name: "Longsword", text: "")])
        let sword = world.addPage(kind: .item, in: context)
        sword.title = "Moonblade"
        let spare = world.addPage(kind: .item, in: context)
        spare.title = "Rusty Key"
        context.insert(PageLink(source: hero, target: sword, role: LinkRole.mention))

        let list = try #require(ContentList(.kind(.item)))
        let active = ContentLists.rows(in: list, world: world, filter: .active).map(\.name)
        #expect(active.contains("Longsword"))
        #expect(active.contains("Moonblade"))
        #expect(!active.contains("Rusty Key"))
        #expect(!active.contains("Dagger"))
    }

    @Test func openingAnEntryOrAPageShowsItsMergedList() throws {
        let (world, context) = try makeWorld()
        let navigation = WorldNavigation()
        let elf = try #require(Library.shared.topLevelEntries(.race, in: .srd51).first { $0.name == "Elf" })
        navigation.openLibraryEntry(elf)
        #expect(navigation.selection == .kind(.race) && navigation.selectedLibraryKey == elf.key)

        let page = world.addPage(kind: .characterClass, in: context)
        navigation.open(page)
        #expect(navigation.selection == .kind(.characterClass))
        #expect(navigation.selectedPage === page && navigation.selectedLibraryKey == nil)

        // Choosing the list again returns to it.
        navigation.chooseAgain(.kind(.characterClass))
        #expect(navigation.selectedPage == nil && navigation.selectedLibraryKey == nil)
    }
}
