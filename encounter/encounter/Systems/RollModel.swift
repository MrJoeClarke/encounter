//
//  RollModel.swift
//  encounter
//

import Foundation

/// How a rule system's checks are rolled and read, as data. D&D rolls one d20, adds a modifier and meets a target; Daggerheart
/// rolls a pair of d12s, adds a modifier, meets a target, and also reads which die was higher.
nonisolated struct RollModel: Equatable, Sendable {
    struct Die: Equatable, Sendable {
        var name: String
        var sides: Int
    }

    /// What advantage and disadvantage do.
    enum AdvantageRule: Equatable, Sendable {
        /// Roll the (single) die twice and keep the higher or the lower.
        case rollTwice
        /// Roll one more die and add it (advantage) or take it off (disadvantage).
        case bonusDie(sides: Int)
    }

    /// What makes a roll a critical.
    enum CriticalRule: Equatable, Sendable {
        /// A single die showing its highest number; its lowest is a fumble.
        case naturalExtreme
        /// Two or more dice showing the same number.
        case matchingDice
        case none
    }

    var dice: [Die]
    var advantage: AdvantageRule
    var critical: CriticalRule
    /// Whether a critical meets any target.
    var criticalAlwaysMeetsTarget: Bool
    /// Whether a fumble misses any target.
    var fumbleAlwaysMisses: Bool

    /// One d20, with advantage by rolling twice. A natural 20 or 1 doesn't decide an ordinary check.
    static let d20 = RollModel(
        dice: [Die(name: "d20", sides: 20)], advantage: .rollTwice, critical: .naturalExtreme,
        criticalAlwaysMeetsTarget: false, fumbleAlwaysMisses: false
    )

    /// A pair of d12s, one for Hope and one for Fear, with a d6 for advantage. Matching dice always succeed.
    static let duality = RollModel(
        dice: [Die(name: "Hope", sides: 12), Die(name: "Fear", sides: 12)], advantage: .bonusDie(sides: 6), critical: .matchingDice,
        criticalAlwaysMeetsTarget: true, fumbleAlwaysMisses: false
    )
}

/// What a check came to.
nonisolated struct CheckResult: Equatable, Sendable {
    var dice: [Int]
    /// The die set aside by rolling twice.
    var discarded: [Int] = []
    /// What the advantage or disadvantage die added (negative for disadvantage); 0 if none.
    var bonusDie = 0
    var modifier: Int
    var target: Int?
    var isCritical: Bool
    var isFumble: Bool
    /// The name of the die that showed the most, when there are several and one is higher. Nil if they tie or there is one.
    var higherDie: String?
    var meetsTarget: Bool?

    var total: Int { dice.reduce(0, +) + bonusDie + modifier }
}

nonisolated enum CheckRoller {
    /// Rolls a check. Dice are drawn in order, and the extra die for advantage after them, so a seeded generator gives the same
    /// roll every time. `mode` is the net advantage: one for and one against has already cancelled.
    static func roll<G: RandomNumberGenerator>(
        _ model: RollModel, modifier: Int = 0, mode: AdvantageMode = .normal, target: Int? = nil, using generator: inout G
    ) -> CheckResult {
        var dice: [Int] = []
        var discarded: [Int] = []
        var bonus = 0

        if case .rollTwice = model.advantage, model.dice.count == 1, mode != .normal {
            let sides = model.dice[0].sides
            let first = Int.random(in: 1...sides, using: &generator)
            let second = Int.random(in: 1...sides, using: &generator)
            let kept = mode == .advantage ? max(first, second) : min(first, second)
            dice = [kept]
            discarded = [first == kept ? second : first]
        } else {
            dice = model.dice.map { Int.random(in: 1...$0.sides, using: &generator) }
            if case .bonusDie(let sides) = model.advantage, mode != .normal {
                let extra = Int.random(in: 1...sides, using: &generator)
                bonus = mode == .advantage ? extra : -extra
            }
        }

        let isCritical: Bool
        let isFumble: Bool
        switch model.critical {
        case .naturalExtreme where dice.count == 1:
            isCritical = dice[0] == model.dice[0].sides
            isFumble = dice[0] == 1
        case .matchingDice where dice.count >= 2:
            isCritical = Set(dice).count == 1
            isFumble = false
        default:
            isCritical = false
            isFumble = false
        }

        var higher: String?
        if dice.count >= 2, let top = dice.max(), dice.filter({ $0 == top }).count == 1, let index = dice.firstIndex(of: top) {
            higher = model.dice[index].name
        }

        var result = CheckResult(
            dice: dice, discarded: discarded, bonusDie: bonus, modifier: modifier, target: target,
            isCritical: isCritical, isFumble: isFumble, higherDie: higher
        )
        if let target {
            if isCritical && model.criticalAlwaysMeetsTarget {
                result.meetsTarget = true
            } else if isFumble && model.fumbleAlwaysMisses {
                result.meetsTarget = false
            } else {
                result.meetsTarget = result.total >= target
            }
        }
        return result
    }

    static func roll(_ model: RollModel, modifier: Int = 0, mode: AdvantageMode = .normal, target: Int? = nil) -> CheckResult {
        var generator = SystemRandomNumberGenerator()
        return roll(model, modifier: modifier, mode: mode, target: target, using: &generator)
    }
}
