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

    var levelKey: String
    var maxLevel: Int
    var gains: [Gain]
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
    static func levelUp(_ page: Page, rule: AdvancementRule, formulas: FormulaSet) -> [(key: String, from: Double, to: Double)]? {
        guard canLevelUp(page, rule: rule) else { return nil }
        let previous = level(of: page, rule: rule)
        page.setAttributeNumber(rule.levelKey, Double(previous + 1))
        var changes: [(key: String, from: Double, to: Double)] = []
        for gain in rule.gains {
            let current = page.attributeNumber(gain.key) ?? 0
            let inputs = ["level": Double(previous + 1), "previousLevel": Double(previous), "current": current]
            guard let value = Formula(gain.formula)?.evaluate({ formulas.value($0, inputs) }), value != current else { continue }
            page.setAttributeNumber(gain.key, value)
            changes.append((gain.key, current, value))
        }
        return changes
    }
}
