//
//  CharacterSheetTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// A random source that gives the same numbers every time, so a roll can be checked.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

struct DiceTests {
    @Test func diceAreReadFromTheWaysTheRulesWriteThem() throws {
        #expect(DiceExpression("d20") == DiceExpression(count: 1, sides: 20))
        #expect(DiceExpression("2d6") == DiceExpression(count: 2, sides: 6))
        #expect(DiceExpression("1d4 + 1") == DiceExpression(count: 1, sides: 4, modifier: 1))
        #expect(DiceExpression("1d8+3") == DiceExpression(count: 1, sides: 8, modifier: 3))
        #expect(DiceExpression("1d8 - 2") == DiceExpression(count: 1, sides: 8, modifier: -2))
        #expect(DiceExpression("1d8 − 2") == DiceExpression(count: 1, sides: 8, modifier: -2))
        #expect(DiceExpression("8d6 fire") == nil && DiceExpression("hello") == nil && DiceExpression("0d6") == nil && DiceExpression("2d1") == nil)
    }

    @Test func diceReadBackAsTheyAreWritten() {
        #expect(DiceExpression(count: 1, sides: 20).text == "d20")
        #expect(DiceExpression(count: 2, sides: 6, modifier: 3).text == "2d6 + 3")
        #expect(DiceExpression(count: 1, sides: 20, modifier: -1).text == "d20 − 1")
        #expect(DiceExpression(count: 1, sides: 8).adding(3).adding(-1).modifier == 2)
        #expect(DiceExpression(count: 1, sides: 6).withCount(3).text == "3d6")
    }

    @Test func aRollIsTheDiceAndWhatIsAdded() {
        var generator = SeededGenerator(seed: 7)
        let result = DiceRoller.roll(DiceExpression(count: 3, sides: 6, modifier: 2), using: &generator)
        #expect(result.dice.count == 3 && result.dice.allSatisfy { (1...6).contains($0) })
        #expect(result.total == result.dice.reduce(0, +) + 2)
        #expect(result.breakdown.hasSuffix("= \(result.total)"))
    }

    @Test func everyFaceCanComeUpAndNoneOutsideTheDie() {
        var generator = SeededGenerator(seed: 1)
        let faces = (0..<2000).flatMap { _ in DiceRoller.roll(DiceExpression(count: 1, sides: 20), using: &generator).dice }
        #expect(Set(faces) == Set(1...20))
    }

    @Test func advantageKeepsTheHigherAndDisadvantageTheLower() {
        for seed in UInt64(1)...40 {
            var a = SeededGenerator(seed: seed), d = SeededGenerator(seed: seed)
            let high = DiceRoller.roll(.d20, mode: .advantage, using: &a)
            let low = DiceRoller.roll(.d20, mode: .disadvantage, using: &d)
            #expect(high.discarded.count == 1 && low.discarded.count == 1)
            #expect(high.dice[0] >= high.discarded[0] && low.dice[0] <= low.discarded[0])
            // The same two dice were rolled.
            #expect(Set([high.dice[0], high.discarded[0]]) == Set([low.dice[0], low.discarded[0]]))
        }
    }

    @Test func advantageOnlyAppliesToASingleD20() {
        var generator = SeededGenerator(seed: 3)
        let damage = DiceRoller.roll(DiceExpression(count: 1, sides: 8), mode: .advantage, using: &generator)
        #expect(damage.discarded.isEmpty && damage.dice.count == 1)
    }

    @Test func aCriticalHitDoublesTheDiceButNotWhatIsAdded() {
        var generator = SeededGenerator(seed: 5)
        let result = DiceRoller.roll(DiceExpression(count: 2, sides: 6, modifier: 3), critical: true, using: &generator)
        #expect(result.dice.count == 4 && result.expression.modifier == 3)
        #expect(result.total == result.dice.reduce(0, +) + 3)
    }

    @Test func aNaturalTwentyAndOneAreRecognised() {
        #expect(RollResult(expression: .d20, dice: [20]).isNaturalTwenty && RollResult(expression: .d20, dice: [1]).isNaturalOne)
        #expect(!RollResult(expression: .d20, dice: [19]).isNaturalTwenty)
        #expect(!RollResult(expression: DiceExpression(count: 1, sides: 8), dice: [8]).isNaturalTwenty)
    }
}

struct SheetRulesTests {
    @Test func itemsAreMatchedWhateverHowTheyAreWritten() {
        #expect(SheetRules.itemName("a longsword") == "longsword")
        #expect(SheetRules.itemName("Two Handaxes") == "handaxes")
        #expect(SheetRules.itemName("Dagger (2)") == "dagger")
        #expect(SheetRules.itemName("4 javelins") == "javelins")
        #expect(SheetRules.isSameItem("handaxes", "Handaxe"))
        #expect(SheetRules.isSameItem("a dagger", "Dagger"))
        #expect(SheetRules.isSameItem("chain mail", "Chain Mail"))
        #expect(!SheetRules.isSameItem("short sword", "longsword"))
    }

    @Test func propertiesAreSplitOutsideBrackets() {
        #expect(SheetRules.splitProperties("Finesse, light, thrown (range 20/60)") == ["Finesse", "light", "thrown (range 20/60)"])
        #expect(SheetRules.splitProperties("Ammunition (Range 150/600; Arrow), Heavy, Two-Handed") == ["Ammunition (Range 150/600; Arrow)", "Heavy", "Two-Handed"])
    }

    @Test func aWeaponIsReadFromItsLibraryEntry() throws {
        let longsword = try #require(Library.shared.entry(forKey: "srd51.equipment.longsword"))
        let weapon = try #require(SheetRules.weapon(named: longsword.name, attributes: longsword.attributes))
        #expect(weapon.damage == DiceExpression(count: 1, sides: 8) && weapon.damageType == "slashing")
        #expect(weapon.versatileDamage == DiceExpression(count: 1, sides: 10))
        #expect(!weapon.isRanged && !weapon.isFinesse)
        let chain = try #require(Library.shared.entry(forKey: "srd51.equipment.chain-mail"))
        #expect(SheetRules.weapon(named: chain.name, attributes: chain.attributes) == nil)
    }

    @Test func theAbilityAWeaponUsesFollowsItsProperties() throws {
        func weapon(_ key: String) throws -> SheetRules.Weapon {
            let entry = try #require(Library.shared.entry(forKey: key))
            return try #require(SheetRules.weapon(named: entry.name, attributes: entry.attributes))
        }
        let strong: [Ability: Int] = [.strength: 16, .dexterity: 12]
        let nimble: [Ability: Int] = [.strength: 10, .dexterity: 16]
        #expect(try weapon("srd51.equipment.longsword").ability(scores: nimble) == .strength)
        #expect(try weapon("srd51.equipment.longbow").ability(scores: strong) == .dexterity)
        #expect(try weapon("srd51.equipment.rapier").ability(scores: nimble) == .dexterity)
        #expect(try weapon("srd51.equipment.rapier").ability(scores: strong) == .strength)
        #expect(try weapon("srd51.equipment.dagger").isThrown)
        #expect(try weapon("srd52.equipment.longbow").range == "Ammunition (Range 150/600; Arrow)")
    }

    @Test func proficiencyFollowsTheClassesWeaponList() throws {
        func weapon(_ key: String) throws -> SheetRules.Weapon {
            let entry = try #require(Library.shared.entry(forKey: key))
            return try #require(SheetRules.weapon(named: entry.name, attributes: entry.attributes))
        }
        let all = "Simple weapons, martial weapons"
        #expect(SheetRules.isProficient(with: try weapon("srd51.equipment.longsword"), proficiencies: all))
        #expect(SheetRules.isProficient(with: try weapon("srd51.equipment.dagger"), proficiencies: all))
        let wizard = "Daggers, darts, slings, quarterstaffs, light crossbows"
        #expect(SheetRules.isProficient(with: try weapon("srd51.equipment.dagger"), proficiencies: wizard))
        #expect(!SheetRules.isProficient(with: try weapon("srd51.equipment.longsword"), proficiencies: wizard))
        let rogue2024 = "Simple weapons and Martial weapons that have the Finesse or Light property"
        #expect(SheetRules.isProficient(with: try weapon("srd52.equipment.rapier"), proficiencies: rogue2024))
        #expect(!SheetRules.isProficient(with: try weapon("srd52.equipment.longsword"), proficiencies: rogue2024))
        #expect(!SheetRules.isProficient(with: try weapon("srd51.equipment.longsword"), proficiencies: ""))
    }

    @Test func spellDifficultyAndAttackBonusUseTheCastingScore() {
        #expect(SheetRules.spellSaveDC(proficiencyBonus: 3, abilityScore: 16) == 14)
        #expect(SheetRules.spellAttackBonus(proficiencyBonus: 3, abilityScore: 16) == 6)
        #expect(["Bard", "Paladin", "Sorcerer", "Warlock"].allSatisfy { SheetRules.spellcastingAbility(forClass: $0) == .charisma })
        #expect(["Cleric", "Druid", "Ranger"].allSatisfy { SheetRules.spellcastingAbility(forClass: $0) == .wisdom })
        #expect(SheetRules.spellcastingAbility(forClass: "Wizard") == .intelligence && SheetRules.spellcastingAbility(forClass: "Fighter") == nil)
    }

    private func effect(_ key: String, characterLevel: Int = 1) throws -> (SheetRules.SpellEffect, Int) {
        let entry = try #require(Library.shared.entry(forKey: key))
        guard case .number(let level)? = entry.attributes["dnd5e.spellLevel"] else { throw CancellationError() }
        return (SheetRules.spellEffect(summary: entry.summary, spellLevel: Int(level), characterLevel: characterLevel, name: entry.name), Int(level))
    }

    @Test func fireballIsADexteritySaveForEightD6WithHalfOnASave() throws {
        for edition in ["srd51", "srd52"] {
            let (effect, level) = try effect("\(edition).spell.fireball")
            #expect(effect.save == .dexterity && !effect.isAttack && effect.halfOnSave)
            #expect(effect.damage == DiceExpression(count: 8, sides: 6) && effect.damageType == "fire")
            #expect(SheetRules.damage(of: effect, spellLevel: level, slotLevel: 3)?.text == "8d6")
            #expect(SheetRules.damage(of: effect, spellLevel: level, slotLevel: 5)?.text == "10d6")
        }
    }

    @Test func aSpellAttackIsRecognisedAndACantripGrowsWithTheLevel() throws {
        let (low, _) = try effect("srd51.spell.fire-bolt", characterLevel: 4)
        #expect(low.isAttack && low.save == nil && low.damage == DiceExpression(count: 1, sides: 10) && low.damageType == "fire")
        #expect(try effect("srd51.spell.fire-bolt", characterLevel: 5).0.damage?.text == "2d10")
        #expect(try effect("srd52.spell.fire-bolt", characterLevel: 11).0.damage?.text == "3d10")
        #expect(try effect("srd52.spell.fire-bolt", characterLevel: 17).0.damage?.text == "4d10")
        #expect(SheetRules.cantripDice(forLevel: 1) == 1 && SheetRules.cantripDice(forLevel: 20) == 4)
    }

    @Test func magicMissileHasNoRollToMakeAndDealsItsFixedDamage() throws {
        for edition in ["srd51", "srd52"] {
            let (effect, _) = try effect("\(edition).spell.magic-missile")
            #expect(!effect.isAttack && effect.save == nil)
            #expect(effect.damage == DiceExpression(count: 1, sides: 4, modifier: 1) && effect.damageType == "force")
        }
    }

    @Test func healingAddsTheCastingModifierAndGrowsWithTheSlot() throws {
        let (old, level) = try effect("srd51.spell.cure-wounds")
        #expect(SheetRules.healing(of: old, spellLevel: level, slotLevel: 1, abilityModifier: 3)?.text == "d8 + 3")
        #expect(SheetRules.healing(of: old, spellLevel: level, slotLevel: 3, abilityModifier: 3)?.text == "3d8 + 3")
        let (new, newLevel) = try effect("srd52.spell.cure-wounds")
        #expect(SheetRules.healing(of: new, spellLevel: newLevel, slotLevel: 1, abilityModifier: 3)?.text == "2d8 + 3")
        #expect(SheetRules.healing(of: new, spellLevel: newLevel, slotLevel: 2, abilityModifier: 3)?.text == "4d8 + 3")
        #expect(new.damage == nil)
    }

    @Test func aSpellWithNothingToRollGivesNothing() throws {
        let (effect, _) = try effect("srd51.spell.mage-hand")
        #expect(effect.damage == nil && effect.healing == nil && effect.save == nil && !effect.isAttack)
    }
}

@MainActor
struct CharacterSheetTests {
    private func makeWorld(_ edition: LibraryEdition = .srd51) throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        world.edition = edition
        context.insert(world)
        return (world, context)
    }

    private func character(
        class classKey: String, level: Int = 1, hitPoints: Int = 20, scores: [Ability: Int] = [:], equipment: [String] = [],
        skills: String = "", saves: String = "", spells: [String] = [], in world: World, _ context: ModelContext
    ) -> Page {
        let page = world.addPage(kind: .character, in: context)
        page.title = "Hero"
        page.characterRole = .playable
        page.setReference(.library(classKey), role: LinkRole.characterClass, in: context)
        page.setAttributeNumber("dnd5e.classLevel", Double(level))
        page.setAttributeNumber("dnd5e.hitPoints", Double(hitPoints))
        page.setAttributeNumber("dnd5e.proficiencyBonus", Double(CharacterRules.proficiencyBonus(atLevel: level)))
        for ability in Ability.allCases { page.setAttributeNumber(ability.attributeKey, Double(scores[ability] ?? 10)) }
        page.setAttributeText("dnd5e.skillProficiencies", skills)
        page.setAttributeText("dnd5e.savingThrowProficiencies", saves)
        if !equipment.isEmpty { page.attributes["dnd5e.equipment"] = .entries(equipment.map { EntryValue(name: $0) }) }
        if !spells.isEmpty { page.attributes["dnd5e.spells"] = .entries(spells.map { EntryValue(name: $0) }) }
        return page
    }

    private func sheet(_ page: Page) throws -> CharacterSheet { try #require(CharacterSheet(page: page)) }

    @Test func onlyADnDCharacterHasASheet() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let plain = World(name: "Plain")
        context.insert(plain)
        let page = plain.addPage(kind: .character, in: context)
        #expect(CharacterSheet(page: page) == nil)
        let (world, dndContext) = try makeWorld()
        #expect(CharacterSheet(page: world.addPage(kind: .place, in: dndContext)) == nil)
    }

    @Test func skillsAndSavesAddTheProficiencyBonusOnlyWhenProficient() throws {
        let (world, context) = try makeWorld()
        let page = character(
            class: "srd51.class.fighter", level: 5, scores: [.strength: 16, .dexterity: 14, .wisdom: 12],
            skills: "Athletics, Perception", saves: "Strength, Constitution", in: world, context
        )
        let sheet = try sheet(page)
        #expect(sheet.proficiencyBonus == 3)
        let skills = Dictionary(uniqueKeysWithValues: sheet.skills.map { ($0.name, $0) })
        #expect(skills.count == 18)
        #expect(skills["Athletics"]?.bonus == 6 && skills["Athletics"]?.isProficient == true)
        #expect(skills["Acrobatics"]?.bonus == 2 && skills["Acrobatics"]?.isProficient == false)
        #expect(skills["Perception"]?.bonus == 4)
        let saves = Dictionary(uniqueKeysWithValues: sheet.saves.map { ($0.ability, $0) })
        #expect(saves[.strength]?.bonus == 6 && saves[.dexterity]?.bonus == 2 && saves[.constitution]?.bonus == 3)
        #expect(sheet.passivePerception == 14 && sheet.initiative == 2)
    }

    @Test func aProficiencyCanBeSwitchedOnAndOffOnThePage() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", skills: "Athletics", in: world, context)
        let sheet = try sheet(page)
        sheet.setSkill("Stealth", proficient: true)
        sheet.setSkill("Athletics", proficient: false)
        sheet.setSave(.wisdom, proficient: true)
        #expect(page.attributeText("dnd5e.skillProficiencies") == "Stealth")
        #expect(page.attributeText("dnd5e.savingThrowProficiencies") == "Wisdom")
        #expect(try self.sheet(page).skills.first { $0.name == "Stealth" }?.isProficient == true)
    }

    @Test func weaponsInTheEquipmentBecomeAttacksWithTheRightBonuses() throws {
        let (world, context) = try makeWorld()
        let page = character(
            class: "srd51.class.fighter", level: 1, scores: [.strength: 16, .dexterity: 12],
            equipment: ["chain mail", "a longsword", "two handaxes", "light crossbow", "An explorer’s pack"], in: world, context
        )
        let attacks = try sheet(page).attacks
        #expect(attacks.map(\.weapon.name) == ["Longsword", "Handaxe"])
        let longsword = try #require(attacks.first)
        #expect(longsword.ability == .strength && longsword.isProficient)
        // +3 for Strength and +2 for proficiency, and 1d8 + 3.
        #expect(longsword.attackBonus == 5 && longsword.damage.text == "d8 + 3" && longsword.versatileDamage?.text == "d10 + 3")
    }

    @Test func aWizardIsProficientOnlyWithItsOwnWeapons() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.wizard", scores: [.dexterity: 14, .strength: 8], equipment: ["a dagger", "a quarterstaff"], in: world, context)
        let attacks = try sheet(page).attacks
        #expect(attacks.allSatisfy { $0.isProficient })
        // A dagger is finesse, so the better of the two scores is used.
        let dagger = try #require(attacks.first { $0.weapon.name == "Dagger" })
        #expect(dagger.ability == .dexterity && dagger.attackBonus == 4)
    }

    @Test func spellcastingNumbersComeFromTheClassesAbility() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.wizard", level: 5, scores: [.intelligence: 17], in: world, context)
        let sheet = try sheet(page)
        #expect(sheet.spellcastingAbility == .intelligence)
        #expect(sheet.spellSaveDC == 14 && sheet.spellAttackBonus == 6)
        #expect(sheet.slotsByLevel == [4, 3, 2, 0, 0, 0, 0, 0, 0])
        let fighter = try self.sheet(character(class: "srd51.class.fighter", in: world, context))
        #expect(fighter.spellSaveDC == nil && fighter.slotsByLevel == [Int](repeating: 0, count: 9))
    }

    @Test func aCustomClassMadeFromAWizardCastsWithIntelligence() throws {
        let (world, context) = try makeWorld()
        let entry = try #require(Library.shared.entry(forKey: "srd51.class.wizard"))
        let classPage = try #require(Library.shared.makeCustomVersion(of: entry, in: world, context: context))
        classPage.title = "Hedge Mage"
        let page = world.addPage(kind: .character, in: context)
        page.setReference(.page(classPage), role: LinkRole.characterClass, in: context)
        page.setAttributeNumber("dnd5e.classLevel", 1)
        #expect(try sheet(page).spellcastingAbility == .intelligence)
        #expect(try sheet(page).className == "Hedge Mage")
    }

    @Test func damageComesOffTemporaryHitPointsFirstAndHealingStopsAtTheMaximum() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 20, in: world, context)
        let sheet = try sheet(page)
        #expect(sheet.currentHitPoints == 20 && sheet.temporaryHitPoints == 0)
        sheet.gainTemporaryHitPoints(5)
        sheet.gainTemporaryHitPoints(3)
        #expect(sheet.temporaryHitPoints == 5)
        sheet.takeDamage(8)
        #expect(try self.sheet(page).temporaryHitPoints == 0 && self.sheet(page).currentHitPoints == 17)
        sheet.takeDamage(100)
        #expect(try self.sheet(page).currentHitPoints == 0)
        sheet.heal(7)
        #expect(try self.sheet(page).currentHitPoints == 7)
        sheet.heal(100)
        #expect(try self.sheet(page).currentHitPoints == 20)
    }

    @Test func aHitDieHealsAndIsUsedUp() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", level: 3, hitPoints: 30, scores: [.constitution: 14], in: world, context)
        let sheet = try sheet(page)
        sheet.takeDamage(20)
        sheet.spendHitDie()
        // The average d10 is 6, plus 2 for Constitution.
        #expect(try self.sheet(page).currentHitPoints == 10 + 8 && self.sheet(page).hitDiceRemaining == 2)
        sheet.spendHitDie(rolled: 1)
        #expect(try self.sheet(page).currentHitPoints == 18 + 3 && self.sheet(page).hitDiceRemaining == 1)
    }

    @Test func spellSlotsAreSpentAndNeverGoBelowNoneOrAboveTheMaximum() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.wizard", level: 3, in: world, context)
        let sheet = try sheet(page)
        #expect(sheet.slotsRemaining == [4, 2, 0, 0, 0, 0, 0, 0, 0])
        #expect(sheet.spendSlot(level: 2))
        #expect(sheet.spendSlot(level: 2))
        #expect(!(try self.sheet(page)).spendSlot(level: 2))
        #expect(!(try self.sheet(page)).spendSlot(level: 3))
        #expect(try self.sheet(page).slotsRemaining == [4, 0, 0, 0, 0, 0, 0, 0, 0])
        try self.sheet(page).setSlotsUsed(level: 1, to: 99)
        #expect(try self.sheet(page).slotsUsed[0] == 4)
        try self.sheet(page).setSlotsUsed(level: 1, to: -3)
        #expect(try self.sheet(page).slotsUsed[0] == 0)
    }

    @Test func slotsUsedFitTheNewLevelAfterLevellingDown() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.wizard", level: 5, in: world, context)
        try sheet(page).setSlotsUsed(level: 3, to: 2)
        page.setAttributeNumber("dnd5e.classLevel", 1)
        #expect(try sheet(page).slotsUsed == [0, 0, 0, 0, 0, 0, 0, 0, 0])
    }

    @Test func aLongRestRestoresEverythingAndHalfTheHitDice() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.cleric", level: 4, hitPoints: 30, in: world, context)
        let sheet = try sheet(page)
        sheet.takeDamage(25)
        sheet.gainTemporaryHitPoints(4)
        sheet.spendSlot(level: 1)
        sheet.spendHitDie()
        sheet.spendHitDie()
        sheet.spendHitDie()
        sheet.longRest()
        let rested = try self.sheet(page)
        #expect(rested.currentHitPoints == 30 && rested.temporaryHitPoints == 0 && rested.slotsUsed.allSatisfy { $0 == 0 })
        // Three were spent and half of four (two) come back.
        #expect(rested.hitDiceRemaining == 4 - 3 + 2)
    }

    @Test func aShortRestRestoresAWarlocksPactSlotsButNotOtherCastersSlots() throws {
        let (world, context) = try makeWorld()
        let warlock = character(class: "srd51.class.warlock", level: 5, in: world, context)
        let pact = try sheet(warlock)
        #expect(pact.usesPactMagic && pact.slotsByLevel == [0, 0, 2, 0, 0, 0, 0, 0, 0])
        pact.spendSlot(level: 3)
        pact.shortRest()
        #expect(try self.sheet(warlock).slotsUsed.allSatisfy { $0 == 0 })

        let wizard = character(class: "srd51.class.wizard", level: 3, in: world, context)
        try sheet(wizard).spendSlot(level: 1)
        try sheet(wizard).shortRest()
        #expect(try self.sheet(wizard).slotsUsed[0] == 1)
    }

    @Test func theSpellsAreFoundInTheLibraryAndOrderedByLevel() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.wizard", spells: ["Magic Missile", "fire bolt", "Home Brew Hex", "Shield"], in: world, context)
        let spells = try sheet(page).spells
        #expect(spells.map(\.name) == ["fire bolt", "Home Brew Hex", "Magic Missile", "Shield"])
        #expect(spells.map(\.level) == [0, 0, 1, 1])
        #expect(spells[0].entry?.key == "srd51.spell.fire-bolt" && spells[1].entry == nil)
    }
}

@MainActor
struct ActionCardTests {
    private func makeWorld(_ edition: LibraryEdition = .srd51) throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        world.edition = edition
        context.insert(world)
        return (world, context)
    }

    private func character(
        class classKey: String, level: Int, scores: [Ability: Int] = [:], equipment: [String] = [], spells: [String] = [],
        in world: World, _ context: ModelContext
    ) -> CharacterSheet {
        let page = world.addPage(kind: .character, in: context)
        page.setReference(.library(classKey), role: LinkRole.characterClass, in: context)
        page.setAttributeNumber("dnd5e.classLevel", Double(level))
        page.setAttributeNumber("dnd5e.hitPoints", 30)
        page.setAttributeNumber("dnd5e.proficiencyBonus", Double(CharacterRules.proficiencyBonus(atLevel: level)))
        for ability in Ability.allCases { page.setAttributeNumber(ability.attributeKey, Double(scores[ability] ?? 10)) }
        if !equipment.isEmpty { page.attributes["dnd5e.equipment"] = .entries(equipment.map { EntryValue(name: $0) }) }
        if !spells.isEmpty { page.attributes["dnd5e.spells"] = .entries(spells.map { EntryValue(name: $0) }) }
        return CharacterSheet(page: page)!
    }

    @Test func aWeaponCardSaysWhatToRollAndWhatToAdd() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.fighter", level: 1, scores: [.strength: 16], equipment: ["a longsword"], in: world, context)
        let card = sheet.card(for: try #require(sheet.attacks.first))
        #expect(card.title == "Longsword")
        let attack = try #require(card.rolls.first { $0.kind == .attack })
        #expect(attack.dice.text == "d20 + 5" && attack.instruction == "Roll d20 + 5")
        #expect(attack.addedFrom == "Strength +3 · proficiency +2" && attack.allowsAdvantage)
        let damage = card.rolls.filter { $0.kind == .damage }
        #expect(damage.map(\.dice.text) == ["d8 + 3", "d10 + 3"])
        #expect(!damage[0].allowsAdvantage)
    }

    @Test func aWeaponTheCharacterCantUseWellSaysSo() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.wizard", level: 1, equipment: ["a longsword"], in: world, context)
        // A wizard isn't proficient, so the bonus is only the modifier.
        let card = sheet.card(for: try #require(sheet.attacks.first))
        let attack = try #require(card.rolls.first { $0.kind == .attack })
        #expect(attack.dice.text == "d20" && attack.note != nil)
    }

    @Test func skillsSavesAndAbilitiesGiveACheckToRoll() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.fighter", level: 1, scores: [.dexterity: 14, .strength: 8], in: world, context)
        #expect(sheet.card(forAbility: .dexterity).rolls.first?.dice.text == "d20 + 2")
        #expect(sheet.card(forAbility: .strength).rolls.first?.dice.text == "d20 − 1")
        let acrobatics = try #require(sheet.skills.first { $0.name == "Acrobatics" })
        #expect(sheet.card(for: acrobatics).rolls.first?.addedFrom == "Dexterity +2")
        #expect(sheet.initiativeCard.rolls.first?.dice.text == "d20 + 2")
        #expect(sheet.card(forAbility: .dexterity).rolls.first?.kind == .check)
    }

    @Test func aSaveSpellSaysWhatTargetsRollAndAnAttackSpellWhatTheCasterRolls() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.wizard", level: 5, scores: [.intelligence: 17], spells: ["Fireball", "Fire Bolt"], in: world, context)
        let fireball = try #require(sheet.spells.first { $0.name == "Fireball" })
        let card = sheet.card(for: fireball, slotLevel: 3)
        #expect(card.rolls.map(\.kind) == [.damage] && card.rolls[0].dice.text == "8d6")
        #expect(card.notes.contains("Each target makes a Dexterity saving throw against DC 14."))
        let upcast = sheet.card(for: fireball, slotLevel: 5)
        #expect(upcast.rolls[0].dice.text == "10d6" && upcast.subtitle.contains("cast at 5th level"))

        let bolt = sheet.card(for: try #require(sheet.spells.first { $0.name == "Fire Bolt" }))
        #expect(bolt.rolls.map(\.kind) == [.attack, .damage])
        #expect(bolt.rolls[0].dice.text == "d20 + 6" && bolt.rolls[1].dice.text == "2d10")
    }

    @Test func aHealingSpellRollsHealing() throws {
        let (world, context) = try makeWorld(.srd52)
        let sheet = character(class: "srd52.class.cleric", level: 3, scores: [.wisdom: 16], spells: ["Cure Wounds"], in: world, context)
        let spell = try #require(sheet.spells.first)
        let healing = try #require(sheet.card(for: spell, slotLevel: 2).rolls.first)
        #expect(healing.kind == .healing && healing.dice.text == "4d8 + 3")
    }

    @Test func aCardAlwaysCarriesTheSpellsTextAndFacts() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.wizard", level: 1, spells: ["Light"], in: world, context)
        let card = sheet.card(for: try #require(sheet.spells.first))
        #expect(card.rolls.isEmpty && !card.text.isEmpty)
        #expect(card.subtitle.hasPrefix("Cantrip"))
        #expect(card.notes.contains { $0.contains("action") })
    }

    @Test func slotsToCastWithAreTheSpellsLevelAndUpWhereOneIsLeft() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.wizard", level: 5, spells: ["Magic Missile", "Fireball", "Light"], in: world, context)
        let missile = try #require(sheet.spells.first { $0.name == "Magic Missile" })
        let fireball = try #require(sheet.spells.first { $0.name == "Fireball" })
        let light = try #require(sheet.spells.first { $0.name == "Light" })
        #expect(sheet.castableSlotLevels(for: missile) == [1, 2, 3])
        #expect(sheet.castableSlotLevels(for: fireball) == [3])
        #expect(sheet.castableSlotLevels(for: light).isEmpty)
        sheet.setSlotsUsed(level: 3, to: 2)
        let again = try #require(CharacterSheet(page: sheet.page))
        #expect(again.castableSlotLevels(for: missile) == [1, 2])
        #expect(again.castableSlotLevels(for: fireball).isEmpty)
    }

    @Test func castingSpendsTheSlotItNamesAndACantripSpendsNothing() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.wizard", level: 3, spells: ["Magic Missile", "Light", "Detect Magic"], in: world, context)
        let missile = try #require(sheet.spells.first { $0.name == "Magic Missile" })
        #expect(sheet.cast(missile, slotLevel: 2))
        #expect(try #require(CharacterSheet(page: sheet.page)).slotsRemaining == [4, 1, 0, 0, 0, 0, 0, 0, 0])
        #expect(sheet.cast(try #require(sheet.spells.first { $0.name == "Light" }), slotLevel: nil))
        #expect(try #require(CharacterSheet(page: sheet.page)).slotsRemaining == [4, 1, 0, 0, 0, 0, 0, 0, 0])
        // A slot can't be used for a spell of a higher level, or one that has none left.
        #expect(!sheet.cast(missile, slotLevel: 3))
        #expect(sheet.cast(missile, slotLevel: 2))
        #expect(!(try #require(CharacterSheet(page: sheet.page))).cast(missile, slotLevel: 2))
    }

    @Test func aRitualCanBeCastWithoutASlotButOtherSpellsCant() throws {
        let (world, context) = try makeWorld()
        let sheet = character(class: "srd51.class.wizard", level: 3, spells: ["Detect Magic", "Magic Missile"], in: world, context)
        let detect = try #require(sheet.spells.first { $0.name == "Detect Magic" })
        #expect(detect.isRitual)
        #expect(sheet.cast(detect, slotLevel: nil))
        #expect(!sheet.cast(try #require(sheet.spells.first { $0.name == "Magic Missile" }), slotLevel: nil))
        #expect(try #require(CharacterSheet(page: sheet.page)).slotsUsed.allSatisfy { $0 == 0 })
    }
}

@MainActor
struct SheetExtrasTests {
    private func makeWorld(_ edition: LibraryEdition = .srd51) throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        world.edition = edition
        context.insert(world)
        return (world, context)
    }

    private func character(
        class classKey: String, level: Int = 1, hitPoints: Int = 20, scores: [Ability: Int] = [:], skills: String = "",
        spells: [String] = [], features: [String] = [], in world: World, _ context: ModelContext
    ) -> Page {
        let page = world.addPage(kind: .character, in: context)
        page.setReference(.library(classKey), role: LinkRole.characterClass, in: context)
        page.setAttributeNumber("dnd5e.classLevel", Double(level))
        page.setAttributeNumber("dnd5e.hitPoints", Double(hitPoints))
        page.setAttributeNumber("dnd5e.proficiencyBonus", Double(CharacterRules.proficiencyBonus(atLevel: level)))
        for ability in Ability.allCases { page.setAttributeNumber(ability.attributeKey, Double(scores[ability] ?? 10)) }
        page.setAttributeText("dnd5e.skillProficiencies", skills)
        if !spells.isEmpty { page.attributes["dnd5e.spells"] = .entries(spells.map { EntryValue(name: $0) }) }
        if !features.isEmpty { page.attributes["dnd5e.classFeatures"] = .entries(features.map { EntryValue(name: $0) }) }
        return page
    }

    private func sheet(_ page: Page) throws -> CharacterSheet { try #require(CharacterSheet(page: page)) }

    // MARK: Expertise and Jack of All Trades

    @Test func expertiseDoublesTheProficiencyBonusAndNeedsProficiency() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.rogue", level: 5, scores: [.dexterity: 16], skills: "Stealth", in: world, context)
        let sheet = try sheet(page)
        func stealth() throws -> SheetSkill { try #require(self.sheet(page).skills.first { $0.name == "Stealth" }) }
        #expect(try stealth().proficiency == .proficient && stealth().bonus == 6)
        sheet.setSkill("Stealth", to: .expertise)
        #expect(try stealth().proficiency == .expertise && stealth().bonus == 9 && stealth().isProficient)
        #expect(page.attributeText("dnd5e.skillExpertise") == "Stealth")
        // Expertise can't be had without proficiency.
        sheet.setSkill("Stealth", proficient: false)
        #expect(try stealth().proficiency == .none && stealth().bonus == 3)
        #expect(page.attributeText("dnd5e.skillExpertise").isEmpty && page.attributeText("dnd5e.skillProficiencies").isEmpty)
        sheet.setSkill("Stealth", to: .expertise)
        sheet.setSkill("Stealth", to: .proficient)
        #expect(page.attributeText("dnd5e.skillExpertise").isEmpty && page.attributeText("dnd5e.skillProficiencies") == "Stealth")
    }

    @Test func expertiseShowsInTheSkillsCard() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.rogue", level: 1, scores: [.dexterity: 14], skills: "Stealth", in: world, context)
        let sheet = try sheet(page)
        sheet.setSkill("Stealth", to: .expertise)
        let card = try self.sheet(page).card(for: try #require(self.sheet(page).skills.first { $0.name == "Stealth" }))
        #expect(card.rolls[0].dice.text == "d20 + 6")
        #expect(card.rolls[0].addedFrom == "Dexterity +2 · expertise +4 (double proficiency)")
    }

    @Test func jackOfAllTradesAddsHalfTheBonusToEverythingNotProficient() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.bard", level: 5, scores: [.dexterity: 14, .strength: 10], skills: "Performance", features: ["Jack of All Trades"], in: world, context)
        let sheet = try sheet(page)
        #expect(sheet.hasJackOfAllTrades && sheet.halfProficiency == 1)
        let skills = Dictionary(uniqueKeysWithValues: sheet.skills.map { ($0.name, $0) })
        #expect(skills["Acrobatics"]?.proficiency == .half && skills["Acrobatics"]?.bonus == 3)
        #expect(skills["Performance"]?.proficiency == .proficient && skills["Performance"]?.bonus == 3)
        // Initiative and plain ability checks are checks too.
        #expect(sheet.initiative == 3)
        #expect(sheet.card(forAbility: .strength).rolls[0].dice.text == "d20 + 1")
        #expect(sheet.card(forAbility: .strength).rolls[0].addedFrom == "Strength +0 · half proficiency +1")
        // Half is rounded down: at level 1 the bonus is +2, so +1.
        let first = try self.sheet(character(class: "srd51.class.bard", level: 1, features: ["Jack of All Trades"], in: world, context))
        #expect(first.halfProficiency == 1)
        // Saving throws aren't ability checks.
        #expect(sheet.saves.allSatisfy { !$0.isProficient ? $0.bonus == sheet.modifier($0.ability) : true })
    }

    @Test func withoutJackOfAllTradesNonProficientSkillsGetNothing() throws {
        let (world, context) = try makeWorld()
        let sheet = try sheet(character(class: "srd51.class.bard", level: 5, in: world, context))
        #expect(!sheet.hasJackOfAllTrades && sheet.skills.allSatisfy { $0.proficiency == .none && $0.bonus == sheet.modifier($0.ability) })
    }

    // MARK: Death saves

    @Test func atZeroHitPointsAChallengeIsDying() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        let sheet = try sheet(page)
        #expect(!sheet.isAtZero && !sheet.isDying)
        sheet.takeDamage(10)
        let down = try self.sheet(page)
        #expect(down.isAtZero && down.isDying && !down.isStable && !down.isDead)
        #expect(down.deathSaveSuccesses == 0 && down.deathSaveFailures == 0)
    }

    @Test func deathSavesFollowTheRules() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(page).takeDamage(10)
        let sheet = try sheet(page)
        #expect(sheet.recordDeathSave(roll: 12) == .success)
        #expect(try self.sheet(page).deathSaveSuccesses == 1)
        #expect(sheet.recordDeathSave(roll: 10) == .success)
        #expect(sheet.recordDeathSave(roll: 9) == .failure)
        #expect(try self.sheet(page).deathSaveSuccesses == 2 && self.sheet(page).deathSaveFailures == 1)
        #expect(sheet.recordDeathSave(roll: 1) == .doubleFailure)
        #expect(try self.sheet(page).deathSaveFailures == 3 && self.sheet(page).isDead && !self.sheet(page).isDying)
    }

    @Test func threeSuccessesMakeACharacterStable() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(page).takeDamage(10)
        for _ in 0..<3 { try sheet(page).recordDeathSave(roll: 15) }
        let stable = try sheet(page)
        #expect(stable.isStable && !stable.isDying && !stable.isDead)
        // Damage ends being stable, and counts as a failure.
        stable.takeDamage(2)
        let hurt = try self.sheet(page)
        #expect(!hurt.isStable && hurt.isDying && hurt.deathSaveSuccesses == 0 && hurt.deathSaveFailures == 1)
    }

    @Test func aNaturalTwentyBringsBackOneHitPointAndHealingClearsTheMarks() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(page).takeDamage(10)
        try sheet(page).recordDeathSave(roll: 4)
        #expect(try sheet(page).recordDeathSave(roll: 20) == .revived)
        let up = try sheet(page)
        #expect(up.currentHitPoints == 1 && !up.isAtZero && up.deathSaveFailures == 0 && up.deathSaveSuccesses == 0)

        try sheet(page).takeDamage(5)
        try sheet(page).recordDeathSave(roll: 2)
        try sheet(page).heal(3)
        let healed = try sheet(page)
        #expect(healed.currentHitPoints == 3 && healed.deathSaveFailures == 0)
    }

    @Test func damageAtZeroIsAFailureAndMassiveDamageKills() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(page).takeDamage(10)
        try sheet(page).takeDamage(3)
        #expect(try sheet(page).deathSaveFailures == 1)
        try sheet(page).takeDamage(3)
        #expect(try sheet(page).deathSaveFailures == 2)

        // Damage that leaves as much over as the maximum kills outright: 10 to drop to 0, and 10 over.
        let big = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(big).takeDamage(20)
        #expect(try sheet(big).isDead)
        // Not quite enough.
        let almost = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(almost).takeDamage(19)
        #expect(try sheet(almost).isDying && !self.sheet(almost).isDead)
    }

    @Test func aLongRestClearsTheDeathSaves() throws {
        let (world, context) = try makeWorld()
        let page = character(class: "srd51.class.fighter", hitPoints: 10, in: world, context)
        try sheet(page).takeDamage(10)
        try sheet(page).recordDeathSave(roll: 3)
        try sheet(page).heal(1)
        try sheet(page).longRest()
        #expect(try sheet(page).deathSaveFailures == 0 && self.sheet(page).currentHitPoints == 10)
    }

    @Test func theDeathSaveCardIsABareD20() throws {
        let (world, context) = try makeWorld()
        let card = try sheet(character(class: "srd51.class.fighter", in: world, context)).deathSaveCard
        #expect(card.rolls.count == 1 && card.rolls[0].dice == .d20 && card.rolls[0].addedFrom == "No modifiers")
    }

    // MARK: Darts, rays and other extras at higher levels

    @Test func magicMissileHasMoreDartsWithEachSlotLevel() throws {
        for edition in [LibraryEdition.srd51, .srd52] {
            let (world, context) = try makeWorld(edition)
            let key = edition == .srd51 ? "srd51.class.wizard" : "srd52.class.wizard"
            let sheet = try sheet(character(class: key, level: 5, scores: [.intelligence: 16], spells: ["Magic Missile"], in: world, context))
            let missile = try #require(sheet.spells.first)
            let basic = try #require(sheet.card(for: missile, slotLevel: 1).rolls.first)
            #expect(basic.dice.text == "3d4 + 3" && basic.title.contains("3 darts"))
            let third = try #require(sheet.card(for: missile, slotLevel: 3).rolls.first)
            #expect(third.dice.text == "5d4 + 5" && third.title.contains("5 darts"))
            #expect(third.note?.contains("5 darts") == true)
        }
    }

    @Test func scorchingRayHasMoreRaysEachWithItsOwnAttack() throws {
        let (world, context) = try makeWorld()
        let sheet = try sheet(character(class: "srd51.class.wizard", level: 5, scores: [.intelligence: 16], spells: ["Scorching Ray"], in: world, context))
        let ray = try #require(sheet.spells.first)
        let card = sheet.card(for: ray, slotLevel: 4)
        // Two levels above the spell's own: three rays and two more.
        let attack = try #require(card.rolls.first { $0.kind == .attack })
        #expect(attack.note?.contains("5 rays") == true && attack.dice.text == "d20 + 6")
        let damage = try #require(card.rolls.first { $0.kind == .damage })
        #expect(damage.dice.text == "2d6" && damage.title.contains("each ray that hits"))
    }

    @Test func extraCreaturesAreCountedForSpellsThatAffectMore() throws {
        let (world, context) = try makeWorld()
        let sheet = try sheet(character(class: "srd51.class.cleric", level: 5, scores: [.wisdom: 14], spells: ["Bless"], in: world, context))
        let bless = try #require(sheet.spells.first)
        #expect(sheet.card(for: bless, slotLevel: 1).notes.allSatisfy { !$0.contains("more creature") })
        #expect(sheet.card(for: bless, slotLevel: 3).notes.contains { $0.contains("2 more creatures") })
    }

    @Test func projectilesAreOnlyForSpellsThatMakeThem() throws {
        let magicMissile = try #require(Library.shared.entry(forKey: "srd51.spell.magic-missile"))
        let effect = SheetRules.spellEffect(summary: magicMissile.summary, spellLevel: 1, characterLevel: 1)
        #expect(effect.baseProjectiles == 3 && effect.extraPerLevel == "dart" && effect.hasProjectiles)
        #expect(SheetRules.projectiles(of: effect, spellLevel: 1, slotLevel: 4) == 6)
        let fireball = try #require(Library.shared.entry(forKey: "srd51.spell.fireball"))
        let none = SheetRules.spellEffect(summary: fireball.summary, spellLevel: 3, characterLevel: 5)
        #expect(!none.hasProjectiles && SheetRules.projectiles(of: none, spellLevel: 3, slotLevel: 5) == nil)
    }
}
