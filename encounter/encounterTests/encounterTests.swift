//
//  encounterTests.swift
//  encounterTests
//
//  Created by Joe Clarke on 30/10/2026.
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct ModelTests {
    private func makeContext() throws -> (ModelContainer, ModelContext) {
        let container = try AppSchema.makeContainer(inMemory: true)
        return (container, ModelContext(container))
    }

    @Test func newWorldHasDefaults() throws {
        let world = World(name: "Faerûn")
        #expect(world.system == .none)
        #expect(world.calendar?.months.count == 12)
        #expect(world.calendar?.hoursPerDay == 24)
    }

    @Test func pageKindAndRoleRoundTrip() {
        let hero = Page(title: "Aria", kind: .character)
        #expect(hero.kind == .character)
        #expect(hero.characterRole == .nonPlayable)
        hero.characterRole = .playable
        #expect(hero.characterRoleRaw == "playable")

        let place = Page(title: "Neverwinter", kind: .place)
        #expect(place.characterRole == nil)
    }

    @Test func unknownRawValuesFallBackSafely() {
        let page = Page(title: "Odd", kind: .item)
        page.kindRaw = "somethingNew"
        #expect(page.kind == .character)
    }

    @Test func parentAndChildrenStayInSync() throws {
        let (_, context) = try makeContext()
        let region = Page(title: "Sword Coast", kind: .place)
        let town = Page(title: "Neverwinter", kind: .place)
        context.insert(region)
        context.insert(town)
        town.parent = region
        #expect(region.children?.contains(town) == true)
    }

    @Test func attributesAndBodySurviveSaveAndReload() throws {
        let (container, context) = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        page.attributes = [
            "dnd5e.armorClass": .number(15),
            "dnd5e.languages": .list(["Common", "Elvish"]),
        ]
        page.tags = ["hero"]
        page.body = AttributedString("Born in the north.")
        page.startDate = InWorldDate(year: 1492, month: 3, day: 14, hour: 6)
        try context.save()

        let fresh = ModelContext(container)
        let loaded = try #require(try fresh.fetch(FetchDescriptor<Page>()).first)
        #expect(loaded.attributes["dnd5e.armorClass"] == .number(15))
        #expect(loaded.attributes["dnd5e.languages"] == .list(["Common", "Elvish"]))
        #expect(loaded.tags == ["hero"])
        #expect(String(loaded.body.characters) == "Born in the north.")
        #expect(loaded.startDate == InWorldDate(year: 1492, month: 3, day: 14, hour: 6))
    }

    @Test func deletingWorldCascadesToItsContent() throws {
        let (_, context) = try makeContext()
        let world = World(name: "Doomed")
        context.insert(world)
        let a = Page(title: "A", kind: .character)
        let b = Page(title: "B", kind: .place)
        context.insert(a)
        context.insert(b)
        a.world = world
        b.world = world
        context.insert(PageLink(source: a, target: b, role: "location"))
        let image = PageImage(caption: "Portrait", isDefault: true)
        context.insert(image)
        image.page = a
        try context.save()

        context.delete(world)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<World>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<PageImage>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<CalendarDefinition>()) == 0)
    }

    @Test func deletingPageRemovesLinksInBothDirections() throws {
        let (_, context) = try makeContext()
        let a = Page(title: "A", kind: .character)
        let b = Page(title: "B", kind: .character)
        context.insert(a)
        context.insert(b)
        context.insert(PageLink(source: a, target: b, role: "ally"))
        context.insert(PageLink(source: b, target: a, role: "ally"))
        try context.save()

        context.delete(a)
        try context.save()

        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 1)
    }
}

@MainActor
struct PageEditingTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.makeContainer(inMemory: true))
    }

    @Test func addPageCreatesBlankPageOfRequestedKindInWorld() throws {
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)

        let place = world.addPage(kind: .place, in: context)
        #expect(place.kind == .place)
        #expect(place.title.isEmpty)
        #expect(place.world === world)
        #expect(world.pages?.contains(place) == true)
        #expect(place.characterRole == nil)

        let character = world.addPage(kind: .character, in: context)
        #expect(character.characterRole == .nonPlayable)
    }

    @Test func deletingPageLeavesWorldAndOtherPages() throws {
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)
        let keep = world.addPage(kind: .item, in: context)
        let remove = world.addPage(kind: .item, in: context)
        try context.save()

        context.delete(remove)
        try context.save()

        let remaining = try context.fetch(FetchDescriptor<Page>())
        #expect(remaining.count == 1)
        #expect(remaining.first === keep)
        #expect(try context.fetchCount(FetchDescriptor<World>()) == 1)
    }

    @Test func textAttributesStoreAndClear() {
        let page = Page(title: "Aria", kind: .character)
        page.setAttributeText("core.occupation", "Ranger")
        #expect(page.attributeText("core.occupation") == "Ranger")
        page.setAttributeText("core.occupation", "")
        #expect(page.attributes["core.occupation"] == nil)
        #expect(page.attributeText("core.occupation").isEmpty)
    }

    @Test func numberAttributesStoreAndClear() {
        let page = Page(title: "Neverwinter", kind: .place)
        page.setAttributeNumber("core.population", 25_000)
        #expect(page.attributeNumber("core.population") == 25_000)
        page.setAttributeNumber("core.population", nil)
        #expect(page.attributes["core.population"] == nil)
    }

    @Test func tagsAreTrimmedAndDeduplicated() {
        let page = Page(title: "Aria", kind: .character)
        #expect(page.addTag("  hero "))
        #expect(!page.addTag("Hero"))
        #expect(!page.addTag("   "))
        #expect(page.tags == ["hero"])
    }

    @Test func characterRaceLinkCanBeSetReplacedAndCleared() throws {
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)
        let hero = world.addPage(kind: .character, in: context)
        let elf = world.addPage(kind: .race, in: context)
        let dwarf = world.addPage(kind: .race, in: context)

        #expect(hero.linkedPage(role: "race") == nil)

        hero.setLinkedPage(elf, role: "race", in: context)
        #expect(hero.linkedPage(role: "race") === elf)

        hero.setLinkedPage(dwarf, role: "race", in: context)
        #expect(hero.linkedPage(role: "race") === dwarf)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 1)

        hero.setLinkedPage(nil, role: "race", in: context)
        #expect(hero.linkedPage(role: "race") == nil)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PageLink>()) == 0)
    }

    @Test func deletingARaceClearsTheCharactersRace() throws {
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)
        let hero = world.addPage(kind: .character, in: context)
        let elf = world.addPage(kind: .race, in: context)
        hero.setLinkedPage(elf, role: "race", in: context)
        try context.save()

        context.delete(elf)
        try context.save()

        #expect(hero.linkedPage(role: "race") == nil)
        #expect(try context.fetchCount(FetchDescriptor<Page>()) == 1)
    }

    @Test func differentLinkRolesDoNotInterfere() throws {
        let context = try makeContext()
        let world = World(name: "W")
        context.insert(world)
        let hero = world.addPage(kind: .character, in: context)
        let elf = world.addPage(kind: .race, in: context)
        let guild = world.addPage(kind: .organisation, in: context)
        hero.setLinkedPage(elf, role: "race", in: context)
        hero.setLinkedPage(guild, role: "member", in: context)

        hero.setLinkedPage(nil, role: "race", in: context)
        #expect(hero.linkedPage(role: "race") == nil)
        #expect(hero.linkedPage(role: "member") === guild)
    }

    @Test func characterDefinesARaceReferenceToRaces() {
        let race = CoreAttributes.definitions(for: .character).first { $0.key == "core.race" }
        guard case .pageReference(let kind, let role)? = race?.type else {
            Issue.record("Character is missing a race reference attribute")
            return
        }
        #expect(kind == .race)
        #expect(role == "race")
    }

    @Test func coreAttributeKeysAreUniqueAndScopedToKinds() {
        let keys = CoreAttributes.all.map(\.key)
        #expect(Set(keys).count == keys.count)

        #expect(CoreAttributes.definitions(for: .character).contains { $0.key == "core.creatureType" })
        #expect(CoreAttributes.definitions(for: .place).contains { $0.key == "core.placeType" })
        #expect(!CoreAttributes.definitions(for: .place).contains { $0.key == "core.creatureType" })
        #expect(CoreAttributes.definitions(for: .event).isEmpty)
        #expect(PageKind.allCases.filter { $0 != .event }.allSatisfy { !CoreAttributes.definitions(for: $0).isEmpty })
    }
}

@MainActor
struct CalendarTests {
    private func calendar() -> CalendarDefinition {
        CalendarDefinition(
            hoursPerDay: 10,
            months: [
                CalendarMonth(name: "Frost", dayCount: 20),
                CalendarMonth(name: "Bloom", dayCount: 30),
            ]
        )
    }

    @Test func yearLengthIsSumOfMonths() {
        let calendar = calendar()
        #expect(calendar.daysPerYear == 50)
        #expect(calendar.hoursPerYear == 500)
    }

    @Test func absoluteHourOrdersDates() throws {
        let calendar = calendar()
        let origin = try #require(calendar.absoluteHour(of: InWorldDate(year: 0, month: 1, day: 1, hour: 0)))
        let nextHour = try #require(calendar.absoluteHour(of: InWorldDate(year: 0, month: 1, day: 1, hour: 1)))
        let secondMonth = try #require(calendar.absoluteHour(of: InWorldDate(year: 0, month: 2, day: 1, hour: 0)))
        let nextYear = try #require(calendar.absoluteHour(of: InWorldDate(year: 1, month: 1, day: 1, hour: 0)))

        #expect(origin == 0)
        #expect(nextHour == 1)
        #expect(secondMonth == 20 * 10)
        #expect(nextYear == 500)
    }

    @Test func invalidDatesAreRejected() {
        let calendar = calendar()
        #expect(calendar.absoluteHour(of: InWorldDate(year: 1, month: 3, day: 1, hour: 0)) == nil)
        #expect(calendar.absoluteHour(of: InWorldDate(year: 1, month: 1, day: 21, hour: 0)) == nil)
        #expect(calendar.absoluteHour(of: InWorldDate(year: 1, month: 1, day: 1, hour: 10)) == nil)
        #expect(calendar.absoluteHour(of: InWorldDate(year: 1, month: 0, day: 1, hour: 0)) == nil)
    }

    @Test func generatedMonthsAreEvenAndNamed() {
        let months = CalendarDefinition.makeMonths(count: 4, daysPerMonth: 28)
        #expect(months.count == 4)
        #expect(months.allSatisfy { $0.dayCount == 28 })
        #expect(months.first?.name == "Month 1")
    }
}
