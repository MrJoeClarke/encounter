//
//  Advancement.swift
//  encounter
//

import Foundation

/// How a system's characters gain levels, as data: where the level is kept, how high it goes, and the numbers that change when
/// a level is reached.
nonisolated struct AdvancementRule: Equatable, Sendable {
    struct Gain: Equatable, Sendable {
        /// The attribute that changes.
        var key: String
        /// What it becomes, as a formula. It can use `level` (the new level), `previousLevel`, and `current` (what the attribute
        /// is now, or 0), as well as the system's own named formulas.
        var formula: String
    }

    /// One of the things a character can pick when they reach a level, such as another hit point slot.
    struct Choice: Equatable, Identifiable, Sendable {
        var id: String
        var title: String
        /// How many of a level's points it uses.
        var cost: Int
        /// What picking it does. A formula can use `current` and `level` as in `Gain`.
        var gains: [Gain]
    }

    var levelKey: String
    var maxLevel: Int
    /// What every level gives.
    var gains: [Gain]
    /// What a character spends `choicePoints` on each level. None if levels have no choices.
    var choices: [Choice] = []
    var choicePoints = 0

    /// Whether the picks, by id (the same one can be picked twice), use exactly the points a level gives.
    func isValid(picks: [String]) -> Bool {
        guard choicePoints > 0 else { return picks.isEmpty }
        let costs = picks.compactMap { id in choices.first { $0.id == id }?.cost }
        return costs.count == picks.count && costs.reduce(0, +) == choicePoints
    }
}

@MainActor
enum Advancement {
    static func level(of page: Page, rule: AdvancementRule) -> Int {
        max(1, min(rule.maxLevel, Int(page.attributeNumber(rule.levelKey) ?? 1)))
    }

    static func canLevelUp(_ page: Page, rule: AdvancementRule) -> Bool {
        page.kind == .character && level(of: page, rule: rule) < rule.maxLevel
    }

    /// Raises the character one level and applies the gains. Returns what each gain changed (key, old, new) for the ones that
    /// did change, or nil if the character can't level up.
    @discardableResult
    static func levelUp(_ page: Page, rule: AdvancementRule, formulas: FormulaSet, picks: [String] = []) -> [(key: String, from: Double, to: Double)]? {
        guard canLevelUp(page, rule: rule), rule.isValid(picks: picks) else { return nil }
        let previous = level(of: page, rule: rule)
        page.setAttributeNumber(rule.levelKey, Double(previous + 1))
        var changes: [(key: String, from: Double, to: Double)] = []
        let chosen = picks.compactMap { id in rule.choices.first { $0.id == id } }.flatMap(\.gains)
        for gain in rule.gains + chosen {
            let current = page.attributeNumber(gain.key) ?? 0
            let inputs = ["level": Double(previous + 1), "previousLevel": Double(previous), "current": current]
            guard let value = Formula(gain.formula)?.evaluate({ formulas.value($0, inputs) }), value != current else { continue }
            page.setAttributeNumber(gain.key, value)
            changes.append((gain.key, current, value))
        }
        return changes
    }
}
