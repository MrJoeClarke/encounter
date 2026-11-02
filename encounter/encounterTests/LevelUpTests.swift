//
//  LevelUpTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

struct LevelRulesTests {
    @Test func theAverageRollIsHalfTheDieRoundedUp() {
        #expect([6, 8, 10, 12].map { LevelRules.averageRoll(hitDieSides: $0) } == [4, 5, 6, 7])
    }

    @Test func aLevelAlwaysGivesAtLeastOneHitPoint() {
        #expect(LevelRules.hitPointsGained(roll: 5, constitution: 14) == 7)
        #expect(LevelRules.hitPointsGained(roll: 1, constitution: 6) == 1)
        #expect(LevelRules.hitPointsGained(roll: 4, constitution: 10) == 4)
    }

    @Test func raisingTheConstitutionModifierRaisesEarlierLevelsToo() {
        // 13 to 14 moves the modifier from +1 to +2, for each of the 3 levels already taken.
        #expect(LevelRules.retroactiveHitPoints(levelsBefore: 3, oldConstitution: 13, newConstitution: 14) == 3)
        #expect(LevelRules.retroactiveHitPoints(levelsBefore: 3, oldConstitution: 14, newConstitution: 15) == 0)
    }

    @Test func anIncreaseIsTwoPointsAndNeverPastTwenty() {
        let scores: [Ability: Int] = [.strength: 18, .dexterity: 19, .constitution: 14]
        #expect(LevelRules.isValidIncrease([.strength: 2], to: scores))
        #expect(LevelRules.isValidIncrease([.strength: 1, .constitution: 1], to: scores))
        #expect(!LevelRules.isValidIncrease([.strength: 1], to: scores))
        #expect(!LevelRules.isValidIncrease([.strength: 1, .constitution: 1, .dexterity: 1], to: scores))
        #expect(!LevelRules.isValidIncrease([.dexterity: 2], to: scores))
        #expect(LevelRules.isValidIncrease([.dexterity: 1, .constitution: 1], to: scores))
        #expect(!LevelRules.isValidIncrease([:], to: scores))
    }

    @Test func ordinalsReadAsTheRulesWriteThem() {
        #expect((1...9).map(ClassProgression.ordinal) == ["1st", "2nd", "3rd", "4th", "5th", "6th", "7th", "8th", "9th"])
    }
}

/// The class tables the converter reads from the SRD, as the library has them.
@MainActor
struct ClassTableTests {
    private func progression(_ key: String) throws -> ClassProgression {
        let entry = try #require(Library.shared.entry(forKey: key))
        return try #require(ClassProgression(attributes: entry.attributes))
    }

    @Test func everyClassInBothEditionsHasATable() throws {
        for edition in LibraryEdition.dnd {
            let classes = Library.shared.topLevelEntries(.class, in: edition)
            #expect(classes.count == 12)
            for entry in classes {
                let progression = try #require(ClassProgression(attributes: entry.attributes), "\(entry.name) has no table")
                #expect(progression.improvementLevels.count >= 5 && progression.improvementLevels.first == 4)
            }
        }
    }

    @Test func fighterAndRogueGetExtraImprovements() throws {
        for edition in ["srd51", "srd52"] {
            #expect(try progression("\(edition).class.fighter").improvementLevels == [4, 6, 8, 12, 14, 16, 19])
            #expect(try progression("\(edition).class.rogue").improvementLevels == [4, 8, 10, 12, 16, 19])
            #expect(try progression("\(edition).class.wizard").improvementLevels == [4, 8, 12, 16, 19])
        }
    }

    @Test func aFullCastersSlotsMatchTheRules() throws {
        for key in ["srd51.class.wizard", "srd52.class.wizard", "srd51.class.cleric", "srd52.class.bard", "srd52.class.sorcerer"] {
            let table = try progression(key)
            #expect(table.slotsDescription(at: 1) == "1st ×2")
            #expect(table.slotsDescription(at: 5) == "1st ×4, 2nd ×3, 3rd ×2")
            #expect(table.slotsDescription(at: 20) == "1st ×4, 2nd ×3, 3rd ×3, 4th ×3, 5th ×3, 6th ×2, 7th ×2, 8th ×1, 9th ×1")
            #expect(table.highestSpellLevel(at: 17) == 9 && table.highestSpellLevel(at: 16) == 8)
        }
    }

    @Test func halfCastersStartLaterAndStopAtFifthLevel() throws {
        let paladin51 = try progression("srd51.class.paladin")
        #expect(paladin51.slotsDescription(at: 1) == "" && paladin51.slotsDescription(at: 2) == "1st ×2")
        #expect(paladin51.highestSpellLevel(at: 20) == 5)
        let paladin52 = try progression("srd52.class.paladin")
        #expect(paladin52.slotsDescription(at: 1) == "1st ×2")
        #expect(paladin52.spellsPrepared(at: 1) == 2 && paladin52.spellsPrepared(at: 20) == 15)
        #expect(try progression("srd51.class.ranger").spellsKnown(at: 20) == 11)
    }

    @Test func aWarlocksSlotsAreAllOfOneLevel() throws {
        for key in ["srd51.class.warlock", "srd52.class.warlock"] {
            let table = try progression(key)
            #expect(table.slotsDescription(at: 1) == "1 × 1st level")
            #expect(table.slotsDescription(at: 2) == "2 × 1st level")
            #expect(table.slotsDescription(at: 11) == "3 × 5th level")
            #expect(table.slotsDescription(at: 17) == "4 × 5th level")
            #expect(table.highestSpellLevel(at: 20) == 5)
        }
    }

    @Test func casterColumnsNeverFallAsTheLevelRises() throws {
        for edition in LibraryEdition.dnd {
            for entry in Library.shared.topLevelEntries(.class, in: edition) {
                let table = try #require(ClassProgression(attributes: entry.attributes))
                for column in [table.cantrips, table.spellsKnown, table.prepared, table.invocations].compactMap({ $0 }) {
                    #expect(column.count == 20 && zip(column, column.dropFirst()).allSatisfy { $0 <= $1 }, "\(entry.name)")
                }
            }
        }
    }

    @Test func classesThatDontCastHaveNoSpellColumns() throws {
        for name in ["barbarian", "fighter", "monk", "rogue"] {
            #expect(!(try progression("srd51.class.\(name)").castsSpells))
        }
    }
}

@MainActor
struct LevelUpTests {
    private func makeWorld(_ edition: LibraryEdition = .srd51) throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        world.edition = edition
        context.insert(world)
        return (world, context)
    }

    /// A playable character of a library class, with the numbers the builder would have given it.
    private func character(
        class classKey: String, level: Int = 1, hitPoints: Int = 12, subclass: String? = nil, constitution: Int = 14,
        in world: World, _ context: ModelContext
    ) -> Page {
        let page = world.addPage(kind: .character, in: context)
        page.title = "Hero"
        page.characterRole = .playable
        page.summary = "Human Test, level \(level)"
        page.setReference(.library(classKey), role: LinkRole.characterClass, in: context)
        if let subclass { page.setLibraryKey(subclass, role: "subclass") }
        page.setAttributeNumber("dnd5e.classLevel", Double(level))
        page.setAttributeNumber("dnd5e.hitPoints", Double(hitPoints))
        for ability in Ability.allCases { page.setAttributeNumber(ability.attributeKey, 12) }
        page.setAttributeNumber("dnd5e.constitution", Double(constitution))
        page.setAttributeNumber("dnd5e.proficiencyBonus", Double(CharacterRules.proficiencyBonus(atLevel: level)))
        return page
    }

    private func context(for page: Page) throws -> LevelUpContext {
        try #require(LevelUp.context(for: page))
    }

    @Test func aLevelGivesAverageHitPointsAndTheFeaturesOfThatLevel() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", in: world, modelContext)
        let levelling = try context(for: page)
        #expect(levelling.needs.newLevel == 2 && levelling.needs.hitDieSides == 10)

        LevelUp.apply(LevelUpChoices(), to: levelling, in: modelContext)

        // Average d10 is 6, plus the Constitution modifier of +2.
        #expect(page.attributeNumber("dnd5e.hitPoints") == 20)
        #expect(page.attributeNumber("dnd5e.classLevel") == 2)
        #expect(page.attributeText("dnd5e.hitDice") == "2d10")
        #expect(page.summary == "Human Test, level 2")
        guard case .entries(let features)? = page.attributes["dnd5e.classFeatures"] else { Issue.record("Expected features"); return }
        #expect(features.map(\.name) == ["Action Surge"])
    }

    @Test func aRolledLevelUsesTheRoll() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", in: world, modelContext)
        var choices = LevelUpChoices()
        choices.hitPoints = .rolled(3)
        LevelUp.apply(choices, to: try context(for: page), in: modelContext)
        #expect(page.attributeNumber("dnd5e.hitPoints") == 17)
        // A roll outside the die isn't allowed.
        let fresh = character(class: "srd51.class.fighter", in: world, modelContext)
        #expect(!(try context(for: fresh)).problems(for: LevelUpChoices(hitPoints: .rolled(0))).isEmpty)
        #expect(!(try context(for: fresh)).problems(for: LevelUpChoices(hitPoints: .rolled(11))).isEmpty)
        #expect(try context(for: fresh).problems(for: LevelUpChoices(hitPoints: .rolled(10))).isEmpty)
    }

    @Test func theProficiencyBonusRisesAtLevelFive() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", level: 4, in: world, modelContext)
        var choices = LevelUpChoices()
        LevelUp.apply(choices, to: try context(for: page), in: modelContext)
        #expect(page.attributeNumber("dnd5e.proficiencyBonus") == 3)
        choices = LevelUpChoices()
        let again = character(class: "srd51.class.fighter", level: 5, in: world, modelContext)
        LevelUp.apply(choices, to: try context(for: again), in: modelContext)
        #expect(again.attributeNumber("dnd5e.proficiencyBonus") == 3)
    }

    @Test func aSubclassIsChosenAtItsLevelAndBringsItsFeatures() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", level: 2, in: world, modelContext)
        let levelling = try context(for: page)
        #expect(levelling.needs.choosesSubclass && levelling.subclassLevel == 3)
        #expect(!levelling.problems(for: LevelUpChoices()).isEmpty)

        var choices = LevelUpChoices()
        choices.subclass = "srd51.subclass.champion"
        #expect(levelling.problems(for: choices).isEmpty)
        LevelUp.apply(choices, to: levelling, in: modelContext)

        #expect(page.libraryKey(role: "subclass") == "srd51.subclass.champion")
        guard case .entries(let features)? = page.attributes["dnd5e.classFeatures"] else { Issue.record("Expected features"); return }
        #expect(features.map(\.name).contains("Martial Archetype") && features.map(\.name).contains("Champion: Improved Critical"))
        // The next level doesn't ask again, and gives the subclass's own features when it has them.
        #expect(!(try context(for: page)).needs.choosesSubclass)
    }

    @Test func aClassThatPicksItsSubclassAtLevelOneIsNeverAsked() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.cleric", subclass: "srd51.subclass.life-domain", in: world, modelContext)
        #expect(!(try context(for: page)).needs.choosesSubclass)
    }

    @Test func anAbilityIncreaseCanBeTwoInOneOrOneInTwo() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", level: 3, subclass: "srd51.subclass.champion", in: world, modelContext)
        let levelling = try context(for: page)
        #expect(levelling.needs.hasImprovement)
        #expect(!levelling.problems(for: LevelUpChoices()).isEmpty)

        var choices = LevelUpChoices()
        choices.abilityIncreases = [.strength: 1, .dexterity: 1]
        #expect(levelling.problems(for: choices).isEmpty)
        LevelUp.apply(choices, to: levelling, in: modelContext)
        #expect(page.attributeNumber("dnd5e.strength") == 13 && page.attributeNumber("dnd5e.dexterity") == 13)
    }

    @Test func raisingConstitutionAddsHitPointsForEveryEarlierLevel() throws {
        let (world, modelContext) = try makeWorld()
        // Constitution 13 (+1) and three levels taken.
        let page = character(class: "srd51.class.fighter", level: 3, hitPoints: 30, subclass: "srd51.subclass.champion", constitution: 13, in: world, modelContext)
        var choices = LevelUpChoices()
        choices.abilityIncreases = [.constitution: 1, .strength: 1]
        LevelUp.apply(choices, to: try context(for: page), in: modelContext)
        // +6 average, +2 modifier now, and +1 for each of the 3 levels before.
        #expect(page.attributeNumber("dnd5e.constitution") == 14)
        let expected = 30 + 6 + 2 + 3
        #expect(Int(page.attributeNumber("dnd5e.hitPoints") ?? 0) == expected)
    }

    @Test func aFeatCanTakeTheImprovementsPlace() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", level: 3, subclass: "srd51.subclass.champion", in: world, modelContext)
        let levelling = try context(for: page)
        #expect(levelling.featOptions.map(\.name) == ["Grappler"])
        var choices = LevelUpChoices()
        choices.feat = "srd51.feat.grappler"
        #expect(levelling.problems(for: choices).isEmpty)
        LevelUp.apply(choices, to: levelling, in: modelContext)
        guard case .entries(let feats)? = page.attributes["dnd5e.feats"] else { Issue.record("Expected feats"); return }
        #expect(feats.map(\.name) == ["Grappler"] && feats.first?.level == 4)
        #expect(page.attributeNumber("dnd5e.strength") == 12)
        #expect(try context(for: page).needs.newLevel == 5)
    }

    @Test func the2024RulesOfferGeneralFeatsAndEpicBoonsOnlyAtTheEnd() throws {
        let (world, modelContext) = try makeWorld(.srd52)
        let early = character(class: "srd52.class.fighter", level: 3, in: world, modelContext)
        let earlyNames = try context(for: early).featOptions.map(\.name)
        #expect(earlyNames.contains("Grappler") && !earlyNames.contains("Ability Score Improvement"))
        #expect(!earlyNames.contains { $0.hasPrefix("Boon") })

        let late = character(class: "srd52.class.fighter", level: 18, in: world, modelContext)
        #expect(try context(for: late).needs.newLevel == 19)
        #expect(try context(for: late).featOptions.contains { $0.name.hasPrefix("Boon") })
    }

    @Test func aWizardWritesTwoSpellsInTheSpellbookAndGainsSlots() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.wizard", hitPoints: 8, in: world, modelContext)
        let levelling = try context(for: page)
        #expect(levelling.needs.spellsToLearn == 2 && levelling.needs.cantripsToLearn == 0 && levelling.needs.highestSpellLevel == 1)
        #expect(!levelling.problems(for: LevelUpChoices()).isEmpty)

        // A wizard also picks an Arcane Tradition at level 2.
        var choices = LevelUpChoices()
        choices.subclass = "srd51.subclass.school-of-evocation"
        choices.spells = ["srd51.spell.magic-missile", "srd51.spell.shield"]
        #expect(levelling.problems(for: choices).isEmpty)
        // Not fewer, and not more.
        choices.spells = ["srd51.spell.magic-missile"]
        #expect(!levelling.problems(for: choices).isEmpty)
        choices.spells = ["srd51.spell.magic-missile", "srd51.spell.shield"]
        LevelUp.apply(choices, to: levelling, in: modelContext)

        guard case .entries(let spells)? = page.attributes["dnd5e.spells"] else { Issue.record("Expected spells"); return }
        #expect(spells.map(\.name).sorted() == ["Magic Missile", "Shield"])
        #expect(page.attributeText("dnd5e.spellSlots") == "1st ×3")
        // They aren't offered again.
        #expect(try context(for: page).spellOptions(level: 1).allSatisfy { $0.name != "Shield" && $0.name != "Magic Missile" })
    }

    @Test func aKnownSpellsCasterLearnsTheDifferenceInTheTable() throws {
        let (world, modelContext) = try makeWorld()
        // A 5.1 bard knows 4 spells at level 1 and 5 at level 2, and a level 2 character of it learns one.
        let page = character(class: "srd51.class.bard", in: world, modelContext)
        let needs = try context(for: page).needs
        #expect(needs.spellsToLearn == 1 && needs.cantripsToLearn == 0)

        // A 5.2 sorcerer prepares 2 spells at level 1 and 4 at level 2.
        let (world52, context52) = try makeWorld(.srd52)
        let sorcerer = character(class: "srd52.class.sorcerer", in: world52, context52)
        #expect(try context(for: sorcerer).needs.spellsToLearn == 2)
    }

    @Test func aWarlockOfTheSecondLevelHasPactSlots() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.warlock", in: world, modelContext)
        var choices = LevelUpChoices()
        let levelling = try context(for: page)
        choices.spells = Set(levelling.spellOptions(level: 1).prefix(levelling.spellsToChoose).map(\.key))
        LevelUp.apply(choices, to: levelling, in: modelContext)
        #expect(page.attributeText("dnd5e.spellSlots") == "2 × 1st level")
    }

    @Test func aClassThatCantCastGetsNoSlotsOrSpellChoices() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.barbarian", in: world, modelContext)
        let levelling = try context(for: page)
        #expect(levelling.cantripsToChoose == 0 && levelling.spellsToChoose == 0)
        LevelUp.apply(LevelUpChoices(), to: levelling, in: modelContext)
        #expect(page.attributes["dnd5e.spellSlots"] == nil && page.attributes["dnd5e.spells"] == nil)
    }

    @Test func aCustomClassMadeFromALibraryClassLevelsToo() throws {
        let (world, modelContext) = try makeWorld()
        let entry = try #require(Library.shared.entry(forKey: "srd51.class.wizard"))
        let classPage = try #require(Library.shared.makeCustomVersion(of: entry, in: world, context: modelContext))
        let page = world.addPage(kind: .character, in: modelContext)
        page.characterRole = .playable
        page.setReference(.page(classPage), role: LinkRole.characterClass, in: modelContext)
        page.setAttributeNumber("dnd5e.classLevel", 1)
        let levelling = try context(for: page)
        #expect(levelling.needs.spellsToLearn == 2)
        #expect(levelling.progression.hitDieSides == 6)
    }

    @Test func aClassWithoutATableCantBeLevelled() throws {
        let (world, modelContext) = try makeWorld()
        let classPage = world.addPage(kind: .characterClass, in: modelContext)
        classPage.setAttributeText("dnd5e.hitDie", "d8")
        let page = world.addPage(kind: .character, in: modelContext)
        page.characterRole = .playable
        page.setReference(.page(classPage), role: LinkRole.characterClass, in: modelContext)
        #expect(LevelUp.context(for: page) == nil)
    }

    @Test func nobodyLevelsPastTwentyOrWithoutBeingPlayable() throws {
        let (world, modelContext) = try makeWorld()
        let capped = character(class: "srd51.class.fighter", level: 20, in: world, modelContext)
        #expect(LevelUp.context(for: capped) == nil)
        let npc = character(class: "srd51.class.fighter", in: world, modelContext)
        npc.characterRole = .nonPlayable
        #expect(LevelUp.context(for: npc) == nil)
    }

    @Test func aCharacterCanBeTakenFromLevelOneToTwenty() throws {
        let (world, modelContext) = try makeWorld()
        let page = character(class: "srd51.class.fighter", in: world, modelContext)
        while let levelling = LevelUp.context(for: page) {
            var choices = LevelUpChoices()
            if levelling.needs.choosesSubclass { choices.subclass = "srd51.subclass.champion" }
            if levelling.needs.hasImprovement { choices.abilityIncreases = [.strength: 2] }
            LevelUp.apply(choices, to: levelling, in: modelContext)
        }
        #expect(page.attributeNumber("dnd5e.classLevel") == 20)
        #expect(page.attributeNumber("dnd5e.proficiencyBonus") == 6)
        #expect(page.attributeText("dnd5e.hitDice") == "20d10")
        #expect(page.attributeNumber("dnd5e.strength") == 20)
        guard case .entries(let features)? = page.attributes["dnd5e.classFeatures"] else { Issue.record("Expected features"); return }
        #expect(features.map(\.name).contains("Indomitable") && features.map(\.name).contains("Champion: Survivor"))
    }
}
