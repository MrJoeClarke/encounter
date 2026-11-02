//
//  DnD5eSystem.swift
//  encounter
//

import Foundation

/// Attribute definitions for Dungeons & Dragons 5e. Names of options only, with no rules text.
struct DnD5eSystem: RuleSystem {
    let id = RuleSystemID.dnd5e

    var additionalPageKinds: Set<PageKind> { [.characterClass, .background, .feat, .spell] }
    var modules: RuleModules { [.library, .characterCreation, .advancement, .sheet, .conditions] }

    var libraryEditions: [LibraryEdition] { [.srd52, .srd51] }
    var rollModel: RollModel? { .d20 }
    var formulas: FormulaSet { Self.formulaSet }

    /// How D&D works out its numbers. Inputs are `score` (an ability score), `level`, `proficiencyMultiplier` (0, a half, 1 or 2
    /// for how well a skill is known) and, for the others, the names of the formulas they use.
    static let formulaSet = FormulaSet([
        "abilityModifier": "floor((score - 10) / 2)",
        "proficiencyBonus": "2 + floor((max(level, 1) - 1) / 4)",
        "spellSaveDC": "8 + proficiencyBonus + abilityModifier",
        "spellAttackBonus": "proficiencyBonus + abilityModifier",
        "skillBonus": "abilityModifier + floor(proficiencyBonus * proficiencyMultiplier)",
    ])

    var conditions: [ConditionDefinition] { Self.conditionList }
    var sheetLayout: SheetLayout? { Self.layout }

    /// The part of D&D's sheet that is only numbers from the page and formulas. The sheet screen still draws the rest (skills,
    /// attacks, spells, action cards) from `CharacterSheet`.
    static let layout = SheetLayout(sections: [
        SheetSection(id: "hitPoints", title: "Hit Points", rows: [
            SheetRow(id: "hitPoints", label: "Hit Points", kind: .resource("hitPoints")),
            SheetRow(id: "temporaryHitPoints", label: "Temporary Hit Points", kind: .resource("temporaryHitPoints")),
        ]),
        SheetSection(id: "abilities", title: "Abilities", rows: Ability.allCases.map {
            SheetRow(id: $0.attributeKey, label: $0.rawValue, kind: .stat(formula: "abilityModifier", inputs: ["score": $0.attributeKey]))
        } + [SheetRow(id: "proficiencyBonus", label: "Proficiency Bonus", kind: .stat(formula: "proficiencyBonus", inputs: [:]))]),
    ])


    /// What D&D's conditions do to the character's own rolls, for both editions: the input `edition2024` is 1 for the 2024
    /// rules and 0 for the 2014 rules, and exhaustion has levels. Movement and hit points are still worked out in code.
    static let conditionList: [ConditionDefinition] = {
        let attack: Set<String> = ["attack"]
        let d20Penalty = ConditionEffectRule.Effect.penalty(formula: "-2 * level", reason: "Exhaustion")
        let senses = { (name: String, sense: String) in
            ConditionEffectRule(["check"], .autoFail("\(name): automatically fails a check that needs \(sense)"))
        }
        let cantMoveSaves = { (name: String) in
            [ConditionEffectRule(["save.strength", "save.dexterity"], .autoFail("\(name): automatically fails Strength and Dexterity saving throws"))]
        }
        return [
            ConditionDefinition("blinded", "Blinded", effects: [.init(attack, .disadvantage), senses("Blinded", "sight")]),
            ConditionDefinition("charmed", "Charmed"),
            ConditionDefinition("deafened", "Deafened", effects: [senses("Deafened", "hearing")]),
            ConditionDefinition("exhaustion", "Exhaustion", hasLevels: true, effects: [
                .init(attack, .disadvantage, when: "(1 - edition2024) * max(0, min(1, level - 2))"),
                .init(["check", "initiative"], .disadvantage, when: "(1 - edition2024) * min(1, level)"),
                .init(["save"], .disadvantage, when: "(1 - edition2024) * max(0, min(1, level - 2))"),
                .init(["attack", "check", "save", "initiative"], d20Penalty, when: "edition2024"),
            ]),
            ConditionDefinition("frightened", "Frightened", effects: [.init(attack, .disadvantage), .init(["check", "initiative"], .disadvantage)]),
            ConditionDefinition("grappled", "Grappled", effects: [.init(attack, .disadvantage, when: "edition2024")]),
            ConditionDefinition("incapacitated", "Incapacitated", effects: [.init(["initiative"], .disadvantage, when: "edition2024")]),
            ConditionDefinition("invisible", "Invisible", effects: [.init(attack, .advantage), .init(["initiative"], .advantage, when: "edition2024")]),
            ConditionDefinition("paralyzed", "Paralyzed", effects: cantMoveSaves("Paralyzed")),
            ConditionDefinition("petrified", "Petrified", effects: cantMoveSaves("Petrified")),
            ConditionDefinition("poisoned", "Poisoned", effects: [.init(attack, .disadvantage), .init(["check", "initiative"], .disadvantage)]),
            ConditionDefinition("prone", "Prone", effects: [.init(attack, .disadvantage)]),
            ConditionDefinition("restrained", "Restrained", effects: [.init(attack, .disadvantage), .init(["save.dexterity"], .disadvantage)]),
            ConditionDefinition("stunned", "Stunned", effects: cantMoveSaves("Stunned")),
            ConditionDefinition("unconscious", "Unconscious", effects: cantMoveSaves("Unconscious")),
        ]
    }()

    var rests: [RestDefinition] { Self.restList }
    var resources: [ResourceDefinition] { Self.resourceList }

    var creationFlow: CreationFlow? { Self.flow }
    var advancement: AdvancementRule? { Self.advancementRule }

    /// The steps D&D's builder shares with any system: who the character is, what they come from, and their scores. The builder
    /// adds D&D's own steps (skills, tools, equipment, spells) between these, and still makes the character itself.
    static let flow = CreationFlow(
        steps: [
            CreationStep(id: "concept", title: "Concept", kind: .concept),
            CreationStep(id: LinkRole.race, title: "Race", kind: .choose(list: LibraryList(.race), isRequired: true)),
            CreationStep(id: LinkRole.characterClass, title: "Class", kind: .choose(list: LibraryList(.class), isRequired: true)),
            CreationStep(id: LinkRole.background, title: "Background", kind: .choose(list: LibraryList(.background), isRequired: true)),
            CreationStep(id: "abilities", title: "Abilities", kind: .numbers(NumberRule(
                entries: Ability.allCases.map { .init(key: $0.attributeKey, label: $0.rawValue, variable: $0.rawValue.lowercased()) },
                method: .assignFrom(CharacterRules.standardArray)
            ))),
            CreationStep(id: "review", title: "Review", kind: .review),
        ],
        derived: [("dnd5e.proficiencyBonus", "proficiencyBonus")],
        levelKey: "dnd5e.classLevel"
    )

    /// Levelling beyond this (hit points, features, spells) is in `LevelUp`; the proficiency bonus is the part that is only a
    /// formula.
    static let advancementRule = AdvancementRule(
        levelKey: "dnd5e.classLevel", maxLevel: 20,
        gains: [.init(key: "dnd5e.proficiencyBonus", formula: "proficiencyBonus")]
    )

    static let restList = [RestDefinition(id: "short", name: "Short Rest"), RestDefinition(id: "long", name: "Long Rest")]

    /// What a rest gives back. Inputs are `level`, the numbers on the page, and `usesPactMagic` (1 or 0). A long rest also takes away a level
    /// of exhaustion, which belongs to the conditions.
    static let resourceList = [
        ResourceDefinition(
            id: "hitPoints", name: "Hit Points", key: "dnd5e.currentHitPoints", storage: .remaining, maximum: "dnd5e.hitPoints",
            restoredBy: ["long": .full]
        ),
        ResourceDefinition(id: "temporaryHitPoints", name: "Temporary Hit Points", key: "dnd5e.temporaryHitPoints", storage: .remaining, restoredBy: ["long": .empty]),
        ResourceDefinition(id: "deathSaveSuccesses", name: "Death Save Successes", key: "dnd5e.deathSaveSuccesses", storage: .spent, maximum: "3", restoredBy: ["long": .full]),
        ResourceDefinition(id: "deathSaveFailures", name: "Death Save Failures", key: "dnd5e.deathSaveFailures", storage: .spent, maximum: "3", restoredBy: ["long": .full]),
        // A warlock's slots come back on a short rest, but other casters' don't.
        ResourceDefinition(
            id: "spellSlots", name: "Spell Slots", key: "dnd5e.spellSlotsUsed", storage: .spentList,
            restoredBy: ["long": .full, "short": .full(when: "usesPactMagic")]
        ),
        ResourceDefinition(
            id: "hitDice", name: "Hit Dice", key: "dnd5e.hitDiceSpent", storage: .spent, maximum: "level",
            restoredBy: ["long": .formula("max(1, floor(level / 2))")]
        ),
    ]

    static let hitDice = ["d6", "d8", "d10", "d12"]

    static let sizes = ["Tiny", "Small", "Medium", "Large", "Huge", "Gargantuan"]

    static let alignments = [
        "Lawful Good", "Neutral Good", "Chaotic Good",
        "Lawful Neutral", "True Neutral", "Chaotic Neutral",
        "Lawful Evil", "Neutral Evil", "Chaotic Evil",
        "Unaligned",
    ]

    static let creatureTypes = [
        "Aberration", "Beast", "Celestial", "Construct", "Dragon", "Elemental", "Fey",
        "Fiend", "Giant", "Humanoid", "Monstrosity", "Ooze", "Plant", "Undead",
    ]

    /// 0, 1/8, 1/4, 1/2, then 1 to 30.
    static let challengeRatings = ["0", "1/8", "1/4", "1/2"] + (1...30).map(String.init)

    static let rarities = ["Common", "Uncommon", "Rare", "Very Rare", "Legendary", "Artifact"]

    static let itemTypes = [
        "Weapon", "Armor", "Potion", "Ring", "Rod", "Scroll", "Staff", "Wand", "Wondrous Item",
    ]

    /// Ability scores run from 1 to 30.
    static let abilityScoreRange = 1...30

    /// The modifier for an ability score: (score - 10) / 2, rounded down. So 9 is -1 and 11 is +0.
    static func abilityModifier(for score: Int) -> Int {
        let difference = score - 10
        return difference >= 0 ? difference / 2 : -((-difference + 1) / 2)
    }

    /// The modifier as shown to the user, such as "+3", "+0" or "−1" (with a true minus sign).
    static func abilityModifierText(for score: Int) -> String {
        let modifier = abilityModifier(for: score)
        return modifier >= 0 ? "+\(modifier)" : "\u{2212}\(-modifier)"
    }

    let attributes: [AttributeDefinition] = [
        // Overrides of core attributes. Stored values stay plain text, so earlier free-text entries survive.
        .init(key: "core.creatureType", label: "Creature Type", type: .choice(creatureTypes), appliesTo: [.character], group: "Details"),
        .init(key: "core.itemType", label: "Item Type", type: .choice(itemTypes), appliesTo: [.item], group: "Details"),
        .init(key: "core.raceSize", label: "Size", type: .choice(sizes), appliesTo: [.race], group: "Details"),

        // A character's class and level. The class can be a page in the world or a library entry.
        .init(key: "core.class", label: "Class", type: .contentReference(.characterClass, role: LinkRole.characterClass), appliesTo: [.character], group: "D&D 5e"),
        .init(key: "dnd5e.subclass", label: "Subclass", type: .subclassReference(role: "subclass", classRole: LinkRole.characterClass), appliesTo: [.character], group: "D&D 5e"),
        .init(key: "core.background", label: "Background", type: .contentReference(.background, role: LinkRole.background), appliesTo: [.character], group: "D&D 5e"),
        .init(key: "dnd5e.classLevel", label: "Class Level", type: .number, appliesTo: [.character], group: "D&D 5e"),

        // Classes
        .init(key: "dnd5e.hitDie", label: "Hit Die", type: .choice(hitDice), appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.primaryAbility", label: "Primary Ability", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.savingThrows", label: "Saving Throws", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        // The class table, as comma-separated numbers for each level from 1 to 20 (slots: nine numbers for each level,
        // with a semicolon between levels). Levelling up reads them.
        .init(key: "dnd5e.asiLevels", label: "Ability Score Improvement Levels", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.cantripsKnownByLevel", label: "Cantrips Known", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.spellsKnownByLevel", label: "Spells Known", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.preparedSpellsByLevel", label: "Prepared Spells", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.spellSlotsByLevel", label: "Spell Slots", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.pactSlotsByLevel", label: "Pact Slots (number, level)", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.invocationsKnownByLevel", label: "Invocations Known", type: .text, appliesTo: [.characterClass], group: "Class Table"),
        .init(key: "dnd5e.armorProficiencies", label: "Armor Proficiencies", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.weaponProficiencies", label: "Weapon Proficiencies", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.toolProficiencies", label: "Tool Proficiencies", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.skillChoices", label: "Skill Choices", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.startingEquipment", label: "Starting Equipment", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),

        // Backgrounds. What a background gives is kept as text, as the rules word it, until the character builder reads it.
        .init(key: "dnd5e.backgroundAbilityScores", label: "Ability Scores", type: .text, appliesTo: [.background], group: "D&D 5e"),
        .init(key: "dnd5e.backgroundFeat", label: "Feat", type: .text, appliesTo: [.background], group: "D&D 5e"),
        .init(key: "dnd5e.backgroundSkills", label: "Skill Proficiencies", type: .text, appliesTo: [.background], group: "D&D 5e"),
        .init(key: "dnd5e.backgroundTools", label: "Tool Proficiency", type: .text, appliesTo: [.background], group: "D&D 5e"),
        .init(key: "dnd5e.backgroundLanguages", label: "Languages", type: .text, appliesTo: [.background], group: "D&D 5e"),
        .init(key: "dnd5e.backgroundEquipment", label: "Starting Equipment", type: .text, appliesTo: [.background], group: "D&D 5e"),

        // Equipment. Armor, weapons, tools and gear from the library become items.
        .init(key: "dnd5e.equipmentCategory", label: "Category", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.cost", label: "Cost", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.weight", label: "Weight", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.damage", label: "Damage", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.weaponProperties", label: "Properties", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.weaponMastery", label: "Mastery", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.armorFormula", label: "Armor Class", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.strengthRequirement", label: "Strength Needed", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.stealth", label: "Stealth", type: .text, appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.toolAbility", label: "Tool Ability", type: .text, appliesTo: [.item], group: "D&D 5e"),

        // What a character built from the library has.
        .init(key: "dnd5e.proficiencyBonus", label: "Proficiency Bonus", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.savingThrowProficiencies", label: "Saving Throw Proficiencies", type: .text, appliesTo: [.character], group: "Proficiencies"),
        .init(key: "dnd5e.skillProficiencies", label: "Skill Proficiencies", type: .text, appliesTo: [.character], group: "Proficiencies"),
        .init(key: "dnd5e.characterToolProficiencies", label: "Tool Proficiencies", type: .text, appliesTo: [.character], group: "Proficiencies"),
        .init(key: "dnd5e.racialTraits", label: "Racial Traits", type: .entries(showsLevel: false), appliesTo: [.character], group: "Traits"),
        .init(key: "dnd5e.classFeatures", label: "Class Features", type: .entries(showsLevel: true), appliesTo: [.character], group: "Features"),
        .init(key: "dnd5e.equipment", label: "Equipment", type: .entries(showsLevel: false), appliesTo: [.character], group: "Equipment"),
        .init(key: "dnd5e.spells", label: "Spells", type: .entries(showsLevel: false), appliesTo: [.character], group: "Spells"),
        .init(key: "dnd5e.spellSlots", label: "Spell Slots", type: .text, appliesTo: [.character], group: "Spells"),
        .init(key: "dnd5e.feats", label: "Feats", type: .entries(showsLevel: true), appliesTo: [.character], group: "Features"),

        // Spells
        .init(key: "dnd5e.spellLevel", label: "Level", type: .number, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.spellSchool", label: "School", type: .text, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.spellClasses", label: "Classes", type: .text, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.castingTime", label: "Casting Time", type: .text, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.spellRange", label: "Range", type: .text, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.components", label: "Components", type: .text, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.duration", label: "Duration", type: .text, appliesTo: [.spell], group: "D&D 5e"),
        .init(key: "dnd5e.ritual", label: "Ritual", type: .bool, appliesTo: [.spell], group: "D&D 5e"),

        // Feats
        .init(key: "dnd5e.featCategory", label: "Category", type: .text, appliesTo: [.feat], group: "D&D 5e"),
        .init(key: "dnd5e.featPrerequisite", label: "Prerequisite", type: .text, appliesTo: [.feat], group: "D&D 5e"),

        // Characters and monsters
        .init(key: "dnd5e.size", label: "Size", type: .choice(sizes), appliesTo: [.character], group: "D&D 5e"),
        .init(key: "dnd5e.alignment", label: "Alignment", type: .choice(alignments), appliesTo: [.character, .organisation], group: "D&D 5e"),
        .init(key: "dnd5e.challengeRating", label: "Challenge Rating", type: .choice(challengeRatings), appliesTo: [.character], group: "D&D 5e"),
        .init(key: "dnd5e.speed", label: "Speed", type: .text, appliesTo: [.character, .race], group: "D&D 5e"),
        .init(key: "dnd5e.armorClass", label: "Armor Class", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.hitPoints", label: "Hit Points", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.hitDice", label: "Hit Dice", type: .text, appliesTo: [.character], group: "Combat"),
        // What is played at the table. The character sheet changes these.
        .init(key: "dnd5e.currentHitPoints", label: "Current Hit Points", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.temporaryHitPoints", label: "Temporary Hit Points", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.hitDiceSpent", label: "Hit Dice Spent", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.conditions", label: "Conditions", type: .text, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.exhaustionLevel", label: "Exhaustion Level", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.skillExpertise", label: "Skill Expertise", type: .text, appliesTo: [.character], group: "Proficiencies"),
        .init(key: "dnd5e.deathSaveSuccesses", label: "Death Save Successes", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.deathSaveFailures", label: "Death Save Failures", type: .number, appliesTo: [.character], group: "Combat"),
        .init(key: "dnd5e.spellSlotsUsed", label: "Spell Slots Used", type: .text, appliesTo: [.character], group: "Spells"),
        .init(key: "dnd5e.strength", label: "Strength", type: .abilityScore, appliesTo: [.character], group: "Ability Scores"),
        .init(key: "dnd5e.dexterity", label: "Dexterity", type: .abilityScore, appliesTo: [.character], group: "Ability Scores"),
        .init(key: "dnd5e.constitution", label: "Constitution", type: .abilityScore, appliesTo: [.character], group: "Ability Scores"),
        .init(key: "dnd5e.intelligence", label: "Intelligence", type: .abilityScore, appliesTo: [.character], group: "Ability Scores"),
        .init(key: "dnd5e.wisdom", label: "Wisdom", type: .abilityScore, appliesTo: [.character], group: "Ability Scores"),
        .init(key: "dnd5e.charisma", label: "Charisma", type: .abilityScore, appliesTo: [.character], group: "Ability Scores"),

        // Races
        .init(key: "dnd5e.darkvision", label: "Darkvision", type: .text, appliesTo: [.race], group: "D&D 5e"),
        .init(key: "dnd5e.languages", label: "Languages", type: .text, appliesTo: [.race], group: "D&D 5e"),

        // Items
        .init(key: "dnd5e.rarity", label: "Rarity", type: .choice(rarities), appliesTo: [.item], group: "D&D 5e"),
        .init(key: "dnd5e.requiresAttunement", label: "Requires Attunement", type: .bool, appliesTo: [.item], group: "D&D 5e"),
    ]
}
