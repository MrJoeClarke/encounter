//
//  AbilityRecommender.swift
//  encounter
//

import Foundation

/// Suggests which ability gets which number of the standard array, from the class and from the bonuses the race or background gives.
nonisolated enum AbilityRecommender {
    /// The abilities in the order a class wants them, most important first, from the classes' quick builds.
    static func priorities(forClass name: String) -> [Ability]? {
        let order: [Ability]
        switch name.trimmingCharacters(in: .whitespaces).lowercased() {
        case "barbarian": order = [.strength, .constitution, .dexterity, .wisdom, .charisma, .intelligence]
        case "bard": order = [.charisma, .dexterity, .constitution, .wisdom, .intelligence, .strength]
        case "cleric": order = [.wisdom, .constitution, .strength, .charisma, .dexterity, .intelligence]
        case "druid": order = [.wisdom, .constitution, .dexterity, .intelligence, .charisma, .strength]
        case "fighter": order = [.strength, .constitution, .dexterity, .wisdom, .charisma, .intelligence]
        case "monk": order = [.dexterity, .wisdom, .constitution, .strength, .charisma, .intelligence]
        case "paladin": order = [.strength, .charisma, .constitution, .wisdom, .dexterity, .intelligence]
        case "ranger": order = [.dexterity, .wisdom, .constitution, .strength, .intelligence, .charisma]
        case "rogue": order = [.dexterity, .constitution, .charisma, .intelligence, .wisdom, .strength]
        case "sorcerer", "warlock": order = [.charisma, .constitution, .dexterity, .wisdom, .intelligence, .strength]
        case "wizard": order = [.intelligence, .constitution, .dexterity, .wisdom, .charisma, .strength]
        default: return nil
        }
        return order
    }

    /// How much each place in the order counts: the first ability matters most.
    private static let weights = [6, 5, 4, 3, 2, 1]

    /// The standard array laid over the abilities. Every arrangement is tried and the best kept, where best is the highest modifiers
    /// on the abilities that matter most, counted after the bonuses. That puts a +1 bonus on an odd number, where it raises the
    /// modifier, and a +2 where it is needed. Of two equal arrangements, the one nearest the class's order wins.
    static func arrangement(priorities: [Ability], bonuses: [Ability: Int]) -> [Ability: Int] {
        let values = CharacterRules.standardArray
        var best: [Int] = Array(values.prefix(priorities.count))
        var bestScore = Int.min

        func score(_ chosen: [Int]) -> Int {
            var total = 0
            for (index, ability) in priorities.enumerated() {
                let final = min(20, chosen[index] + (bonuses[ability] ?? 0))
                total += weights[index] * (4 * CharacterRules.modifier(for: final) + final)
            }
            return total
        }

        // Permutations in an order that starts with the values as given, so the first of equals is the class's own order.
        func permute(_ items: [Int], _ chosen: [Int]) {
            if items.isEmpty {
                let value = score(chosen)
                if value > bestScore { bestScore = value; best = chosen }
                return
            }
            for index in items.indices {
                var rest = items
                let picked = rest.remove(at: index)
                permute(rest, chosen + [picked])
            }
        }
        permute(values, [])
        return Dictionary(uniqueKeysWithValues: zip(priorities, best))
    }
}
