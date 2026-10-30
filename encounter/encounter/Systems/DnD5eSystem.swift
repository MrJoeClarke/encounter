//
//  DnD5eSystem.swift
//  encounter
//

import Foundation

/// Attribute definitions for Dungeons & Dragons 5e. Names of options only, with no rules text.
struct DnD5eSystem: RuleSystem {
    let id = RuleSystemID.dnd5e

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
