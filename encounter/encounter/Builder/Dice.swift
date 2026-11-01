//
//  Dice.swift
//  encounter
//

import Foundation

/// Dice and a number to add, such as "2d6 + 3". Plain values, so they can be shown, scaled and rolled.
nonisolated struct DiceExpression: Equatable, Hashable, Sendable {
    var count: Int
    var sides: Int
    var modifier = 0

    static let d20 = DiceExpression(count: 1, sides: 20)

    /// Reads "d20", "2d6", "1d4 + 1" or "1d8+3". Nil for anything else.
    init?(_ text: String) {
        guard let match = text.wholeMatch(of: /\s*(\d*)\s*[dD]\s*(\d+)\s*(?:([+\-−])\s*(\d+))?\s*/),
              let sides = Int(match.2), sides >= 2
        else { return nil }
        let count = match.1.isEmpty ? 1 : (Int(match.1) ?? 0)
        guard count >= 1 else { return nil }
        let amount = match.4.flatMap { Int($0) } ?? 0
        self.count = count
        self.sides = sides
        self.modifier = match.3 == "+" ? amount : -amount
    }

    init(count: Int, sides: Int, modifier: Int = 0) {
        self.count = count
        self.sides = sides
        self.modifier = modifier
    }

    /// The same dice with a number added to what is added already.
    func adding(_ amount: Int) -> DiceExpression {
        DiceExpression(count: count, sides: sides, modifier: modifier + amount)
    }

    /// The same dice with more (or fewer) of them.
    func withCount(_ newCount: Int) -> DiceExpression {
        DiceExpression(count: max(newCount, 1), sides: sides, modifier: modifier)
    }

    /// "2d6 + 3", "1d20 − 1", or "d20" for one die and nothing to add.
    var text: String {
        let dice = count == 1 ? "d\(sides)" : "\(count)d\(sides)"
        if modifier == 0 { return dice }
        return modifier > 0 ? "\(dice) + \(modifier)" : "\(dice) − \(-modifier)"
    }
}

/// Whether a d20 is rolled twice and the higher or lower kept.
nonisolated enum AdvantageMode: String, CaseIterable, Identifiable, Sendable {
    case normal, advantage, disadvantage
    var id: String { rawValue }
}

/// What a roll came to: every die, what was added, and the total.
nonisolated struct RollResult: Equatable, Sendable {
    var expression: DiceExpression
    /// The dice that count.
    var dice: [Int]
    /// The d20 that wasn't kept with advantage or disadvantage.
    var discarded: [Int] = []
    var mode = AdvantageMode.normal

    var total: Int { dice.reduce(0, +) + expression.modifier }

    /// A natural 20 on a single d20.
    var isNaturalTwenty: Bool { expression.sides == 20 && dice.count == 1 && dice[0] == 20 }
    var isNaturalOne: Bool { expression.sides == 20 && dice.count == 1 && dice[0] == 1 }

    /// "d20 14 + 5 = 19", or "d20 14 (8) + 5 = 19" where one die was set aside.
    var breakdown: String {
        var parts = dice.map(String.init).joined(separator: " + ")
        if !discarded.isEmpty { parts += " (" + discarded.map(String.init).joined(separator: ", ") + " set aside)" }
        if expression.modifier > 0 { parts += " + \(expression.modifier)" }
        if expression.modifier < 0 { parts += " − \(-expression.modifier)" }
        return "\(parts) = \(total)"
    }
}

nonisolated enum DiceRoller {
    /// Rolls dice. A critical hit rolls twice as many (the number added isn't doubled), and advantage or
    /// disadvantage, which only apply to a single d20, roll it twice and keep the higher or lower.
    static func roll<G: RandomNumberGenerator>(
        _ expression: DiceExpression, mode: AdvantageMode = .normal, critical: Bool = false, using generator: inout G
    ) -> RollResult {
        var expression = expression
        if critical { expression = expression.withCount(expression.count * 2) }
        if expression.sides == 20, expression.count == 1, mode != .normal {
            let first = Int.random(in: 1...20, using: &generator)
            let second = Int.random(in: 1...20, using: &generator)
            let kept = mode == .advantage ? max(first, second) : min(first, second)
            let other = first == kept ? second : first
            return RollResult(expression: expression, dice: [kept], discarded: [other], mode: mode)
        }
        let dice = (0..<expression.count).map { _ in Int.random(in: 1...expression.sides, using: &generator) }
        return RollResult(expression: expression, dice: dice)
    }

    static func roll(_ expression: DiceExpression, mode: AdvantageMode = .normal, critical: Bool = false) -> RollResult {
        var generator = SystemRandomNumberGenerator()
        return roll(expression, mode: mode, critical: critical, using: &generator)
    }
}
