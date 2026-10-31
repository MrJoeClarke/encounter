//
//  DnD5eSystem.swift
//  encounter
//

import Foundation

/// Attribute definitions for Dungeons & Dragons 5e. Names of options only, with no rules text.
struct DnD5eSystem: RuleSystem {
    let id = RuleSystemID.dnd5e

    var additionalPageKinds: Set<PageKind> { [.characterClass, .background, .feat, .spell] }
    var hasContentLibrary: Bool { true }

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
        .init(key: "dnd5e.classLevel", label: "Class Level", type: .number, appliesTo: [.character], group: "D&D 5e"),

        // Classes
        .init(key: "dnd5e.hitDie", label: "Hit Die", type: .choice(hitDice), appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.primaryAbility", label: "Primary Ability", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
        .init(key: "dnd5e.savingThrows", label: "Saving Throws", type: .text, appliesTo: [.characterClass], group: "D&D 5e"),
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
