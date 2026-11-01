//
//  Levelling.swift
//  encounter
//

import Foundation

/// A class's numbers by level, read from the class table in its library entry (or a custom class made from it):
/// its hit die, the levels that give an Ability Score Improvement, and for a spellcaster its cantrips, spells and
/// spell slots.
nonisolated struct ClassProgression: Sendable, Equatable {
    /// A warlock's slots are all of one level.
    struct PactSlots: Sendable, Equatable {
        var count: Int
        var level: Int
    }

    var hitDieSides: Int
    var improvementLevels: [Int]
    var cantrips: [Int]?
    /// Spells known, for the classes that learn a fixed number (2014 rules).
    var spellsKnown: [Int]?
    /// Spells prepared (2024 rules).
    var prepared: [Int]?
    /// Spell slots of each spell level, 1 to 9, for each class level.
    var slots: [[Int]]?
    var pactSlots: [PactSlots]?
    var invocations: [Int]?

    /// Reads a class's attributes. Nil if it has no hit die or no table, such as a class made from scratch.
    init?(attributes: [String: AttributeValue]) {
        guard case .text(let die)? = attributes["dnd5e.hitDie"], let sides = CharacterRules.hitDieSides(die),
              case .text(let improvements)? = attributes["dnd5e.asiLevels"]
        else { return nil }
        hitDieSides = sides
        improvementLevels = Self.numbers(improvements)
        cantrips = Self.byLevel(attributes["dnd5e.cantripsKnownByLevel"])
        spellsKnown = Self.byLevel(attributes["dnd5e.spellsKnownByLevel"])
        prepared = Self.byLevel(attributes["dnd5e.preparedSpellsByLevel"])
        invocations = Self.byLevel(attributes["dnd5e.invocationsKnownByLevel"])
        if case .text(let text)? = attributes["dnd5e.spellSlotsByLevel"] {
            let rows = text.split(separator: ";").map { Self.numbers(String($0)) }
            slots = rows.count == 20 && rows.allSatisfy({ $0.count == 9 }) ? rows : nil
        }
        if case .text(let text)? = attributes["dnd5e.pactSlotsByLevel"] {
            let rows = text.split(separator: ";").map { Self.numbers(String($0)) }
            pactSlots = rows.count == 20 && rows.allSatisfy({ $0.count == 2 }) ? rows.map { PactSlots(count: $0[0], level: $0[1]) } : nil
        }
    }

    private static func numbers(_ text: String) -> [Int] {
        text.split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) }
    }

    private static func byLevel(_ value: AttributeValue?) -> [Int]? {
        guard case .text(let text)? = value else { return nil }
        let values = numbers(text)
        return values.count == 20 ? values : nil
    }

    private func value(_ values: [Int]?, at level: Int) -> Int {
        guard let values, (1...20).contains(level) else { return 0 }
        return values[level - 1]
    }

    func cantripsKnown(at level: Int) -> Int { value(cantrips, at: level) }
    func spellsKnown(at level: Int) -> Int { value(spellsKnown, at: level) }
    func spellsPrepared(at level: Int) -> Int { value(prepared, at: level) }

    var castsSpells: Bool { slots != nil || pactSlots != nil }

    /// The highest level of spell the character can cast at a class level, 0 if none.
    func highestSpellLevel(at level: Int) -> Int {
        if let pactSlots, (1...20).contains(level) { return pactSlots[level - 1].count > 0 ? pactSlots[level - 1].level : 0 }
        guard let slots, (1...20).contains(level) else { return 0 }
        return slots[level - 1].lastIndex { $0 > 0 }.map { $0 + 1 } ?? 0
    }

    /// The spell slots at a class level, such as "1st ×4, 2nd ×3", or a warlock's "2 × 3rd level". Empty if none.
    func slotsDescription(at level: Int) -> String {
        if let pactSlots, (1...20).contains(level) {
            let pact = pactSlots[level - 1]
            return pact.count > 0 ? "\(pact.count) × \(Self.ordinal(pact.level)) level" : ""
        }
        guard let slots, (1...20).contains(level) else { return "" }
        return slots[level - 1].enumerated().filter { $0.element > 0 }
            .map { "\(Self.ordinal($0.offset + 1)) ×\($0.element)" }.joined(separator: ", ")
    }

    static func ordinal(_ number: Int) -> String {
        let suffix = (11...13).contains(number % 100) ? "th" : ["th", "st", "nd", "rd"][number % 10 < 4 ? number % 10 : 0]
        return "\(number)\(suffix)"
    }
}

/// How a level's hit points are decided.
nonisolated enum HitPointMethod: Equatable, Sendable {
    /// Half the die, rounded up, which is what the rules offer in place of rolling.
    case average
    case rolled(Int)
}

/// What the person levelling up has chosen.
nonisolated struct LevelUpChoices: Sendable, Equatable {
    var hitPoints = HitPointMethod.average
    /// How many points each ability goes up by: 2 in one, or 1 in two.
    var abilityIncreases: [Ability: Int] = [:]
    /// A feat taken in place of the ability increase: the key of its library entry.
    var feat: String?
    var subclass: String?
    var cantrips: Set<String> = []
    var spells: Set<String> = []
}

/// What the next level asks of whoever is levelling up, and what it gives.
nonisolated struct LevelUpNeeds: Sendable, Equatable {
    var newLevel: Int
    var hitDieSides: Int
    var choosesSubclass: Bool
    var hasImprovement: Bool
    var cantripsToLearn: Int
    var spellsToLearn: Int
    var highestSpellLevel: Int
}

nonisolated enum LevelRules {
    static let maximumLevel = 20

    /// A level's hit points when not rolled: half the die, rounded up.
    static func averageRoll(hitDieSides: Int) -> Int { hitDieSides / 2 + 1 }

    /// The hit points a new level gives: the roll plus the Constitution modifier, and always at least 1.
    static func hitPointsGained(roll: Int, constitution: Int) -> Int {
        max(1, roll + CharacterRules.modifier(for: constitution))
    }

    /// When a Constitution increase raises the modifier, the hit points of every earlier level rise with it.
    static func retroactiveHitPoints(levelsBefore: Int, oldConstitution: Int, newConstitution: Int) -> Int {
        levelsBefore * (CharacterRules.modifier(for: newConstitution) - CharacterRules.modifier(for: oldConstitution))
    }

    /// Whether the increases are allowed: 2 in one ability or 1 in two, and no score above 20.
    static func isValidIncrease(_ increases: [Ability: Int], to scores: [Ability: Int]) -> Bool {
        let chosen = increases.filter { $0.value != 0 }
        guard chosen.values.reduce(0, +) == 2, chosen.values.allSatisfy({ $0 > 0 }), chosen.count <= 2 else { return false }
        return chosen.allSatisfy { (scores[$0.key] ?? 10) + $0.value <= CharacterRules.maximumScore }
    }

    /// What reaching the next level asks for.
    /// - Parameters:
    ///   - subclassLevel: the level the class picks its subclass at, if it has one in the library.
    ///   - hasSubclass: whether the character already has a subclass.
    ///   - spellbookSpellsPerLevel: spells a wizard writes in the spellbook with each level.
    static func needs(
        for progression: ClassProgression,
        fromLevel level: Int,
        subclassLevel: Int?,
        hasSubclass: Bool,
        spellbookSpellsPerLevel: Int = 0
    ) -> LevelUpNeeds? {
        guard (1..<maximumLevel).contains(level) else { return nil }
        let next = level + 1
        let learned = progression.spellsKnown(at: next) - progression.spellsKnown(at: level)
            + (progression.spellsPrepared(at: next) - progression.spellsPrepared(at: level))
        return LevelUpNeeds(
            newLevel: next,
            hitDieSides: progression.hitDieSides,
            choosesSubclass: !hasSubclass && subclassLevel.map { $0 <= next } == true,
            hasImprovement: progression.improvementLevels.contains(next),
            cantripsToLearn: max(0, progression.cantripsKnown(at: next) - progression.cantripsKnown(at: level)),
            spellsToLearn: spellbookSpellsPerLevel > 0 && progression.castsSpells ? spellbookSpellsPerLevel : max(0, learned),
            highestSpellLevel: progression.highestSpellLevel(at: next)
        )
    }
}
