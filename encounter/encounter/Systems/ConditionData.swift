//
//  ConditionData.swift
//  encounter
//

import Foundation

/// One thing a condition does to a kind of roll.
nonisolated struct ConditionEffectRule: Equatable, Sendable {
    enum Effect: Equatable, Sendable {
        case advantage
        case disadvantage
        /// The roll is failed without being made, with what says so.
        case autoFail(String)
        /// A number added to the roll, worked out by a formula that can use `level`, with what says so.
        case penalty(formula: String, reason: String)
    }

    /// The kinds of roll it applies to: "attack", "check", "initiative", "save", or one save such as "save.dexterity" (a roll of
    /// "save.dexterity" is also a "save").
    var rolls: Set<String>
    var effect: Effect
    /// A formula that must come to more than 0 for it to apply. It can use `level` and the inputs the caller gives.
    var when: String?

    init(_ rolls: Set<String>, _ effect: Effect, when: String? = nil) {
        self.rolls = rolls
        self.effect = effect
        self.when = when
    }
}

/// A condition a character can be under, and what it does to rolls, as data.
nonisolated struct ConditionDefinition: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// A condition that has levels, such as exhaustion, rather than being on or off.
    var hasLevels = false
    var effects: [ConditionEffectRule]

    init(_ id: String, _ name: String, hasLevels: Bool = false, effects: [ConditionEffectRule] = []) {
        self.id = id
        self.name = name
        self.hasLevels = hasLevels
        self.effects = effects
    }
}

nonisolated enum ConditionEngine {
    /// What the conditions a character is under do to a roll. `active` gives the level of each condition, which is 1 for one that is
    /// simply on; a condition at 0 is not on. Advantage and disadvantage cancel, as in `RollConditionEffect`.
    static func effect(
        on roll: String, active: [String: Int], definitions: [ConditionDefinition], formulas: FormulaSet = FormulaSet([:]),
        inputs: [String: Double] = [:]
    ) -> RollConditionEffect {
        var result = RollConditionEffect()
        var autoFails: [String] = []
        var reasons: [String] = []
        let family = roll.split(separator: ".").first.map(String.init) ?? roll

        for definition in definitions {
            guard let level = active[definition.id], level > 0 else { continue }
            var scope = inputs
            scope["level"] = Double(level)
            for rule in definition.effects where rule.rolls.contains(roll) || rule.rolls.contains(family) {
                if let condition = rule.when {
                    guard let value = Formula(condition)?.evaluate({ formulas.value($0, scope) }), value > 0 else { continue }
                }
                switch rule.effect {
                case .advantage: result.advantage.append(definition.name)
                case .disadvantage: result.disadvantage.append(definition.name)
                case .autoFail(let text): autoFails.append(text)
                case .penalty(let formula, let reason):
                    if let amount = Formula(formula)?.evaluate({ formulas.value($0, scope) }) {
                        result.penalty += Int(amount.rounded())
                        reasons.append(reason)
                    }
                }
            }
        }
        if !autoFails.isEmpty { result.autoFail = autoFails.joined(separator: ". ") }
        if !reasons.isEmpty { result.penaltyReason = reasons.joined(separator: ". ") }
        if !result.advantage.isEmpty && !result.disadvantage.isEmpty {
            result.mode = .normal
        } else if !result.disadvantage.isEmpty {
            result.mode = .disadvantage
        } else if !result.advantage.isEmpty {
            result.mode = .advantage
        }
        return result
    }
}
