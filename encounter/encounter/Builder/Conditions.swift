//
//  Conditions.swift
//  encounter
//

import Foundation

/// The conditions a character can be under. The rules text of each is in the library; what each does to the
/// character's own rolls is in `ConditionRules`.
nonisolated enum Condition: String, CaseIterable, Identifiable, Sendable {
    case blinded, charmed, deafened, exhaustion, frightened, grappled, incapacitated, invisible
    case paralyzed, petrified, poisoned, prone, restrained, stunned, unconscious

    var id: String { rawValue }

    /// "Blinded", as the library names it.
    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    init?(title: String) {
        guard let match = Self.allCases.first(where: { $0.title.caseInsensitiveCompare(title.trimmingCharacters(in: .whitespaces)) == .orderedSame }) else { return nil }
        self = match
    }
}

/// What a character is under: the conditions, and how exhausted they are (0 for not at all).
nonisolated struct ConditionState: Equatable, Sendable {
    var active: Set<Condition> = []
    var exhaustion = 0

    /// Everything that applies, with exhaustion counted when there is any.
    var all: Set<Condition> { exhaustion > 0 ? active.union([.exhaustion]) : active.subtracting([.exhaustion]) }

    var isEmpty: Bool { all.isEmpty }
}

/// What the conditions do to one kind of roll.
nonisolated struct RollConditionEffect: Equatable, Sendable {
    /// Advantage and disadvantage cancel each other, however many of each there are.
    var mode = AdvantageMode.normal
    /// "Poisoned", for each condition that gives advantage or disadvantage.
    var advantage: [String] = []
    var disadvantage: [String] = []
    /// Set when the roll is failed without being made, with what says so.
    var autoFail: String?
    /// A number added to the d20 (negative for exhaustion in the 2024 rules).
    var penalty = 0
    var penaltyReason: String?

    var isEmpty: Bool { advantage.isEmpty && disadvantage.isEmpty && autoFail == nil && penalty == 0 }

    /// Lines to show with the roll, such as "Disadvantage: Poisoned, Frightened".
    var notes: [String] {
        var lines: [String] = []
        if let autoFail { lines.append(autoFail) }
        if !advantage.isEmpty && !disadvantage.isEmpty {
            lines.append(String(localized: "Advantage (\(advantage.joined(separator: ", "))) and disadvantage (\(disadvantage.joined(separator: ", "))) cancel out."))
        } else if !disadvantage.isEmpty {
            lines.append(String(localized: "Disadvantage: \(disadvantage.joined(separator: ", "))"))
        } else if !advantage.isEmpty {
            lines.append(String(localized: "Advantage: \(advantage.joined(separator: ", "))"))
        }
        if let penaltyReason { lines.append(penaltyReason) }
        return lines
    }
}

/// What each condition does to the character's own rolls and movement, by edition. The rules text itself is in the
/// library. This is the part that turns it into advantage, disadvantage and numbers.
nonisolated enum ConditionRules {
    private static func make(
        _ state: ConditionState, edition: LibraryEdition,
        advantage: (Condition) -> Bool, disadvantage: (Condition) -> Bool
    ) -> RollConditionEffect {
        var effect = RollConditionEffect()
        for condition in Condition.allCases where state.all.contains(condition) {
            if advantage(condition) { effect.advantage.append(condition.title) }
            if disadvantage(condition) { effect.disadvantage.append(condition.title) }
        }
        if !effect.advantage.isEmpty && !effect.disadvantage.isEmpty {
            effect.mode = .normal
        } else if !effect.disadvantage.isEmpty {
            effect.mode = .disadvantage
        } else if !effect.advantage.isEmpty {
            effect.mode = .advantage
        }
        return effect
    }

    /// The effect on the character's attack rolls.
    static func attack(_ state: ConditionState, edition: LibraryEdition) -> RollConditionEffect {
        var effect = make(state, edition: edition, advantage: { $0 == .invisible }) { condition in
            switch condition {
            case .blinded, .frightened, .poisoned, .prone, .restrained: true
            case .grappled: edition == .srd52
            case .exhaustion: edition == .srd51 && state.exhaustion >= 3
            default: false
            }
        }
        applyExhaustionPenalty(&effect, state, edition: edition)
        return effect
    }

    /// The effect on an ability check (and so on a skill check). Blinded and deafened fail the checks that need the
    /// sense, which the roll can't tell, so those are noted.
    static func abilityCheck(_ state: ConditionState, edition: LibraryEdition) -> RollConditionEffect {
        var effect = make(state, edition: edition, advantage: { _ in false }) { condition in
            switch condition {
            case .frightened, .poisoned: true
            case .exhaustion: edition == .srd51 && state.exhaustion >= 1
            default: false
            }
        }
        var senses: [String] = []
        if state.all.contains(.blinded) { senses.append(String(localized: "Blinded: automatically fails a check that needs sight")) }
        if state.all.contains(.deafened) { senses.append(String(localized: "Deafened: automatically fails a check that needs hearing")) }
        if !senses.isEmpty { effect.autoFail = senses.joined(separator: ". ") }
        applyExhaustionPenalty(&effect, state, edition: edition)
        return effect
    }

    /// The effect on a saving throw with an ability.
    static func save(_ ability: Ability, _ state: ConditionState, edition: LibraryEdition) -> RollConditionEffect {
        var effect = make(state, edition: edition, advantage: { _ in false }) { condition in
            switch condition {
            case .restrained: ability == .dexterity
            case .exhaustion: edition == .srd51 && state.exhaustion >= 3
            default: false
            }
        }
        if ability == .strength || ability == .dexterity {
            let failing = [Condition.paralyzed, .petrified, .stunned, .unconscious].filter { state.all.contains($0) }
            if !failing.isEmpty {
                effect.autoFail = String(localized: "\(failing.map(\.title).joined(separator: ", ")): automatically fails Strength and Dexterity saving throws")
            }
        }
        applyExhaustionPenalty(&effect, state, edition: edition)
        return effect
    }

    /// The effect on an initiative roll, which is a Dexterity check.
    static func initiative(_ state: ConditionState, edition: LibraryEdition) -> RollConditionEffect {
        var effect = abilityCheck(state, edition: edition)
        effect.autoFail = nil
        if edition == .srd52 {
            if state.all.contains(.invisible) { effect.advantage.append(Condition.invisible.title) }
            if state.all.contains(.incapacitated) { effect.disadvantage.append(Condition.incapacitated.title) }
            effect.mode = effect.advantage.isEmpty == effect.disadvantage.isEmpty ? .normal : (effect.disadvantage.isEmpty ? .advantage : .disadvantage)
        }
        return effect
    }

    /// In the 2024 rules a d20 roll is reduced by 2 for each level of exhaustion.
    private static func applyExhaustionPenalty(_ effect: inout RollConditionEffect, _ state: ConditionState, edition: LibraryEdition) {
        guard edition == .srd52, state.exhaustion > 0 else { return }
        effect.penalty = -2 * state.exhaustion
        effect.penaltyReason = String(localized: "Exhaustion \(state.exhaustion): the roll is reduced by \(2 * state.exhaustion)")
    }

    // MARK: Movement and hit points

    /// Conditions that make the speed 0.
    static func speedIsZero(_ state: ConditionState, edition: LibraryEdition) -> [Condition] {
        var conditions: [Condition] = [.grappled, .paralyzed, .petrified, .restrained]
        // In the 2014 rules these can't move, and in the 2024 rules unconscious has a speed of 0.
        conditions += edition == .srd51 ? [.stunned, .unconscious] : [.unconscious]
        return conditions.filter { state.all.contains($0) }
    }

    /// The speed in feet with conditions applied: 0 for the conditions that stop movement, and exhaustion's reduction.
    static func speed(base: Int, _ state: ConditionState, edition: LibraryEdition) -> Int {
        if !speedIsZero(state, edition: edition).isEmpty { return 0 }
        guard state.exhaustion > 0 else { return base }
        switch edition {
        case .srd51: return state.exhaustion >= 5 ? 0 : state.exhaustion >= 2 ? base / 2 : base
        case .srd52, .daggerheart: return max(0, base - 5 * state.exhaustion)
        }
    }

    /// The hit point maximum, which the 2014 rules halve at exhaustion level 4.
    static func maximumHitPoints(_ maximum: Int, _ state: ConditionState, edition: LibraryEdition) -> Int {
        edition == .srd51 && state.exhaustion >= 4 ? maximum / 2 : maximum
    }

    /// Whether the character can take actions and reactions.
    static func cantAct(_ state: ConditionState) -> [Condition] {
        [Condition.incapacitated, .paralyzed, .petrified, .stunned, .unconscious].filter { state.all.contains($0) }
    }

    /// What others get against the character, for the sheet to remind the table of.
    static func againstYou(_ state: ConditionState, edition: LibraryEdition) -> [String] {
        var lines: [String] = []
        let advantage = [Condition.blinded, .paralyzed, .petrified, .restrained, .stunned, .unconscious].filter { state.all.contains($0) }
        if !advantage.isEmpty {
            lines.append(String(localized: "Attack rolls against you have advantage (\(advantage.map(\.title).joined(separator: ", ")))."))
        }
        if state.all.contains(.invisible) { lines.append(String(localized: "Attack rolls against you have disadvantage (Invisible).")) }
        if state.all.contains(.prone) {
            lines.append(String(localized: "Prone: attack rolls against you have advantage from within 5 feet, and disadvantage from farther away."))
        }
        if [Condition.paralyzed, .unconscious].contains(where: state.all.contains) {
            lines.append(String(localized: "An attack that hits you from within 5 feet is a critical hit."))
        }
        return lines
    }
}
