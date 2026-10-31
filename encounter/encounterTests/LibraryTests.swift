//
//  LibraryTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
import SwiftUI
@testable import encounter

@MainActor
struct LibraryTests {
    // MARK: Helpers

    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.makeContainer(inMemory: true))
    }

    /// A small library with a race, a subrace, a class and a subclass, in the 5.1 pack.
    private func makeLibrary() -> Library {
        let pack = LibraryPack(
            id: "srd51",
            name: "Test",
            edition: "5.1",
            attribution: "Attribution",
            entries: [
                LibraryEntry(
                    key: "srd51.race.dwarf", kind: .race, name: "Dwarf", summary: "Sturdy.",
                    attributes: ["core.raceSize": .text("Medium"), "dnd5e.speed": .text("25 feet")],
                    entries: [EntryValue(name: "Darkvision", text: "See in the dark.")]
                ),
                LibraryEntry(
                    key: "srd51.race.hill-dwarf", kind: .race, name: "Hill Dwarf", parent: "srd51.race.dwarf",
                    attributes: ["dnd5e.speed": .text("30 feet")],
                    entries: [EntryValue(name: "Toughness", text: "More hit points.")]
                ),
                LibraryEntry(
                    key: "srd51.race.elf", kind: .race, name: "Elf",
                    entries: [EntryValue(name: "Fey Ancestry", text: "Resist charm.")]
                ),
                LibraryEntry(
                    key: "srd51.class.fighter", kind: .class, name: "Fighter", summary: "A warrior.",
                    attributes: ["dnd5e.hitDie": .text("d10")],
                    entries: [
                        EntryValue(name: "Second Wind", level: 1, text: "Heal."),
                        EntryValue(name: "Action Surge", level: 2, text: "Extra action."),
                    ]
                ),
                LibraryEntry(
                    key: "srd51.subclass.champion", kind: .subclass, name: "Champion", parent: "srd51.class.fighter",
                    entries: [EntryValue(name: "Improved Critical", level: 3, text: "Crit on 19.")]
                ),
            ]
        )
        return Library(packs: [.srd51: pack])
    }

    private func makeWorld(in context: ModelContext, edition: LibraryEdition = .srd51) -> World {
        let world = World(name: "W", system: .dnd5e)
        world.edition = edition
        context.insert(world)
        return world
    }

    private func decode(_ json: String) throws -> LibraryPack {
        try JSONDecoder().decode(LibraryPack.self, from: Data(json.utf8))
    }

    // MARK: Pack format

    @Test func aPackDecodesEntriesWithAllValueTypes() throws {
        let pack = try decode("""
        { "formatVersion": 1, "id": "p", "name": "P", "edition": "E", "attribution": "A",
          "entries": [
            { "key": "p.race.x", "kind": "race", "name": "X", "summary": "S",
              "attributes": { "text": "t", "number": 3, "flag": true, "list": ["a", "b"] },
              "entries": [ { "name": "N", "level": 2, "text": "T" } ] }
          ] }
        """)

        let entry = try #require(pack.entries.first)
        #expect(entry.key == "p.race.x")
        #expect(entry.kind == .race)
        #expect(entry.summary == "S")
        #expect(entry.attributes["text"] == .text("t"))
        #expect(entry.attributes["number"] == .number(3))
        #expect(entry.attributes["flag"] == .bool(true))
        #expect(entry.attributes["list"] == .list(["a", "b"]))
        #expect(entry.entries == [EntryValue(name: "N", level: 2, text: "T")])
    }

    @Test func missingOptionalPartsDefaultToEmpty() throws {
        let pack = try decode("""
        { "formatVersion": 1, "id": "p", "name": "P", "edition": "E", "attribution": "A",
          "entries": [ { "key": "p.class.x", "kind": "class", "name": "X" } ] }
        """)

        let entry = try #require(pack.entries.first)
        #expect(entry.summary.isEmpty)
        #expect(entry.attributes.isEmpty)
        #expect(entry.entries.isEmpty)
        #expect(entry.parent == nil)
    }

    @Test func anEntryOfAnUnknownKindOrMissingAFieldIsSkippedAndTheRestLoad() throws {
        let pack = try decode("""
        { "formatVersion": 1, "id": "p", "name": "P", "edition": "E", "attribution": "A",
          "entries": [
            { "key": "p.race.a", "kind": "race", "name": "A" },
            { "key": "p.vehicle.b", "kind": "vehicle", "name": "B" },
            { "key": "p.race.c", "kind": "race" },
            { "key": "p.race.d", "kind": "race", "name": "D" }
          ] }
        """)

        #expect(pack.entries.map(\.key) == ["p.race.a", "p.race.d"])
    }

    @Test func aPackWithoutAnAttributionIsRejected() {
        let json = #"{ "formatVersion": 1, "id": "p", "name": "P", "edition": "E", "entries": [] }"#
        #expect(throws: DecodingError.self) { try decode(json) }
    }

    @Test func aPackFromANewerVersionOfTheAppIsNotLoaded() {
        let json = #"{ "formatVersion": 99, "id": "p", "name": "P", "edition": "E", "attribution": "A", "entries": [] }"#
        #expect(Library.decodePack(from: Data(json.utf8)) == nil)

        let current = #"{ "formatVersion": 1, "id": "p", "name": "P", "edition": "E", "attribution": "A", "entries": [] }"#
        #expect(Library.decodePack(from: Data(current.utf8)) != nil)
        #expect(Library.decodePack(from: Data("not json".utf8)) == nil)
    }

    // MARK: Bundled packs

    /// The statements the licence requires, exactly as printed on page 1 of each official document.
    private let attribution51 = "This work includes material taken from the System Reference Document 5.1 (“SRD 5.1”) by Wizards of the Coast LLC and available at https://dnd.wizards.com/resources/systems-reference-document. The SRD 5.1 is licensed under the Creative Commons Attribution 4.0 International License available at https://creativecommons.org/licenses/by/4.0/legalcode."
    private let attribution52 = "This work includes material from the System Reference Document 5.2.1 (“SRD 5.2.1”) by Wizards of the Coast LLC, available at https://www.dndbeyond.com/srd. The SRD 5.2.1 is licensed under the Creative Commons Attribution 4.0 International License, available at https://creativecommons.org/licenses/by/4.0/legalcode."

    @Test func bothBundledPacksLoadWithTheExactAttributionTheLicenceRequires() throws {
        let library = Library.shared
        let pack51 = try #require(library.pack(for: .srd51))
        let pack52 = try #require(library.pack(for: .srd52))

        #expect(pack51.id == "srd51")
        #expect(pack52.id == "srd52")
        #expect(pack51.attribution == attribution51)
        #expect(pack52.attribution == attribution52)
        #expect(library.attribution(for: .srd51) == attribution51)
    }

    @Test func theBundledPacksAreInternallyConsistent() throws {
        for edition in LibraryEdition.allCases {
            let pack = try #require(Library.shared.pack(for: edition))
            let keys = pack.entries.map(\.key)

            #expect(!pack.entries.isEmpty, "\(edition) has no entries")
            #expect(Set(keys).count == keys.count, "\(edition) has duplicate keys")
            for entry in pack.entries {
                #expect(entry.key.hasPrefix(edition.rawValue + "."), "\(entry.key) isn't namespaced to \(edition)")
                #expect(!entry.name.isEmpty)

                if let parentKey = entry.parent {
                    let parent = pack.entries.first { $0.key == parentKey }
                    #expect(parent != nil, "\(entry.key) names a parent that doesn't exist")
                    switch entry.kind {
                    case .race: #expect(parent?.kind == .race)
                    case .subclass: #expect(parent?.kind == .class)
                    default: Issue.record("\(entry.key) is a \(entry.kind) with a parent")
                    }
                }
                for feature in entry.entries {
                    #expect(!feature.name.isEmpty, "\(entry.key) has an unnamed entry")
                    #expect(!feature.text.isEmpty, "\(entry.key) / \(feature.name) has no text")
                    switch entry.kind {
                    case .race:
                        #expect(feature.level == nil, "\(entry.key) / \(feature.name) has a level")
                    case .class, .subclass:
                        #expect((1...20).contains(feature.level ?? 0), "\(entry.key) / \(feature.name) needs a level from 1 to 20")
                    case .skill, .background, .feat, .equipment, .spell:
                        break
                    }
                }
            }
        }
    }

    @Test func everyAttributeInTheBundledPacksCanBeShownAndEditedOnACustomVersion() throws {
        // A custom version copies the attributes onto a page, so each must be one the editor has a field for.
        for edition in LibraryEdition.allCases {
            let pack = try #require(Library.shared.pack(for: edition))
            for entry in pack.entries {
                let pageKind = try #require(entry.kind.pageKind ?? .characterClass)
                // Skills and the like have no page to edit, so their attributes only need a label in the library.
                let libraryOnly: Set<String> = ["dnd5e.ability"]
                let known = Set(RuleSystems.definitions(for: pageKind, system: .dnd5e).map(\.key)).union(libraryOnly)
                for key in entry.attributes.keys {
                    #expect(known.contains(key), "\(entry.key) uses \(key), which the editor has no field for")
                }
            }
        }
    }

    @Test func theBundledFighterHasItsFeaturesAtTheRightLevels() throws {
        let fighter51 = try #require(Library.shared.entry(forKey: "srd51.class.fighter"))
        #expect(fighter51.entries.map(\.name) == ["Fighting Style", "Second Wind", "Action Surge", "Martial Archetype", "Ability Score Improvement", "Extra Attack", "Indomitable"])
        #expect(fighter51.entries.map(\.level) == [1, 1, 2, 3, 4, 5, 9])
        #expect(fighter51.attributes["dnd5e.hitDie"] == .text("d10"))

        let fighter52 = try #require(Library.shared.entry(forKey: "srd52.class.fighter"))
        #expect(fighter52.entries.prefix(3).map(\.name) == ["Fighting Style", "Second Wind", "Weapon Mastery"])
        #expect(fighter52.entries.map(\.level).first == 1)
        #expect(fighter52.entries.contains { $0.name == "Fighter Subclass" && $0.level == 3 })
        #expect(fighter52.entries.contains { $0.name == "Three Extra Attacks" && $0.level == 20 })
        #expect(fighter52.attributes["dnd5e.primaryAbility"] == .text("Strength or Dexterity"))
    }

    @Test func srd51HasAllTheRacesAndClassesWithOneSubclassEach() throws {
        let library = Library.shared
        let races = library.topLevelEntries(.race, in: .srd51).map(\.name)
        #expect(Set(races) == ["Dwarf", "Elf", "Halfling", "Human", "Dragonborn", "Gnome", "Half-Elf", "Half-Orc", "Tiefling"])
        let subraces = library.entries(.race, in: .srd51).filter { $0.parent != nil }.map(\.name)
        #expect(Set(subraces) == ["Hill Dwarf", "High Elf", "Lightfoot", "Rock Gnome"])

        let classes = library.topLevelEntries(.class, in: .srd51)
        #expect(Set(classes.map(\.name)) == ["Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk", "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"])
        for entry in classes {
            #expect(library.children(of: entry, in: .srd51).count == 1, "\(entry.name) should have one subclass")
            #expect(["d6", "d8", "d10", "d12"].map { AttributeValue.text($0) }.contains { $0 == entry.attributes["dnd5e.hitDie"] }, "\(entry.name) hit die")
            for key in ["dnd5e.armorProficiencies", "dnd5e.weaponProficiencies", "dnd5e.toolProficiencies", "dnd5e.savingThrows", "dnd5e.skillChoices"] {
                #expect(entry.attributes[key] != nil, "\(entry.name) is missing \(key)")
            }
            #expect(entry.entries.contains { $0.name == "Ability Score Improvement" && $0.level == 4 })
            #expect(entry.entries.allSatisfy { !$0.text.isEmpty })
        }
    }

    @Test func srd52HasAllTheSpeciesAndClassesWithOneSubclassEach() throws {
        let library = Library.shared
        let species = library.topLevelEntries(.race, in: .srd52).map(\.name)
        #expect(Set(species) == ["Dragonborn", "Dwarf", "Elf", "Gnome", "Goliath", "Halfling", "Human", "Orc", "Tiefling"])
        #expect(library.entries(.race, in: .srd52).count == 9)

        let classes = library.topLevelEntries(.class, in: .srd52)
        #expect(Set(classes.map(\.name)) == ["Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk", "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"])
        for entry in classes {
            #expect(library.children(of: entry, in: .srd52).count == 1, "\(entry.name) should have one subclass")
            #expect(["d6", "d8", "d10", "d12"].map { AttributeValue.text($0) }.contains { $0 == entry.attributes["dnd5e.hitDie"] }, "\(entry.name) hit die")
            for key in ["dnd5e.primaryAbility", "dnd5e.savingThrows", "dnd5e.skillChoices", "dnd5e.weaponProficiencies", "dnd5e.armorProficiencies"] {
                #expect(entry.attributes[key] != nil, "\(entry.name) is missing \(key)")
            }
            // Every class gets a subclass at 3, an Ability Score Improvement at 4 and an Epic Boon at 19, except the one that
            // gains Epic Boon as part of a different feature.
            #expect(entry.entries.contains { $0.name.hasSuffix("Subclass") && $0.level == 3 }, "\(entry.name) subclass choice")
            #expect(entry.entries.contains { $0.name == "Ability Score Improvement" && $0.level == 4 })
            #expect(entry.entries.contains { $0.name == "Epic Boon" && $0.level == 19 })
            #expect(entry.entries.allSatisfy { !$0.text.isEmpty })
            #expect(entry.entries.map { $0.level ?? 0 } == entry.entries.map { $0.level ?? 0 }.sorted(), "\(entry.name) features are in level order")
        }
    }

    @Test func theBundledDwarfAndHillDwarfAreLinked() throws {
        let library = Library.shared
        let dwarf = try #require(library.entry(forKey: "srd51.race.dwarf"))
        let hill = try #require(library.entry(forKey: "srd51.race.hill-dwarf"))

        #expect(hill.parent == dwarf.key)
        #expect(library.children(of: dwarf, in: .srd51).map(\.key) == [hill.key])
        #expect(library.topLevelEntries(.race, in: .srd51).contains { $0.key == dwarf.key })
        #expect(!library.topLevelEntries(.race, in: .srd51).contains { $0.key == hill.key })
    }

    // MARK: Editions

    @Test func newWorldsStartOnTheCurrentRulesAndEditionsAreNamedByTheirTerm() {
        #expect(LibraryEdition.default == .srd52)
        #expect(World(name: "W").edition == .srd52)

        #expect(String(localized: LibraryEdition.srd51.raceTermPlural) == "Races")
        #expect(String(localized: LibraryEdition.srd52.raceTermPlural) == "Species")
        #expect(String(localized: LibraryEdition.srd51.raceTermSingular) == "Race")
        #expect(String(localized: LibraryEdition.srd52.raceTermSingular) == "Species")
    }

    @Test func anEditionIsFoundFromAnEntryKey() {
        #expect(LibraryEdition(key: "srd51.race.elf") == .srd51)
        #expect(LibraryEdition(key: "srd52.class.fighter") == .srd52)
        #expect(LibraryEdition(key: "srd5.race.elf") == nil)
        #expect(LibraryEdition(key: "homebrew.race.elf") == nil)
    }

    @Test func aWorldWithAnUnknownEditionFallsBackToTheDefault() {
        let world = World(name: "W")
        world.editionRaw = "srd99"
        #expect(world.edition == .default)
        world.edition = .srd51
        #expect(world.editionRaw == "srd51")
    }

    // MARK: Looking things up

    @Test func entriesAreListedByNameWithSubracesAndSubclassesIncluded() {
        let library = makeLibrary()

        #expect(library.entries(.race, in: .srd51).map(\.name) == ["Dwarf", "Elf", "Hill Dwarf"])
        #expect(library.entries(.class, in: .srd51).map(\.name) == ["Champion", "Fighter"])
        #expect(library.entries(.race, in: .srd52).isEmpty)
    }

    @Test func topLevelEntriesLeaveOutSubracesAndSubclasses() {
        let library = makeLibrary()

        #expect(library.topLevelEntries(.race, in: .srd51).map(\.name) == ["Dwarf", "Elf"])
        #expect(library.topLevelEntries(.class, in: .srd51).map(\.name) == ["Fighter"])
    }

    @Test func childrenBelongToTheirParent() throws {
        let library = makeLibrary()
        let dwarf = try #require(library.entry(forKey: "srd51.race.dwarf"))
        let elf = try #require(library.entry(forKey: "srd51.race.elf"))
        let fighter = try #require(library.entry(forKey: "srd51.class.fighter"))

        #expect(library.children(of: dwarf, in: .srd51).map(\.name) == ["Hill Dwarf"])
        #expect(library.children(of: elf, in: .srd51).isEmpty)
        #expect(library.children(of: fighter, in: .srd51).map(\.name) == ["Champion"])
    }

    @Test func anEntryIsFoundByKeyAndAnUnknownKeyIsNot() {
        let library = makeLibrary()
        #expect(library.entry(forKey: "srd51.race.elf")?.name == "Elf")
        #expect(library.entry(forKey: "srd51.race.nobody") == nil)
        #expect(library.entry(forKey: "") == nil)
    }

    // MARK: Create Custom Version

    @Test func aCustomRaceIsAnEditableCopyThatRemembersItsSource() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let elf = try #require(library.entry(forKey: "srd51.race.elf"))

        let page = try #require(library.makeCustomVersion(of: elf, in: world, context: context))

        #expect(page.kind == .race)
        #expect(page.title == "Elf")
        #expect(page.world === world)
        #expect(page.basedOnKey == "srd51.race.elf")
        #expect(page.attributes[CoreAttributes.traitsKey] == .entries([EntryValue(name: "Fey Ancestry", text: "Resist charm.")]))
        #expect(world.pages?.contains(page) == true)
    }

    @Test func aCustomSubraceIsACompleteRaceWithItsParentsTraitsAndAttributes() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let hill = try #require(library.entry(forKey: "srd51.race.hill-dwarf"))

        let page = try #require(library.makeCustomVersion(of: hill, in: world, context: context))

        #expect(page.title == "Hill Dwarf")
        #expect(page.basedOnKey == "srd51.race.hill-dwarf")
        // The parent's attributes come first and the subrace's override them.
        #expect(page.attributeText("core.raceSize") == "Medium")
        #expect(page.attributeText("dnd5e.speed") == "30 feet")
        // The parent's traits, then the subrace's own.
        guard case .entries(let traits)? = page.attributes[CoreAttributes.traitsKey] else {
            Issue.record("Expected traits")
            return
        }
        #expect(traits.map(\.name) == ["Darkvision", "Toughness"])
    }

    @Test func aCustomClassIncludesTheFeaturesOfItsSubclassesNamedAfterThem() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let fighter = try #require(library.entry(forKey: "srd51.class.fighter"))

        let page = try #require(library.makeCustomVersion(of: fighter, in: world, context: context))

        #expect(page.kind == .characterClass)
        #expect(page.summary == "A warrior.")
        #expect(page.attributeText("dnd5e.hitDie") == "d10")
        guard case .entries(let features)? = page.attributes[CoreAttributes.featuresKey] else {
            Issue.record("Expected features")
            return
        }
        #expect(features.map(\.name) == ["Second Wind", "Action Surge", "Champion: Improved Critical"])
        #expect(features.map(\.level) == [1, 2, 3])
    }

    @Test func aSubclassCantBeCopiedOnItsOwn() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let champion = try #require(library.entry(forKey: "srd51.subclass.champion"))

        #expect(library.makeCustomVersion(of: champion, in: world, context: context) == nil)
        #expect(world.pages?.isEmpty != false)
    }

    @Test func aCustomVersionUsesTheEntrysOwnEditionNotTheWorldsCurrentOne() throws {
        let context = try makeContext()
        // The world has since moved to 5.2.1, but the entry being copied is from 5.1.
        let world = makeWorld(in: context, edition: .srd52)
        let library = makeLibrary()
        let fighter = try #require(library.entry(forKey: "srd51.class.fighter"))

        let page = try #require(library.makeCustomVersion(of: fighter, in: world, context: context))

        guard case .entries(let features)? = page.attributes[CoreAttributes.featuresKey] else {
            Issue.record("Expected features")
            return
        }
        #expect(features.contains { $0.name == "Champion: Improved Critical" })
    }

    @Test func aCustomVersionIsIndependentOfTheLibrary() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let elf = try #require(library.entry(forKey: "srd51.race.elf"))
        let page = try #require(library.makeCustomVersion(of: elf, in: world, context: context))

        page.title = "Moon Elf"
        page.attributes[CoreAttributes.traitsKey] = .entries([EntryValue(name: "Moonlight", text: "Glow.")])

        #expect(library.entry(forKey: "srd51.race.elf")?.name == "Elf")
        #expect(library.entry(forKey: "srd51.race.elf")?.entries.first?.name == "Fey Ancestry")
    }

    @Test func makingTwoCustomVersionsMakesTwoPages() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let elf = try #require(library.entry(forKey: "srd51.race.elf"))

        let first = library.makeCustomVersion(of: elf, in: world, context: context)
        let second = library.makeCustomVersion(of: elf, in: world, context: context)

        #expect(first !== second)
        #expect(world.pages?.count == 2)
    }

    @Test func aCustomVersionSurvivesSavingAndReloading() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let world = makeWorld(in: context)
        let library = makeLibrary()
        let fighter = try #require(library.entry(forKey: "srd51.class.fighter"))
        library.makeCustomVersion(of: fighter, in: world, context: context)
        try context.save()

        let loaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Page>()).first)
        #expect(loaded.kind == .characterClass)
        #expect(loaded.basedOnKey == "srd51.class.fighter")
        guard case .entries(let features)? = loaded.attributes[CoreAttributes.featuresKey] else {
            Issue.record("Expected features after reloading")
            return
        }
        #expect(features.count == 3)
        #expect(features.first == EntryValue(name: "Second Wind", level: 1, text: "Heal."))
    }

    // MARK: References to world pages or library entries

    @Test func aReferenceCanBeAWorldPageOrALibraryEntryButNeverBoth() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let hero = world.addPage(kind: .character, in: context)
        let homebrew = world.addPage(kind: .race, in: context)

        #expect(hero.reference(role: LinkRole.race) == .none)

        hero.setReference(.library("srd51.race.elf"), role: LinkRole.race, in: context)
        #expect(hero.reference(role: LinkRole.race) == .library("srd51.race.elf"))
        #expect(hero.linkedPage(role: LinkRole.race) == nil)

        hero.setReference(.page(homebrew), role: LinkRole.race, in: context)
        #expect(hero.reference(role: LinkRole.race) == .page(homebrew))
        #expect(hero.libraryKey(role: LinkRole.race) == nil)

        hero.setReference(.library("srd51.race.dwarf"), role: LinkRole.race, in: context)
        #expect(hero.reference(role: LinkRole.race) == .library("srd51.race.dwarf"))
        #expect(hero.linkedPage(role: LinkRole.race) == nil)

        hero.setReference(.none, role: LinkRole.race, in: context)
        #expect(hero.reference(role: LinkRole.race) == .none)
        #expect(hero.libraryKey(role: LinkRole.race) == nil)
        #expect(hero.linkedPage(role: LinkRole.race) == nil)
    }

    @Test func raceAndClassReferencesAreIndependent() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let hero = world.addPage(kind: .character, in: context)

        hero.setReference(.library("srd51.race.elf"), role: LinkRole.race, in: context)
        hero.setReference(.library("srd51.class.fighter"), role: LinkRole.characterClass, in: context)
        hero.setReference(.none, role: LinkRole.race, in: context)

        #expect(hero.reference(role: LinkRole.race) == .none)
        #expect(hero.reference(role: LinkRole.characterClass) == .library("srd51.class.fighter"))
    }

    @Test func aLibraryReferenceCreatesNoPageLink() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let hero = world.addPage(kind: .character, in: context)

        hero.setReference(.library("srd51.race.elf"), role: LinkRole.race, in: context)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 0)
    }

    @Test func aLibraryReferenceSurvivesSavingAndReloading() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let world = makeWorld(in: context)
        let hero = world.addPage(kind: .character, in: context)
        hero.setReference(.library("srd52.race.dwarf"), role: LinkRole.race, in: context)
        try context.save()

        let loaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Page>()).first)
        #expect(loaded.reference(role: LinkRole.race) == .library("srd52.race.dwarf"))
    }

    // MARK: Classes in the sidebar and the system

    @Test func theClassesCategoryShowsOnlyWhereTheSystemOrTheWorldNeedsIt() throws {
        let context = try makeContext()
        let plain = World(name: "Plain")
        context.insert(plain)
        #expect(!plain.visibleKinds.contains(.characterClass))
        #expect(plain.visibleKinds.count == PageKind.allCases.count - 1)

        let dnd = World(name: "D&D", system: .dnd5e)
        context.insert(dnd)
        #expect(dnd.visibleKinds.contains(.characterClass))
        #expect(dnd.visibleKinds == PageKind.allCases)
    }

    @Test func aWorldWithClassPagesKeepsShowingThemWhateverTheSystem() throws {
        let context = try makeContext()
        let world = World(name: "W", system: .dnd5e)
        context.insert(world)
        world.addPage(kind: .characterClass, in: context)

        world.system = .none

        #expect(world.visibleKinds.contains(.characterClass))
    }

    @Test func onlyDnDHasALibraryAndClasses() {
        #expect(RuleSystems.system(for: .dnd5e).hasContentLibrary)
        #expect(!RuleSystems.system(for: .none).hasContentLibrary)
        #expect(RuleSystems.system(for: .dnd5e).additionalPageKinds == [.characterClass])
        #expect(RuleSystems.system(for: .none).additionalPageKinds.isEmpty)
    }

    @Test func raceAndClassPagesGetTheirEntryListsAndDnDAttributes() {
        func keys(_ kind: PageKind, _ system: RuleSystemID) -> [String] {
            RuleSystems.definitions(for: kind, system: system).map(\.key)
        }

        #expect(keys(.race, .none).contains(CoreAttributes.traitsKey))
        #expect(keys(.race, .dnd5e).contains(CoreAttributes.traitsKey))
        #expect(keys(.characterClass, .none) == [CoreAttributes.featuresKey])
        for key in ["dnd5e.hitDie", "dnd5e.primaryAbility", "dnd5e.savingThrows", "dnd5e.armorProficiencies",
                    "dnd5e.weaponProficiencies", "dnd5e.toolProficiencies", "dnd5e.skillChoices", CoreAttributes.featuresKey] {
            #expect(keys(.characterClass, .dnd5e).contains(key), "missing \(key)")
        }
        #expect(keys(.character, .dnd5e).contains("core.class"))
        #expect(keys(.character, .dnd5e).contains("dnd5e.classLevel"))
        #expect(!keys(.character, .none).contains("core.class"))
        #expect(keys(.character, .none).contains("core.race"))
    }

    // MARK: Structured entries

    @Test func entriesRoundTripThroughJSON() throws {
        let value = AttributeValue.entries([
            EntryValue(name: "Second Wind", level: 1, text: "Heal."),
            EntryValue(name: "Darkvision", level: nil, text: "See."),
        ])

        let decoded = try JSONDecoder().decode(AttributeValue.self, from: JSONEncoder().encode(value))

        #expect(decoded == value)
    }

    @Test func entriesOnAPageSurviveSavingAndReloading() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let page = Page(title: "Elf", kind: .race)
        context.insert(page)
        page.attributes[CoreAttributes.traitsKey] = .entries([EntryValue(name: "Keen Senses", text: "Perception.")])
        try context.save()

        let loaded = try #require(try ModelContext(container).fetch(FetchDescriptor<Page>()).first)
        #expect(loaded.attributes[CoreAttributes.traitsKey] == .entries([EntryValue(name: "Keen Senses", text: "Perception.")]))
    }

    // MARK: Navigation

    @Test func openingALibraryEntrySwitchesToItsListAndSelectsIt() throws {
        let library = makeLibrary()
        let navigation = WorldNavigation()
        let hill = try #require(library.entry(forKey: "srd51.race.hill-dwarf"))
        let champion = try #require(library.entry(forKey: "srd51.subclass.champion"))

        navigation.openLibraryEntry(hill)
        #expect(navigation.selection == .library(.race))
        #expect(navigation.selectedLibraryKey == "srd51.race.hill-dwarf")

        // A subclass is listed under Classes.
        navigation.openLibraryEntry(champion)
        #expect(navigation.selection == .library(.class))
        #expect(navigation.selectedLibraryKey == "srd51.subclass.champion")
    }

    @Test func choosingAnotherSidebarItemOrOpeningAPageClearsTheOpenLibraryEntry() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let page = world.addPage(kind: .character, in: context)
        let navigation = WorldNavigation()
        navigation.openLibraryEntry(LibraryEntry(key: "srd51.race.elf", kind: .race, name: "Elf"))

        navigation.choose(.library(.class))
        #expect(navigation.selectedLibraryKey == nil)

        navigation.openLibraryEntry(LibraryEntry(key: "srd51.race.elf", kind: .race, name: "Elf"))
        navigation.open(page)
        #expect(navigation.selectedLibraryKey == nil)
        #expect(navigation.selection == .kind(.character))
    }

    // MARK: Export and import

    @Test func theEditionAndTheSourceOfACustomVersionSurviveExportAndImport() async throws {
        let source = try makeContext()
        let world = makeWorld(in: source, edition: .srd51)
        let library = makeLibrary()
        let fighter = try #require(library.entry(forKey: "srd51.class.fighter"))
        library.makeCustomVersion(of: fighter, in: world, context: source)
        let hero = world.addPage(kind: .character, in: source)
        hero.title = "Aria"
        hero.setReference(.library("srd51.race.elf"), role: LinkRole.race, in: source)

        let contents = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world)))
        let (imported, _) = await WorldImporter.importWorld(contents, into: try makeContext())

        #expect(imported.edition == .srd51)
        let pages = Dictionary(uniqueKeysWithValues: (imported.pages ?? []).map { ($0.title, $0) })
        let custom = try #require(pages["Fighter"])
        #expect(custom.basedOnKey == "srd51.class.fighter")
        #expect(custom.kind == .characterClass)
        guard case .entries(let features)? = custom.attributes[CoreAttributes.featuresKey] else {
            Issue.record("Expected features after import")
            return
        }
        #expect(features.count == 3)
        #expect(pages["Aria"]?.reference(role: LinkRole.race) == .library("srd51.race.elf"))
    }

    @Test func anOlderFileWithNoEditionImportsOnTheDefaultEdition() async throws {
        let source = try makeContext()
        let world = makeWorld(in: source, edition: .srd51)
        var contents = WorldExporter.makeContents(of: world)
        contents.archive.world.edition = nil

        let reread = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: contents))
        #expect(reread.archive.world.edition == nil)
        let (imported, _) = await WorldImporter.importWorld(reread, into: try makeContext())

        #expect(imported.edition == .default)
    }

    // MARK: Mentioning library entries

    private func plainText(_ body: AttributedString) -> String { String(body.characters) }

    @Test func aLibraryMentionURLRoundTripsAndIsNotAPageMention() throws {
        let url = Mention.url(forLibraryKey: "srd51.race.half-elf")

        #expect(Mention.libraryKey(from: url) == "srd51.race.half-elf")
        #expect(Mention.pageID(from: url) == nil)
        #expect(Mention.target(from: url) == .library("srd51.race.half-elf"))

        let id = UUID()
        #expect(Mention.libraryKey(from: Mention.url(for: id)) == nil)
        #expect(Mention.target(from: Mention.url(for: id)) == .page(id))
        #expect(Mention.libraryKey(from: try #require(URL(string: "https://example.com/srd51.race.elf"))) == nil)
    }

    @Test func insertingALibraryMentionLinksTheNameAndLeavesTheSpaceUnlinked() {
        let library = makeLibrary()
        let fighter = library.entry(forKey: "srd51.class.fighter")!
        var body = AttributedString("Trained as a @Fi")
        var selection = AttributedTextSelection()

        Mention.insertMention(ofLibraryEntry: fighter, replacing: 13..<16, in: &body, selection: &selection)

        #expect(plainText(body) == "Trained as a Fighter ")
        #expect(Mention.mentionedLibraryKeys(in: body) == ["srd51.class.fighter"])
        #expect(Mention.mentionedIDs(in: body).isEmpty)
        let linked = body.runs.filter { $0.link != nil }.map { String(body[$0.range].characters) }
        #expect(linked == ["Fighter"])
    }

    @Test func aLibraryMentionIsDeletedAsOneBlockAndKeepsItsNameWhenAPageIsRenamed() {
        let library = makeLibrary()
        let fighter = library.entry(forKey: "srd51.class.fighter")!
        var old = AttributedString("See ")
        old.append(Mention.mention(libraryEntry: fighter))
        old.append(AttributedString(" today"))

        var damaged = AttributedString("See ")
        var partial = AttributedString("Fighte")
        partial.link = Mention.url(forLibraryKey: fighter.key)
        damaged.append(partial)
        damaged.append(AttributedString(" today"))

        let result = Mention.normalize(old: old, new: damaged)
        #expect(plainText(result.body) == "See  today")
        #expect(Mention.mentionedLibraryKeys(in: result.body).isEmpty)

        var refreshed = old
        Mention.refreshTitles(in: &refreshed, titles: [UUID(): "Anything"])
        #expect(refreshed == old)
    }

    @Test func importingLeavesLibraryMentionsAlone() {
        let library = makeLibrary()
        let elf = library.entry(forKey: "srd51.race.elf")!
        var body = AttributedString("A ")
        body.append(Mention.mention(libraryEntry: elf))

        Mention.remapMentions(in: &body, using: [:])

        #expect(Mention.mentionedLibraryKeys(in: body) == ["srd51.race.elf"])
    }

    @Test func libraryEntriesAreFoundByNameForMentioning() {
        let library = makeLibrary()

        #expect(library.mentionableEntries(matching: "fight", in: .srd51, limit: 8).map(\.name) == ["Fighter"])
        #expect(library.mentionableEntries(matching: "dwarf", in: .srd51, limit: 8).map(\.name) == ["Dwarf", "Hill Dwarf"])
        #expect(library.mentionableEntries(matching: "", in: .srd51, limit: 3).count == 3)
        #expect(library.mentionableEntries(matching: "fight", in: .srd52, limit: 8).isEmpty)
        // Subclasses can be mentioned too.
        #expect(library.mentionableEntries(matching: "champ", in: .srd51, limit: 8).map(\.kind) == [.subclass])
    }

    @Test func entriesAreNamedByTheirKind() {
        let library = makeLibrary()
        #expect(String(localized: library.entry(forKey: "srd51.class.fighter")!.kindTitle) == "Class")
        #expect(String(localized: library.entry(forKey: "srd51.subclass.champion")!.kindTitle) == "Subclass")
        #expect(String(localized: library.entry(forKey: "srd51.race.elf")!.kindTitle) == "Race")
        #expect(String(localized: library.entry(forKey: "srd51.race.hill-dwarf")!.kindTitle) == "Subrace")
    }

    @Test func aLinkToALibraryEntryOpensItsListAndEntry() throws {
        let context = try makeContext()
        let world = makeWorld(in: context)
        let navigation = WorldNavigation()
        let router = LinkRouter()
        router.activate(world: world, navigation: navigation)

        #expect(router.open(Mention.url(forLibraryKey: "srd51.class.fighter")))
        #expect(navigation.selection == .library(.class))
        #expect(navigation.selectedLibraryKey == "srd51.class.fighter")
        #expect(!router.open(Mention.url(forLibraryKey: "srd51.class.nobody")))
    }

    // MARK: Subclass of a character

    @Test func aCharacterHasASubclassFieldOnlyUnderDnD() {
        func keys(_ system: RuleSystemID) -> [String] {
            RuleSystems.definitions(for: .character, system: system).map(\.key)
        }
        let dnd = keys(.dnd5e)
        #expect(dnd.contains("dnd5e.subclass"))
        // The subclass comes straight after the class.
        let classIndex = dnd.firstIndex(of: "core.class")
        #expect(classIndex.map { dnd[$0 + 1] } == "dnd5e.subclass")
        #expect(!keys(.none).contains("dnd5e.subclass"))
    }

    @Test func theClassPickerOffersClassesNotSubclasses() {
        let classes = Library.shared.topLevelEntries(.class, in: .srd52)
        #expect(classes.count == 12)
        #expect(classes.allSatisfy { $0.kind == .class })
    }

    // MARK: Skills and the other library kinds

    @Test func bothEditionsHaveTheEighteenSkillsWithTheirAbilities() throws {
        let abilities = ["Strength", "Dexterity", "Constitution", "Intelligence", "Wisdom", "Charisma"]
        let expected: [String: String] = [
            "Athletics": "Strength",
            "Acrobatics": "Dexterity", "Sleight of Hand": "Dexterity", "Stealth": "Dexterity",
            "Arcana": "Intelligence", "History": "Intelligence", "Investigation": "Intelligence", "Nature": "Intelligence", "Religion": "Intelligence",
            "Animal Handling": "Wisdom", "Insight": "Wisdom", "Medicine": "Wisdom", "Perception": "Wisdom", "Survival": "Wisdom",
            "Deception": "Charisma", "Intimidation": "Charisma", "Performance": "Charisma", "Persuasion": "Charisma",
        ]
        for edition in LibraryEdition.allCases {
            let skills = Library.shared.entries(.skill, in: edition)
            #expect(skills.count == 18, "\(edition)")
            for skill in skills {
                #expect(skill.kind == .skill)
                #expect(skill.parent == nil)
                #expect(!skill.summary.isEmpty, "\(skill.name) has no description")
                guard case .text(let ability)? = skill.attributes["dnd5e.ability"] else {
                    Issue.record("\(skill.name) has no ability")
                    continue
                }
                #expect(abilities.contains(ability))
                #expect(expected[skill.name] == ability, "\(skill.name) in \(edition)")
            }
            // Constitution has no skills.
            #expect(!skills.contains { $0.attributes["dnd5e.ability"] == .text("Constitution") })
        }
    }

    @Test func theLibraryListsOnlyKindsThatHaveEntries() {
        for edition in LibraryEdition.allCases {
            let kinds = Library.shared.listKinds(in: edition)
            #expect(kinds.starts(with: [.race, .class]))
            #expect(kinds.contains(.skill))
            #expect(!kinds.contains(.subclass))
            #expect(kinds == kinds.sorted { LibraryKind.listKinds.firstIndex(of: $0)! < LibraryKind.listKinds.firstIndex(of: $1)! })
        }
        #expect(makeLibrary().listKinds(in: .srd51) == [.race, .class])
        #expect(makeLibrary().listKinds(in: .srd52).isEmpty)
    }

    @Test func everyKindHasATitleAnIconAndALabel() {
        for kind in LibraryKind.allCases {
            #expect(!kind.systemImage.isEmpty)
            #expect(!String(localized: kind.listTitle(in: .srd51)).isEmpty)
        }
        #expect(String(localized: LibraryKind.race.listTitle(in: .srd51)) == "Races")
        #expect(String(localized: LibraryKind.race.listTitle(in: .srd52)) == "Species")
        #expect(String(localized: LibraryKind.skill.listTitle(in: .srd52)) == "Skills")
        for kind in LibraryKind.allCases {
            #expect(!String(localized: LibraryEntry(key: "srd52.x.y", kind: kind, name: "N").kindTitle).isEmpty)
        }
    }

    @Test func aSkillCanBeMentionedAndOpenedButNotCopied() throws {
        let context = try makeContext()
        let world = makeWorld(in: context, edition: .srd51)
        let athletics = try #require(Library.shared.entry(forKey: "srd51.skill.athletics"))

        #expect(Library.shared.mentionableEntries(matching: "athlet", in: .srd51, limit: 8).map(\.key) == ["srd51.skill.athletics"])
        #expect(Library.shared.makeCustomVersion(of: athletics, in: world, context: context) == nil)

        let navigation = WorldNavigation()
        navigation.openLibraryEntry(athletics)
        #expect(navigation.selection == .library(.skill))
        #expect(navigation.selectedLibraryKey == "srd51.skill.athletics")
    }

    @Test func aPackWithAKindThisAppDoesNotKnowStillLoads() throws {
        let pack = try decode("""
        { "formatVersion": 1, "id": "p", "name": "P", "edition": "E", "attribution": "A",
          "entries": [
            { "key": "p.skill.a", "kind": "skill", "name": "A" },
            { "key": "p.vehicle.b", "kind": "vehicle", "name": "B" }
          ] }
        """)
        #expect(pack.entries.map(\.key) == ["p.skill.a"])
    }
}
