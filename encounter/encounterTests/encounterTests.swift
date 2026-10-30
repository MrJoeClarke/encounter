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

struct ImageProcessingTests {
    @Test func smallImagesKeepTheirOriginalBytesAndGetAThumbnailNoLargerThanTheImage() throws {
        let data = SampleData.solidImage(width: 100, height: 50)
        let prepared = try #require(ImageProcessing.prepareSynchronously(data))

        #expect(prepared.imageData == data)
        let thumbnailSize = try #require(ImageProcessing.pixelSize(of: prepared.thumbnailData))
        #expect(thumbnailSize.width == 100)
        #expect(thumbnailSize.height == 50)
    }

    @Test func largeImagesAreDownscaledKeepingAspectRatio() throws {
        let data = SampleData.solidImage(width: 4500, height: 2250)
        let prepared = try #require(ImageProcessing.prepareSynchronously(data))

        let original = try #require(ImageProcessing.pixelSize(of: prepared.imageData))
        #expect(max(original.width, original.height) == ImageProcessing.maxOriginalDimension)
        #expect(original.width == 2 * original.height)

        let thumbnail = try #require(ImageProcessing.pixelSize(of: prepared.thumbnailData))
        #expect(max(thumbnail.width, thumbnail.height) == ImageProcessing.thumbnailDimension)
        #expect(thumbnail.width == 2 * thumbnail.height)
    }

    @Test func customLimitsAreRespected() throws {
        let data = SampleData.solidImage(width: 800, height: 400)
        let prepared = try #require(
            ImageProcessing.prepareSynchronously(data, maxDimension: 500, thumbnailDimension: 50)
        )
        #expect(ImageProcessing.pixelSize(of: prepared.imageData)?.width == 500)
        #expect(ImageProcessing.pixelSize(of: prepared.thumbnailData)?.width == 50)
    }

    @Test func downscalingKeepsTransparencyAsPNG() throws {
        let data = SampleData.solidImage(width: 600, height: 300, withAlpha: true)
        let prepared = try #require(
            ImageProcessing.prepareSynchronously(data, maxDimension: 400, thumbnailDimension: 100)
        )
        // PNG files start with this signature. JPEG would have lost the alpha channel.
        let pngSignature = Data([0x89, 0x50, 0x4E, 0x47])
        #expect(prepared.imageData.prefix(4) == pngSignature)
        #expect(prepared.thumbnailData.prefix(4) == pngSignature)
    }

    @Test func undecodableDataIsRejected() {
        #expect(ImageProcessing.prepareSynchronously(Data("not an image".utf8)) == nil)
        #expect(ImageProcessing.prepareSynchronously(Data()) == nil)
    }
}

@MainActor
struct PageImageRulesTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.makeContainer(inMemory: true))
    }

    private func prepared(_ red: Double = 0.5) throws -> PreparedImage {
        try #require(
            ImageProcessing.prepareSynchronously(SampleData.solidImage(width: 40, height: 40, red: red))
        )
    }

    @Test func firstImageBecomesDefaultAndLaterOnesDoNot() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)

        let first = page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)

        #expect(first.isDefault)
        #expect(!second.isDefault)
        #expect(page.defaultImage === first)
        #expect(page.sortedImages.map(\.sortOrder) == [0, 1])
        #expect(first.thumbnailData != nil)
    }

    @Test func settingADefaultClearsTheOthers() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let first = page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)
        let third = page.addImage(try prepared(0.3), in: context)

        page.setDefaultImage(third)

        #expect(page.sortedImages.filter(\.isDefault).count == 1)
        #expect(page.defaultImage === third)
        #expect(!first.isDefault)
        #expect(!second.isDefault)
    }

    @Test func removingTheDefaultPromotesTheNextImage() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let first = page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)
        page.addImage(try prepared(0.3), in: context)

        page.removeImage(first, in: context)

        #expect(page.sortedImages.count == 2)
        #expect(page.defaultImage === second)
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<PageImage>()) == 2)
    }

    @Test func removingANonDefaultImageKeepsTheDefault() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let first = page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)

        page.removeImage(second, in: context)

        #expect(page.defaultImage === first)
        #expect(page.sortedImages.count == 1)
    }

    @Test func removingTheLastImageLeavesNoDefault() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let only = page.addImage(try prepared(), in: context)

        page.removeImage(only, in: context)

        #expect(page.sortedImages.isEmpty)
        #expect(page.defaultImage == nil)
    }

    @Test func addingAfterARemovalDoesNotReuseASortOrder() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)
        page.removeImage(second, in: context)

        let third = page.addImage(try prepared(0.3), in: context)

        #expect(third.sortOrder == 1)
        #expect(!third.isDefault)
    }

    @Test func imagesCanBeMovedButNotPastEitherEnd() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let first = page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)
        let third = page.addImage(try prepared(0.3), in: context)

        page.moveImage(third, by: -1)
        #expect(page.sortedImages.map(\.id) == [first.id, third.id, second.id])

        page.moveImage(first, by: -1)
        page.moveImage(second, by: 1)
        #expect(page.sortedImages.map(\.id) == [first.id, third.id, second.id])

        page.moveImage(first, by: 1)
        #expect(page.sortedImages.map(\.id) == [third.id, first.id, second.id])
        #expect(page.sortedImages.map(\.sortOrder) == [0, 1, 2])
    }

    @Test func dragReorderMovesImagesBeforeATargetOrToTheEnd() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let a = page.addImage(try prepared(0.1), in: context)
        let b = page.addImage(try prepared(0.2), in: context)
        let c = page.addImage(try prepared(0.3), in: context)
        let d = page.addImage(try prepared(0.4), in: context)

        page.moveImages(withIDs: [d.id], before: a.id)
        #expect(page.sortedImages.map(\.id) == [d.id, a.id, b.id, c.id])

        page.moveImages(withIDs: [d.id, a.id], before: nil)
        #expect(page.sortedImages.map(\.id) == [b.id, c.id, d.id, a.id])

        // Dropping onto the dragged item itself changes nothing.
        page.moveImages(withIDs: [c.id], before: c.id)
        #expect(page.sortedImages.map(\.id) == [b.id, c.id, d.id, a.id])

        // An unknown target moves to the end, without losing or duplicating images.
        page.moveImages(withIDs: [b.id], before: UUID())
        #expect(page.sortedImages.map(\.id) == [c.id, d.id, a.id, b.id])
        #expect(page.sortedImages.map(\.sortOrder) == [0, 1, 2, 3])
    }

    @Test func dragReorderDoesNotChangeTheDefault() throws {
        let context = try makeContext()
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let first = page.addImage(try prepared(0.1), in: context)
        let second = page.addImage(try prepared(0.2), in: context)

        page.moveImages(withIDs: [second.id], before: first.id)

        #expect(page.defaultImage === first)
        #expect(page.sortedImages.first === second)
    }

    @Test func imagesSurviveSaveAndReload() throws {
        let container = try AppSchema.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let page = Page(title: "Aria", kind: .character)
        context.insert(page)
        let image = page.addImage(try prepared(), caption: "Portrait", in: context)
        try context.save()

        let fresh = ModelContext(container)
        let loaded = try #require(try fresh.fetch(FetchDescriptor<Page>()).first)
        let loadedImage = try #require(loaded.defaultImage)
        #expect(loadedImage.caption == "Portrait")
        #expect(loadedImage.imageData == image.imageData)
        #expect(loadedImage.thumbnailData == image.thumbnailData)
    }
}

@MainActor
struct RuleSystemTests {
    private func keys(_ kind: PageKind, _ system: RuleSystemID) -> [String] {
        RuleSystems.definitions(for: kind, system: system).map(\.key)
    }

    @Test func noSystemGivesExactlyTheCoreAttributes() {
        for kind in PageKind.allCases {
            #expect(keys(kind, .none) == CoreAttributes.definitions(for: kind).map(\.key))
        }
    }

    @Test func mergedDefinitionsNeverRepeatAKey() {
        for system in RuleSystemID.allCases {
            for kind in PageKind.allCases {
                let merged = keys(kind, system)
                #expect(Set(merged).count == merged.count, "\(system) / \(kind) has duplicate keys")
            }
        }
    }

    @Test func dndAddsStatBlockAttributesToCharacters() {
        let characterKeys = keys(.character, .dnd5e)
        for key in [
            "dnd5e.size", "dnd5e.alignment", "dnd5e.challengeRating", "dnd5e.speed",
            "dnd5e.armorClass", "dnd5e.hitPoints", "dnd5e.hitDice",
            "dnd5e.strength", "dnd5e.dexterity", "dnd5e.constitution",
            "dnd5e.intelligence", "dnd5e.wisdom", "dnd5e.charisma",
        ] {
            #expect(characterKeys.contains(key), "missing \(key)")
        }
        #expect(!keys(.character, .none).contains("dnd5e.armorClass"))
    }

    @Test func dndAddsAttributesToOtherKinds() {
        #expect(keys(.race, .dnd5e).contains("dnd5e.darkvision"))
        #expect(keys(.race, .dnd5e).contains("dnd5e.languages"))
        #expect(keys(.race, .dnd5e).contains("dnd5e.speed"))
        #expect(keys(.item, .dnd5e).contains("dnd5e.rarity"))
        #expect(keys(.item, .dnd5e).contains("dnd5e.requiresAttunement"))
        #expect(keys(.organisation, .dnd5e).contains("dnd5e.alignment"))
        #expect(keys(.place, .dnd5e) == keys(.place, .none))
        #expect(keys(.event, .dnd5e).isEmpty)
    }

    @Test func dndOverridesCoreAttributesInPlaceKeepingTheirPosition() throws {
        let plain = RuleSystems.definitions(for: .character, system: .none)
        let dnd = RuleSystems.definitions(for: .character, system: .dnd5e)

        let plainIndex = try #require(plain.firstIndex { $0.key == "core.creatureType" })
        let dndIndex = try #require(dnd.firstIndex { $0.key == "core.creatureType" })
        #expect(plainIndex == dndIndex)

        guard case .text = plain[plainIndex].type else {
            Issue.record("Core creature type should be free text")
            return
        }
        guard case .choice(let options) = dnd[dndIndex].type else {
            Issue.record("D&D creature type should be a picker")
            return
        }
        #expect(options.contains("Beast"))
        #expect(options.contains("Humanoid"))
    }

    @Test func dndChoiceListsAreNonEmptyAndHaveNoDuplicates() {
        for definition in DnD5eSystem().attributes {
            if case .choice(let options) = definition.type {
                #expect(!options.isEmpty, "\(definition.key) has no options")
                #expect(Set(options).count == options.count, "\(definition.key) has duplicate options")
            }
        }
    }

    @Test func everyDefinitionAppliesToAtLeastOneKind() {
        for system in RuleSystemID.allCases {
            for definition in RuleSystems.system(for: system).attributes {
                #expect(!definition.appliesTo.isEmpty, "\(definition.key) applies to nothing")
            }
        }
    }

    @Test func challengeRatingsRunFromZeroThroughThirty() {
        let ratings = DnD5eSystem.challengeRatings
        #expect(Array(ratings.prefix(5)) == ["0", "1/8", "1/4", "1/2", "1"])
        #expect(ratings.last == "30")
        #expect(ratings.count == 34)
    }

    @Test func abilityModifiersRoundDownFromTen() {
        let expected: [Int: Int] = [
            1: -5, 2: -4, 3: -4, 8: -1, 9: -1, 10: 0, 11: 0, 12: 1, 13: 1, 14: 2,
            15: 2, 16: 3, 18: 4, 20: 5, 30: 10,
        ]
        for (score, modifier) in expected {
            #expect(DnD5eSystem.abilityModifier(for: score) == modifier, "score \(score)")
        }
    }

    @Test func abilityModifierTextShowsSignAndUsesATrueMinus() {
        #expect(DnD5eSystem.abilityModifierText(for: 16) == "+3")
        #expect(DnD5eSystem.abilityModifierText(for: 10) == "+0")
        #expect(DnD5eSystem.abilityModifierText(for: 11) == "+0")
        #expect(DnD5eSystem.abilityModifierText(for: 8) == "\u{2212}1")
        #expect(DnD5eSystem.abilityModifierText(for: 1) == "\u{2212}5")
    }

    @Test func switchingSystemsKeepsStoredValues() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        context.insert(world)
        let hero = world.addPage(kind: .character, in: context)
        hero.setAttributeNumber("dnd5e.armorClass", 17)
        hero.setAttributeText("core.creatureType", "Humanoid")

        world.system = .none
        #expect(!RuleSystems.definitions(for: .character, system: world.system).contains { $0.key == "dnd5e.armorClass" })
        #expect(hero.attributeNumber("dnd5e.armorClass") == 17)

        world.system = .dnd5e
        #expect(RuleSystems.definitions(for: .character, system: world.system).contains { $0.key == "dnd5e.armorClass" })
        #expect(hero.attributeNumber("dnd5e.armorClass") == 17)
        #expect(hero.attributeText("core.creatureType") == "Humanoid")
    }

    @Test func boolAttributesStoreTrueAndRemoveFalse() {
        let item = Page(title: "Ring", kind: .item)
        #expect(!item.attributeBool("dnd5e.requiresAttunement"))
        item.setAttributeBool("dnd5e.requiresAttunement", true)
        #expect(item.attributeBool("dnd5e.requiresAttunement"))
        item.setAttributeBool("dnd5e.requiresAttunement", false)
        #expect(item.attributes["dnd5e.requiresAttunement"] == nil)
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
