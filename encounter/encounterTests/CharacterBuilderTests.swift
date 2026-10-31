//
//  CharacterBuilderTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

struct CharacterRulesTests {
    @Test func modifiersFollowTheScoreInPairs() {
        #expect([1, 8, 9, 10, 11, 12, 13, 15, 18, 20].map(CharacterRules.modifier(for:)) == [-5, -1, -1, 0, 0, 1, 1, 2, 4, 5])
        #expect(CharacterRules.modifierText(for: 16) == "+3")
        #expect(CharacterRules.modifierText(for: 8) == "−1")
        #expect(CharacterRules.modifierText(for: 10) == "+0")
    }

    @Test func pointBuyCostsMatchTheRules() {
        #expect((8...15).compactMap(CharacterRules.pointBuyCost(of:)) == [0, 1, 2, 3, 4, 5, 7, 9])
        #expect(CharacterRules.pointBuyCost(of: 7) == nil && CharacterRules.pointBuyCost(of: 16) == nil)
        // The standard array costs exactly the budget.
        #expect(CharacterRules.pointBuyTotal(of: CharacterRules.standardArray) == 27)
        #expect(CharacterRules.pointBuyTotal(of: [15, 15, 15, 8, 8, 8]) == 27)
        #expect(CharacterRules.pointBuyTotal(of: [13, 13, 13, 12, 12, 12]) == 27)
        #expect(CharacterRules.pointBuyTotal(of: [16, 8, 8, 8, 8, 8]) == nil)
    }

    @Test func proficiencyBonusRisesEveryFourLevels() {
        #expect([1, 4, 5, 8, 9, 12, 13, 16, 17, 20].map(CharacterRules.proficiencyBonus(atLevel:)) == [2, 2, 3, 3, 4, 4, 5, 5, 6, 6])
    }

    @Test func hitPointsAndArmorClassAtLevel1() {
        #expect(CharacterRules.hitPointsAtLevel1(hitDie: 10, constitution: 14) == 12)
        #expect(CharacterRules.hitPointsAtLevel1(hitDie: 6, constitution: 8) == 5)
        #expect(CharacterRules.hitPointsAtLevel1(hitDie: 6, constitution: 1) == 1)
        #expect(CharacterRules.unarmoredArmorClass(dexterity: 16) == 13)
        #expect(CharacterRules.hitDieSides("d12") == 12 && CharacterRules.hitDieSides("D8 per Cleric level") == 8 && CharacterRules.hitDieSides("none") == nil)
    }

    @Test func numbersCanBeWordsOrDigits() {
        #expect(CharacterRules.number(from: "Two") == 2 && CharacterRules.number(from: "10") == 10 && CharacterRules.number(from: "many") == nil)
    }
}

@MainActor
struct CharacterBuilderTests {
    private func makeContext() throws -> ModelContext {
        ModelContext(try AppSchema.makeContainer(inMemory: true))
    }

    private func makeWorld(_ edition: LibraryEdition, in context: ModelContext) -> World {
        let world = World(name: "W", system: .dnd5e)
        world.edition = edition
        context.insert(world)
        return world
    }

    private func source(_ key: String) throws -> ContentSource {
        CharacterContent.source(for: try #require(Library.shared.entry(forKey: key)))
    }

    // MARK: Reading the rules text

    @Test func everyRaceOf2014HasAbilityBonusesTheBuilderUnderstands() {
        let expected: [String: [Ability: Int]] = [
            "Dwarf": [.constitution: 2], "Elf": [.dexterity: 2], "Halfling": [.dexterity: 2], "Gnome": [.intelligence: 2],
            "Dragonborn": [.strength: 2, .charisma: 1], "Half-Orc": [.strength: 2, .constitution: 1], "Tiefling": [.intelligence: 1, .charisma: 2],
            "Human": Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 1) }), "Half-Elf": [.charisma: 2],
        ]
        for race in Library.shared.topLevelEntries(.race, in: .srd51) {
            let text = race.entries.first { $0.name == "Ability Score Increase" }?.text ?? ""
            let bonuses = AbilityBonuses.parse(text)
            #expect(bonuses.isUnderstood, "\(race.name)")
            #expect(bonuses.fixed == expected[race.name], "\(race.name)")
            if race.name == "Half-Elf" { #expect(bonuses.choices?.count == 2 && bonuses.choices?.amount == 1) } else { #expect(bonuses.choices == nil) }
        }
        #expect(!AbilityBonuses.parse("You grow wings.").isUnderstood)
    }

    @Test func subracesAddToTheirRacesBonuses() throws {
        let hill = try #require(Library.shared.entry(forKey: "srd51.race.hill-dwarf"))
        #expect(AbilityBonuses.parse(hill.entries.first { $0.name == "Ability Score Increase" }?.text ?? "").fixed == [.wisdom: 1])
        let merged = CharacterContent.source(for: try #require(Library.shared.entry(forKey: "srd51.race.dwarf")), subrace: hill)
        #expect(merged.name == "Hill Dwarf")
        #expect(merged.entries.contains { $0.name == "Dwarven Toughness" } && merged.entries.contains { $0.name == "Stonecunning" })
    }

    @Test func everyClassAndBackgroundHasSkillsTheBuilderUnderstands() {
        let skillNames = Set(Library.shared.entries(.skill, in: .srd52).map(\.name))
        for edition in LibraryEdition.allCases {
            for entry in Library.shared.topLevelEntries(.class, in: edition) {
                guard case .text(let text)? = entry.attributes["dnd5e.skillChoices"] else { Issue.record("\(entry.name) has no skills"); continue }
                let choice = SkillChoice.parse(text)
                #expect(choice != nil, "\(entry.name) in \(edition): \(text)")
                #expect(choice.map { $0.count >= 2 && $0.options.count >= $0.count } == true, "\(entry.name)")
                #expect(choice?.options.allSatisfy { skillNames.contains($0) } == true, "\(entry.name) in \(edition) has \(choice?.options ?? [])")
            }
            for entry in Library.shared.entries(.background, in: edition) {
                guard case .text(let text)? = entry.attributes["dnd5e.backgroundSkills"] else { Issue.record("\(entry.name) has no skills"); continue }
                #expect(SkillList.parse(text).count == 2 && SkillList.parse(text).allSatisfy { skillNames.contains($0) }, "\(entry.name)")
            }
        }
        #expect(SkillChoice.parse("Choose two from Arcana, History, Insight, Investigation, Medicine, and Religion")
                == SkillChoice(count: 2, options: ["Arcana", "History", "Insight", "Investigation", "Medicine", "Religion"]))
        #expect(SkillChoice.parse("Choose 2: Animal Handling, Athletics, or Survival") == SkillChoice(count: 2, options: ["Animal Handling", "Athletics", "Survival"]))
        #expect(SkillChoice.parse("Pick whatever") == nil)
        #expect(SkillChoice.parse("Choose any three")?.count == 3 && SkillChoice.parse("Choose any 3 skills (see “Playing the Game”)")?.options.count == 18)
        #expect(SkillList.parse("Insight and Religion") == ["Insight", "Religion"])
    }

    @Test func startingEquipmentIsSplitIntoItsChoices() throws {
        // 2024: one lettered group per class and background.
        let fighter = try #require(Library.shared.entry(forKey: "srd52.class.fighter"))
        guard case .text(let fighterText)? = fighter.attributes["dnd5e.startingEquipment"] else { Issue.record("no equipment"); return }
        let groups = EquipmentGroup.parse(fighterText)
        #expect(groups.count == 1 && groups[0].options.map(\.label) == ["A", "B", "C"])
        #expect(groups[0].options[0].text.hasPrefix("Chain Mail, Greatsword") && groups[0].options[2].text == "155 GP")

        // 2014: a group for each bullet, some of them choices and some fixed.
        let fighter51 = try #require(Library.shared.entry(forKey: "srd51.class.fighter"))
        guard case .text(let text51)? = fighter51.attributes["dnd5e.startingEquipment"] else { Issue.record("no equipment"); return }
        let groups51 = EquipmentGroup.parse(text51)
        #expect(groups51.count == 4)
        #expect(groups51[0].options.map(\.label) == ["a", "b"] && groups51[0].options[0].text == "chain mail")
        #expect(groups51[0].options[1].text == "leather armor, longbow, and 20 arrows")

        let acolyte51 = try #require(Library.shared.entry(forKey: "srd51.background.acolyte"))
        guard case .text(let acolyteText)? = acolyte51.attributes["dnd5e.backgroundEquipment"] else { Issue.record("no equipment"); return }
        #expect(EquipmentGroup.parse(acolyteText).count == 1 && !EquipmentGroup.parse(acolyteText)[0].isChoice)

        for edition in LibraryEdition.allCases {
            for entry in Library.shared.topLevelEntries(.class, in: edition) {
                guard case .text(let text)? = entry.attributes["dnd5e.startingEquipment"] else { continue }
                #expect(!EquipmentGroup.parse(text).isEmpty, "\(entry.name) in \(edition)")
            }
        }
    }

    @Test func spellcastingIsReadFromTheLevel1Feature() throws {
        func limits(_ key: String) throws -> SpellLimits {
            let entry = try #require(Library.shared.entry(forKey: key))
            let feature = entry.entries.first { $0.level == 1 && ($0.name == "Spellcasting" || $0.name == "Pact Magic") }
            return feature.map { SpellLimits.parse($0.text) } ?? SpellLimits()
        }
        var all: [String: SpellLimits] = [:]
        for edition in ["srd51", "srd52"] {
            for name in ["bard", "cleric", "druid", "fighter", "barbarian", "paladin", "ranger", "sorcerer", "warlock", "wizard"] {
                all["\(edition).\(name)"] = try limits("\(edition).class.\(name)")
            }
        }
        // 2014: known spells for bards, sorcerers and warlocks, and prepared spells for the others.
        #expect(all["srd51.bard"] == SpellLimits(cantrips: 2, spells: .fixed(4), ability: .charisma))
        #expect(all["srd51.sorcerer"]?.cantrips == 4 && all["srd51.sorcerer"]?.spells == .fixed(2))
        #expect(all["srd51.warlock"]?.cantrips == 2 && all["srd51.warlock"]?.spells == .fixed(2))
        #expect(all["srd51.cleric"] == SpellLimits(cantrips: 3, spells: .abilityPlusLevel(.wisdom), ability: .wisdom))
        #expect(all["srd51.druid"]?.spells == .abilityPlusLevel(.wisdom))
        #expect(all["srd51.wizard"]?.cantrips == 3 && all["srd51.wizard"]?.spells == .abilityPlusLevel(.intelligence))
        // Fighters don't cast, and paladins and rangers cast from level 2 in 2014.
        #expect(all["srd51.fighter"]?.isCaster == false && all["srd51.paladin"]?.isCaster == false)

        // 2024: prepared spells are a fixed number, and paladins and rangers cast from level 1.
        #expect(all["srd52.wizard"]?.cantrips == 3 && all["srd52.wizard"]?.spells == .fixed(4))
        #expect(all["srd52.cleric"]?.spells == .fixed(4) && all["srd52.cleric"]?.cantrips == 3)
        #expect(all["srd52.sorcerer"]?.cantrips == 4 && all["srd52.sorcerer"]?.spells == .fixed(2))
        #expect(all["srd52.paladin"]?.spells == .fixed(2) && all["srd52.paladin"]?.cantrips == 0)
        #expect(all["srd52.ranger"]?.spells == .fixed(2))
        #expect(all["srd52.bard"]?.ability == .charisma)
        #expect(all["srd52.fighter"]?.isCaster == false && all["srd52.barbarian"]?.isCaster == false)
    }

    // MARK: Planning a character

    private func fighterDraft(_ world: World) throws -> (CharacterDraft, ContentSource, ContentSource, ContentSource) {
        var draft = CharacterDraft()
        draft.name = "Brannoch"
        let race = try source("srd51.race.dwarf")
        let fighter = try source("srd51.class.fighter")
        let acolyte = try source("srd51.background.acolyte")
        draft.race = race.choice
        draft.characterClass = fighter.choice
        draft.background = acolyte.choice
        draft.scores = [.strength: 15, .dexterity: 13, .constitution: 14, .intelligence: 8, .wisdom: 12, .charisma: 10]
        draft.skills = ["Athletics", "Perception"]
        draft.equipmentChoices = [0: 0, 1: 0, 2: 0, 3: 0]
        return (draft, race, fighter, acolyte)
    }

    @Test func a2014DwarfFighterGetsTheRacesBonusAndTheClassesHitDie() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        let (draft, race, fighter, acolyte) = try fighterDraft(world)

        let plan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: fighter, background: acolyte)

        #expect(plan.problems.isEmpty, "\(plan.problems)")
        #expect(plan.scores[.constitution] == 16)
        #expect(plan.hitPoints == 13)               // 10 + 3
        #expect(plan.hitDie == "d10")
        #expect(plan.armorClass == 11)              // 10 + Dex 13 (+1)
        #expect(plan.savingThrows == ["Strength", "Constitution"])
        #expect(Set(plan.skills) == ["Insight", "Religion", "Athletics", "Perception"])
        #expect(plan.proficiencyBonus == 2)
        #expect(plan.equipment.first == "chain mail")
        #expect(plan.equipment.contains("A holy symbol (a gift to you when you entered the priesthood)"))
        #expect(plan.equipment.contains("a prayer book or prayer wheel") && plan.equipment.contains("a pouch containing 15 gp"))
    }

    @Test func aPlanSaysWhatIsMissing() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        let empty = CharacterPlanner.plan(CharacterDraft(), edition: .srd51, race: nil, characterClass: nil, background: nil)
        #expect(empty.problems.contains("Give the character a name."))
        #expect(empty.problems.contains("Choose a race or species."))
        #expect(empty.problems.contains("Choose a class."))
        #expect(empty.problems.contains("Choose a background."))
        #expect(empty.problems.contains("Use each number of the standard array once."))

        var (draft, race, fighter, acolyte) = try fighterDraft(world)
        draft.skills = ["Athletics"]
        draft.equipmentChoices = [:]
        let partial = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: fighter, background: acolyte)
        #expect(partial.problems.contains("Choose 2 class skills."))
        #expect(partial.problems.contains("Choose your starting equipment."))
    }

    @Test func standardArrayPointBuyAndManualScoresAreEachChecked() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        var (draft, race, fighter, acolyte) = try fighterDraft(world)
        func problems() -> [String] { CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: fighter, background: acolyte).problems }

        draft.method = .standardArray
        draft.scores = Dictionary(uniqueKeysWithValues: zip(Ability.allCases, CharacterRules.standardArray))
        #expect(problems().isEmpty)
        draft.scores[.strength] = 14
        #expect(problems().contains("Use each number of the standard array once."))

        draft.method = .pointBuy
        draft.scores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 8) })
        #expect(problems().isEmpty)
        draft.scores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 15) })
        #expect(problems().contains { $0.hasPrefix("Point buy is over") })
        draft.scores[.strength] = 16
        #expect(problems().contains("Point buy scores go from 8 to 15."))

        draft.method = .manual
        draft.scores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 18) })
        #expect(problems().isEmpty)
        draft.scores[.wisdom] = 21
        #expect(problems().contains("Scores go from 1 to 20."))
    }

    @Test func bonusesNeverRaiseAScoreAboveTwenty() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        var (draft, race, fighter, acolyte) = try fighterDraft(world)
        draft.method = .manual
        draft.scores[.constitution] = 19
        let plan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: fighter, background: acolyte)
        #expect(plan.scores[.constitution] == 20)
    }

    @Test func aHalfElfChoosesTwoOtherAbilitiesForTheirBonus() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        var (draft, _, fighter, acolyte) = try fighterDraft(world)
        let halfElf = try source("srd51.race.half-elf")
        draft.raceBonusChoices = [.strength]
        let one = CharacterPlanner.plan(draft, edition: .srd51, race: halfElf, characterClass: fighter, background: acolyte)
        #expect(one.problems.contains("Choose 2 abilities for the race’s bonus."))

        draft.raceBonusChoices = [.strength, .wisdom]
        let two = CharacterPlanner.plan(draft, edition: .srd51, race: halfElf, characterClass: fighter, background: acolyte)
        #expect(two.bonuses == [.charisma: 2, .strength: 1, .wisdom: 1])
        // Charisma, already raised by 2, isn't offered again.
        draft.raceBonusChoices = [.charisma, .wisdom]
        #expect(CharacterPlanner.plan(draft, edition: .srd51, race: halfElf, characterClass: fighter, background: acolyte).problems.contains("Choose 2 abilities for the race’s bonus."))
    }

    @Test func in2024TheBackgroundGivesTheBonuses() throws {
        let context = try makeContext()
        let world = makeWorld(.srd52, in: context)
        var draft = CharacterDraft()
        draft.name = "Wren"
        let species = try source("srd52.race.elf")
        let wizard = try source("srd52.class.wizard")
        let sage = try source("srd52.background.sage")     // Constitution, Intelligence, Wisdom
        draft.race = species.choice; draft.characterClass = wizard.choice; draft.background = sage.choice
        draft.scores = [.strength: 8, .dexterity: 14, .constitution: 13, .intelligence: 15, .wisdom: 12, .charisma: 10]
        draft.skills = ["Investigation", "Medicine"]
        draft.equipmentChoices = [0: 0, 1: 0]

        let missing = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: wizard, background: sage)
        #expect(missing.problems.contains("Choose how the background raises your ability scores."))

        draft.backgroundBonus = .twoAndOne(two: .intelligence, one: .constitution)
        let plan = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: wizard, background: sage)
        #expect(plan.problems.isEmpty, "\(plan.problems)")
        #expect(plan.scores[.intelligence] == 17 && plan.scores[.constitution] == 14)
        #expect(plan.hitPoints == 8)               // d6 + Con 14 (+2)
        #expect(Set(plan.skills) == ["Arcana", "History", "Investigation", "Medicine"])
        #expect(plan.cantripLimit == 3 && plan.spellLimit == 4)

        draft.backgroundBonus = .twoAndOne(two: .strength, one: .constitution)
        #expect(CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: wizard, background: sage).problems.contains("Choose two different abilities the background offers."))
        draft.backgroundBonus = .oneEach
        let each = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: wizard, background: sage)
        #expect(each.bonuses == [.constitution: 1, .intelligence: 1, .wisdom: 1])
    }

    @Test func aCasterNeedsItsSpellsAndCantNeverTakeMoreThanItsLimit() throws {
        let context = try makeContext()
        let world = makeWorld(.srd52, in: context)
        var draft = CharacterDraft()
        draft.name = "Wren"
        let wizard = try source("srd52.class.wizard")
        draft.characterClass = wizard.choice
        let spells = CharacterContent.spells(level: 0, for: wizard, in: world)
        #expect(spells.contains { $0.name == "Fire Bolt" } && !spells.contains { $0.name == "Cure Wounds" })
        #expect(CharacterContent.spells(level: 1, for: wizard, in: world).contains { $0.name == "Magic Missile" })

        draft.cantrips = Set(spells.prefix(4).map(\.key))
        let plan = CharacterPlanner.plan(draft, edition: .srd52, race: nil, characterClass: wizard, background: nil)
        #expect(plan.problems.contains("Too many cantrips: this class knows 3."))
    }

    @Test func the2014PreparedCasterHasAnAbilityBasedNumberOfSpells() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        var (draft, race, _, acolyte) = try fighterDraft(world)
        let cleric = try source("srd51.class.cleric")
        draft.characterClass = cleric.choice
        draft.scores[.wisdom] = 16
        let plan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: cleric, background: acolyte)
        #expect(plan.spellLimit == 4)               // 1 + Wis 16 (+3)
        #expect(plan.cantripLimit == 3)
    }

    // MARK: Creating the page

    @Test func theCharacterPageHoldsEverythingTheBuilderWorkedOut() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        var (draft, race, fighter, acolyte) = try fighterDraft(world)
        draft.alignment = "Lawful Good"
        let plan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: fighter, background: acolyte)

        let page = CharacterBuilder.create(draft, plan: plan, race: race, characterClass: fighter, background: acolyte, subclass: nil, in: world, context: context)

        #expect(page.kind == .character && page.characterRole == .playable)
        #expect(page.title == "Brannoch")
        #expect(page.summary == "Dwarf Fighter, level 1")
        #expect(page.reference(role: LinkRole.race) == .library("srd51.race.dwarf"))
        #expect(page.reference(role: LinkRole.characterClass) == .library("srd51.class.fighter"))
        #expect(page.reference(role: LinkRole.background) == .library("srd51.background.acolyte"))
        #expect(page.attributeNumber("dnd5e.constitution") == 16)
        #expect(page.attributeNumber("dnd5e.hitPoints") == 13)
        #expect(page.attributeText("dnd5e.hitDice") == "1d10")
        #expect(page.attributeNumber("dnd5e.armorClass") == 11)
        #expect(page.attributeNumber("dnd5e.classLevel") == 1)
        #expect(page.attributeNumber("dnd5e.proficiencyBonus") == 2)
        #expect(page.attributeText("dnd5e.alignment") == "Lawful Good")
        #expect(page.attributeText("dnd5e.speed") == "25 feet")
        #expect(page.attributeText("dnd5e.savingThrowProficiencies") == "Strength, Constitution")
        #expect(page.attributeText("dnd5e.skillProficiencies").contains("Athletics"))
        guard case .entries(let traits)? = page.attributes["dnd5e.racialTraits"], case .entries(let features)? = page.attributes["dnd5e.classFeatures"],
              case .entries(let equipment)? = page.attributes["dnd5e.equipment"]
        else { Issue.record("Expected traits, features and equipment"); return }
        #expect(traits.contains { $0.name == "Darkvision" })
        #expect(features.map(\.name) == ["Fighting Style", "Second Wind"])
        #expect(equipment.first?.name == "chain mail")
        #expect(world.pages?.contains(page) == true)
    }

    @Test func aLevelOneSubclassAndSpellsAreAddedToThePage() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        var (draft, race, _, acolyte) = try fighterDraft(world)
        let cleric = try source("srd51.class.cleric")
        draft.characterClass = cleric.choice
        draft.skills = ["History", "Medicine"]
        draft.equipmentChoices = [0: 0, 1: 0, 2: 0, 3: 0, 4: 0]
        let subclasses = CharacterContent.levelOneSubclasses(of: cleric, in: world)
        #expect(subclasses.map(\.name) == ["Life Domain"])
        draft.subclass = subclasses[0].key
        draft.cantrips = ["srd51.spell.guidance", "srd51.spell.light", "srd51.spell.sacred-flame"]
        draft.spells = ["srd51.spell.cure-wounds"]
        let plan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: cleric, background: acolyte)

        let page = CharacterBuilder.create(draft, plan: plan, race: race, characterClass: cleric, background: acolyte, subclass: subclasses[0], in: world, context: context)

        #expect(page.libraryKey(role: "subclass") == "srd51.subclass.life-domain")
        guard case .entries(let features)? = page.attributes["dnd5e.classFeatures"], case .entries(let spells)? = page.attributes["dnd5e.spells"] else {
            Issue.record("Expected features and spells")
            return
        }
        #expect(features.contains { $0.name == "Life Domain: Bonus Proficiency" })
        #expect(spells.map(\.name).contains("Cure Wounds") && spells.count == 4)
        // No 2024 class picks its subclass at level 1.
        #expect(CharacterContent.levelOneSubclasses(of: try source("srd52.class.cleric"), in: makeWorld(.srd52, in: context)).isEmpty)
    }

    @Test func aHomebrewRaceAndClassWorkLikeLibraryOnes() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        let raceEntry = try #require(Library.shared.entry(forKey: "srd51.race.gnome"))
        let racePage = try #require(Library.shared.makeCustomVersion(of: raceEntry, in: world, context: context))
        racePage.title = "Moss Gnome"
        let classEntry = try #require(Library.shared.entry(forKey: "srd51.class.wizard"))
        let classPage = try #require(Library.shared.makeCustomVersion(of: classEntry, in: world, context: context))
        classPage.title = "Hedge Mage"

        #expect(CharacterContent.races(in: world).contains { $0.name == "Moss Gnome" })
        #expect(CharacterContent.classes(in: world).contains { $0.name == "Hedge Mage" })
        let race = CharacterContent.source(for: racePage)
        let hedgeMage = CharacterContent.source(for: classPage)
        #expect(AbilityBonuses.parse(race.entryText(named: "Ability Score Increase") ?? "").fixed == [.intelligence: 2])
        #expect(hedgeMage.text("dnd5e.hitDie") == "d6")
        // A class made from a library class keeps its spell list.
        #expect(CharacterContent.spells(level: 0, for: hedgeMage, in: world).contains { $0.name == "Fire Bolt" })
        #expect(CharacterContent.resolve(.page(racePage.id), in: world)?.name == "Moss Gnome")
    }

    @Test func toolOptionsComeFromTheLibraryInBothEditions() {
        let context = ModelContext(try! AppSchema.makeContainer(inMemory: true))
        for edition in LibraryEdition.allCases {
            let world = makeWorld(edition, in: context)
            let options = CharacterContent.toolOptions(in: world)
            #expect(options[.artisan]?.count ?? 0 >= 17, "\(edition)")
            #expect(options[.musical]?.contains("Lute") == true, "\(edition)")
            #expect(options[.gaming]?.contains("Dice set") == true || options[.gaming]?.contains("Dice") == true, "\(edition)")
        }
        let plain = World(name: "Plain")
        context.insert(plain)
        #expect(CharacterContent.toolOptions(in: plain).isEmpty)
    }

    @Test func aMonkChoosesATool_andTheEquipmentUsesIt_in2024() throws {
        let context = try makeContext()
        let world = makeWorld(.srd52, in: context)
        var draft = CharacterDraft()
        draft.name = "Kess"
        let species = try source("srd52.race.human")
        let monk = try source("srd52.class.monk")
        let acolyte = try source("srd52.background.acolyte")
        draft.race = species.choice; draft.characterClass = monk.choice; draft.background = acolyte.choice
        draft.scores = [.strength: 8, .dexterity: 15, .constitution: 13, .intelligence: 10, .wisdom: 14, .charisma: 12]
        draft.backgroundBonus = .oneEach
        draft.skills = ["Acrobatics", "Athletics"]
        draft.equipmentChoices = [0: 0, 1: 0]
        let options = CharacterContent.toolOptions(in: world)

        let missing = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: monk, background: acolyte, toolOptions: options)
        #expect(missing.toolChoices.map(\.id) == ["class"])
        #expect(missing.problems.contains("Choose 1 tool for the class."))
        #expect(missing.toolChoices.first?.options.contains("Lute") == true && missing.toolChoices.first?.options.contains("Smith’s Tools") == true)

        draft.toolPicks["class"] = ["Lute"]
        let plan = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: monk, background: acolyte, toolOptions: options)
        #expect(plan.problems.isEmpty, "\(plan.problems)")
        #expect(plan.tools == ["Lute", "Calligrapher’s Supplies"])
        #expect(plan.equipment.contains("Lute") && !plan.equipment.contains { $0.contains("chosen for the tool proficiency") })

        draft.toolPicks["class"] = ["Lute", "Flute"]
        #expect(CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: monk, background: acolyte, toolOptions: options).problems.contains("Choose 1 tool for the class."))
    }

    @Test func aSoldierAndABardEachChooseToolsInTheirOwnStep() throws {
        let context = try makeContext()
        let world = makeWorld(.srd52, in: context)
        let options = CharacterContent.toolOptions(in: world)
        var draft = CharacterDraft()
        draft.name = "Dag"
        let species = try source("srd52.race.human")
        let bard = try source("srd52.class.bard")
        let soldier = try source("srd52.background.soldier")
        draft.race = species.choice; draft.characterClass = bard.choice; draft.background = soldier.choice
        draft.backgroundBonus = .oneEach

        let plan = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: bard, background: soldier, toolOptions: options)
        #expect(plan.toolChoices.map(\.id) == ["class", "background"])
        #expect(plan.toolChoices.map(\.count) == [3, 1])
        #expect(plan.toolChoices[1].options.contains("Dragonchess"))

        draft.toolPicks = ["class": ["Lute", "Lyre", "Flute"], "background": ["Dragonchess"]]
        draft.equipmentChoices = [0: 0, 1: 0]
        let done = CharacterPlanner.plan(draft, edition: .srd52, race: species, characterClass: bard, background: soldier, toolOptions: options)
        #expect(!done.problems.contains { $0.contains("tool") })
        #expect(done.tools == ["Flute", "Lute", "Lyre", "Dragonchess"])
        #expect(done.equipment.contains("Flute") && done.equipment.contains("Dragonchess"))
    }

    @Test func the2014BardAndMonkChooseToolsToo() throws {
        let context = try makeContext()
        let world = makeWorld(.srd51, in: context)
        let options = CharacterContent.toolOptions(in: world)
        var (draft, race, _, acolyte) = try fighterDraft(world)
        let bard = try source("srd51.class.bard")
        draft.characterClass = bard.choice
        let plan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: bard, background: acolyte, toolOptions: options)
        #expect(plan.toolChoices.first?.count == 3)
        #expect(plan.toolChoices.first?.options.contains("Lute") == true)
        let monk = try source("srd51.class.monk")
        let monkPlan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: monk, background: acolyte, toolOptions: options)
        #expect(monkPlan.toolChoices.first?.options.contains("Smith’s tools") == true && monkPlan.toolChoices.first?.options.contains("Lute") == true)
        // A class with named tools has no choice to make but still has the tools.
        let rogue = try source("srd51.class.rogue")
        let roguePlan = CharacterPlanner.plan(draft, edition: .srd51, race: race, characterClass: rogue, background: acolyte, toolOptions: options)
        #expect(roguePlan.toolChoices.isEmpty && roguePlan.tools == ["Thieves’ tools"])
    }

    @Test func theToolsStepOnlyAppearsWhenThereIsAChoice() throws {
        let context = try makeContext()
        let world = World(name: "W", system: .dnd5e)
        world.edition = .srd52
        context.insert(world)
        let model = CharacterBuilderModel(world: world)
        #expect(!model.steps.contains(.tools))
        model.chooseClass(try source("srd52.class.monk"))
        #expect(model.steps.contains(.tools))
        model.chooseClass(try source("srd52.class.fighter"))
        #expect(!model.steps.contains(.tools))
    }

    @Test func everyChoiceSaysWhereItComesFrom() throws {
        let context = try makeContext()
        let world = makeWorld(.srd52, in: context)
        let elf = try #require(Library.shared.entry(forKey: "srd52.race.elf"))
        let page = try #require(Library.shared.makeCustomVersion(of: elf, in: world, context: context))
        #expect(try source("srd52.race.elf").sourceTitle == "SRD 5.2.1")
        #expect(try source("srd51.race.elf").sourceTitle == "SRD 5.1")
        // A world's own page says so, even one copied from the library.
        #expect(CharacterContent.source(for: page).sourceTitle == "This World")
    }

    @Test func raceClassAndBackgroundListsHaveTheLibraryFirstAndOnlyForDnD() throws {
        let context = try makeContext()
        let dnd = makeWorld(.srd52, in: context)
        #expect(CharacterContent.races(in: dnd).count == 9 && CharacterContent.classes(in: dnd).count == 12 && CharacterContent.backgrounds(in: dnd).count == 4)
        let plain = World(name: "Plain")
        context.insert(plain)
        #expect(CharacterContent.races(in: plain).isEmpty)
    }
}

struct EquipmentItemsTests {
    @Test func aPackageIsSplitIntoItsItems() {
        #expect(EquipmentGroup.items(in: "Spear, 5 Daggers, Artisan’s Tools or Musical Instrument chosen for the tool proficiency above, Explorer’s Pack, and 11 GP")
                == ["Spear", "5 Daggers", "Artisan’s Tools or Musical Instrument chosen for the tool proficiency above", "Explorer’s Pack", "11 GP"])
        #expect(EquipmentGroup.items(in: "Calligrapher’s Supplies, Book (prayers), Holy Symbol, Parchment (10 sheets), Robe, 8 GP")
                == ["Calligrapher’s Supplies", "Book (prayers)", "Holy Symbol", "Parchment (10 sheets)", "Robe", "8 GP"])
        // 2014 wording joins with "and" and has no capitals.
        #expect(EquipmentGroup.items(in: "a light crossbow and 20 bolts") == ["a light crossbow", "20 bolts"])
        #expect(EquipmentGroup.items(in: "leather armor, longbow, and 20 arrows") == ["leather armor", "longbow", "20 arrows"])
        #expect(EquipmentGroup.items(in: "An explorer’s pack and four javelins") == ["An explorer’s pack", "four javelins"])
        #expect(EquipmentGroup.items(in: "75 GP") == ["75 GP"])
    }

    @Test func bracketsAndNamesWithAndStayWhole() {
        #expect(EquipmentGroup.items(in: "Arcane Focus (Staff, or Wand), Block and Tackle, and Rope") == ["Arcane Focus (Staff, or Wand)", "Block and Tackle", "Rope"])
        #expect(EquipmentGroup.items(in: "a dagger, a pouch (coins and a key)") == ["a dagger", "a pouch (coins and a key)"])
    }

    @Test func everyStartingPackageInTheLibrarySplitsIntoSeveralItemsOrOne() {
        for edition in LibraryEdition.allCases {
            let texts = (Library.shared.topLevelEntries(.class, in: edition) + Library.shared.entries(.background, in: edition)).flatMap { entry -> [String] in
                let key = entry.kind == .class ? "dnd5e.startingEquipment" : "dnd5e.backgroundEquipment"
                guard case .text(let text)? = entry.attributes[key] else { return [] }
                return EquipmentGroup.parse(text).flatMap { $0.options.map(\.text) }
            }
            #expect(!texts.isEmpty)
            for text in texts {
                let items = EquipmentGroup.items(in: text)
                #expect(!items.isEmpty && items.allSatisfy { !$0.hasPrefix("and ") && !$0.hasSuffix(",") }, "\(text)")
            }
        }
    }
}

struct ToolProficiencyTests {
    @Test func toolTextIsReadAsNamedToolsOrAChoice() {
        #expect(ToolProficiency.parse("None") == ToolProficiency())
        #expect(ToolProficiency.parse("Herbalism kit").fixed == ["Herbalism kit"])
        #expect(ToolProficiency.parse("Thieves’ Tools").fixed == ["Thieves’ Tools"])
        #expect(ToolProficiency.parse("Choose one kind of Gaming Set (see “Equipment”)") == ToolProficiency(count: 1, categories: [.gaming]))
        #expect(ToolProficiency.parse("Three musical instruments of your choice") == ToolProficiency(count: 3, categories: [.musical]))
        #expect(ToolProficiency.parse("Choose 3 Musical Instruments (see “Equipment”)") == ToolProficiency(count: 3, categories: [.musical]))
        #expect(ToolProficiency.parse("Choose one type of artisan’s tools or one musical instrument") == ToolProficiency(count: 1, categories: [.artisan, .musical]))
        #expect(ToolProficiency.parse("Choose one type of Artisan’s Tools or Musical Instrument (see “Equipment”)") == ToolProficiency(count: 1, categories: [.artisan, .musical]))
    }

    @Test func everyToolTextInTheLibraryIsUnderstood() {
        for edition in LibraryEdition.allCases {
            for entry in Library.shared.topLevelEntries(.class, in: edition) + Library.shared.entries(.background, in: edition) {
                for key in ["dnd5e.toolProficiencies", "dnd5e.backgroundTools"] {
                    guard case .text(let text)? = entry.attributes[key] else { continue }
                    let parsed = ToolProficiency.parse(text)
                    #expect(parsed.isChoice || !parsed.fixed.isEmpty || text == "None", "\(entry.name): \(text)")
                }
            }
        }
    }

    @Test func anItemThatNamesAToolChoiceGetsTheTool() {
        #expect(EquipmentGroup.resolvingTool(in: "Artisan’s Tools or Musical Instrument chosen for the tool proficiency above", with: "Lute") == "Lute")
        #expect(EquipmentGroup.resolvingTool(in: "Gaming Set (same as above)", with: "Dice") == "Dice")
        #expect(EquipmentGroup.resolvingTool(in: "Musical Instrument of your choice", with: "Flute") == "Flute")
        #expect(EquipmentGroup.resolvingTool(in: "Spear", with: "Lute") == "Spear")
        #expect(EquipmentGroup.resolvingTool(in: "Gaming Set (same as above)", with: nil) == "Gaming Set (same as above)")
    }
}

@MainActor
struct CharacterBuilderModelTests {
    @Test func theBuilderMovesThroughItsStepsInOrder() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .dnd5e)
        context.insert(world)
        let model = CharacterBuilderModel(world: world)

        #expect(model.step == .concept && !model.canGoBack && model.canGoForward)
        model.goForward()
        #expect(model.step == .race)
        for _ in 0..<5 { model.goForward() }
        #expect(model.step == .equipment)
        model.goForward()
        // The review comes last. The spells step is left out until a class that casts is chosen.
        #expect(model.step == .review && !model.canGoForward)
        model.goBack()
        #expect(model.step == .equipment)
        #expect(!model.steps.contains(.spells))
    }
}
