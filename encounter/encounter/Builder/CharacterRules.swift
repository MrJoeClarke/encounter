//
//  CharacterRules.swift
//  encounter
//

import Foundation

/// The six abilities, with the names the rules use.
nonisolated enum Ability: String, CaseIterable, Identifiable, Sendable {
    case strength = "Strength"
    case dexterity = "Dexterity"
    case constitution = "Constitution"
    case intelligence = "Intelligence"
    case wisdom = "Wisdom"
    case charisma = "Charisma"

    var id: String { rawValue }

    /// The key a character page stores the score under.
    var attributeKey: String { "dnd5e." + rawValue.lowercased() }

    init?(name: String) {
        guard let match = Self.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(name.trimmingCharacters(in: .whitespaces)) == .orderedSame }) else { return nil }
        self = match
    }
}

/// The arithmetic of making a level 1 character, kept apart from the screens so it can be tested.
nonisolated enum CharacterRules {
    // MARK: Ability scores

    /// The modifier for a score: 10 or 11 is 0, and it moves by 1 for every 2 points.
    static func modifier(for score: Int) -> Int {
        DnD5eSystem.formulaSet.integer("abilityModifier", ["score": Double(score)]) ?? 0
    }

    static func modifierText(for score: Int) -> String {
        let value = modifier(for: score)
        return value >= 0 ? "+\(value)" : "−\(-value)"
    }

    static let standardArray = [15, 14, 13, 12, 10, 8]

    static let pointBuyBudget = 27
    static let pointBuyRange = 8...15

    /// What a score costs to buy: 8 is free, up to 13 costs 1 point each, then 14 and 15 cost 2 each.
    static func pointBuyCost(of score: Int) -> Int? {
        switch score {
        case 8...13: score - 8
        case 14: 7
        case 15: 9
        default: nil
        }
    }

    /// The points spent on a set of scores, or nil if one is outside what point buy allows.
    static func pointBuyTotal(of scores: [Int]) -> Int? {
        var total = 0
        for score in scores {
            guard let cost = pointBuyCost(of: score) else { return nil }
            total += cost
        }
        return total
    }

    static let maximumScore = 20

    // MARK: Derived values

    static let level1ProficiencyBonus = 2

    /// A level's proficiency bonus: 2 at level 1, rising by 1 every four levels.
    static func proficiencyBonus(atLevel level: Int) -> Int {
        DnD5eSystem.formulaSet.integer("proficiencyBonus", ["level": Double(level)]) ?? 2
    }

    /// Hit points at level 1: the most the hit die can roll, plus the Constitution modifier (at least 1).
    static func hitPointsAtLevel1(hitDie: Int, constitution: Int) -> Int {
        max(1, hitDie + modifier(for: constitution))
    }

    /// Armor class without armor: 10 plus the Dexterity modifier.
    static func unarmoredArmorClass(dexterity: Int) -> Int {
        10 + modifier(for: dexterity)
    }

    /// The number a hit die such as "d10" or "D10" has, or nil if it isn't one.
    static func hitDieSides(_ text: String) -> Int? {
        let digits = text.drop { !$0.isNumber }.prefix { $0.isNumber }
        return Int(digits)
    }

    // MARK: Number words

    private static let numberWords = ["one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7, "eight": 8, "nine": 9, "ten": 10]

    /// A number written as digits or as a word up to ten.
    static func number(from word: String) -> Int? {
        let lowered = word.lowercased().trimmingCharacters(in: .whitespaces)
        return Int(lowered) ?? numberWords[lowered]
    }
}
