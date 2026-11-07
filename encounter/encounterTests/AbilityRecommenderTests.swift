//
//  AbilityRecommenderTests.swift
//  encounterTests
//

import Testing
@testable import encounter

struct AbilityRecommenderTests {
    @Test func everyClassOfTheRulesHasAnOrderOfAllSixAbilities() {
        for name in ["Barbarian", "Bard", "Cleric", "Druid", "Fighter", "Monk", "Paladin", "Ranger", "Rogue", "Sorcerer", "Warlock", "Wizard"] {
            let order = AbilityRecommender.priorities(forClass: name)
            #expect(order != nil && Set(order ?? []).count == 6, "\(name)")
        }
        #expect(AbilityRecommender.priorities(forClass: "Artificer") == nil)
    }

    @Test func aFighterWithNoBonusesGetsTheArrayInTheClassOrder() throws {
        let order = try #require(AbilityRecommender.priorities(forClass: "Fighter"))
        let scores = AbilityRecommender.arrangement(priorities: order, bonuses: [:])
        #expect(scores[.strength] == 15)
        #expect(scores[.constitution] == 14)
        #expect(scores[.dexterity] == 13)
        #expect(scores[.intelligence] == 8)
    }

    @Test func theArrayIsUsedOnceEach() throws {
        let order = try #require(AbilityRecommender.priorities(forClass: "Wizard"))
        let scores = AbilityRecommender.arrangement(priorities: order, bonuses: [.dexterity: 2, .intelligence: 1])
        #expect(scores.values.sorted(by: >) == CharacterRules.standardArray)
    }

    @Test func aPlusOneBonusGoesWhereItRaisesTheModifier() throws {
        // A cleric wants Wisdom first, and a +1 to Wisdom (15 → 16) raises the modifier, so Wisdom keeps the 15.
        let order = try #require(AbilityRecommender.priorities(forClass: "Cleric"))
        let scores = AbilityRecommender.arrangement(priorities: order, bonuses: [.wisdom: 1])
        #expect(scores[.wisdom] == 15)
        // A +1 to the second ability (14 → 15) raises nothing, so it is better given the 13 and a bonus to the 15 or 13.
        let second = AbilityRecommender.arrangement(priorities: order, bonuses: [.constitution: 1])
        let constitution = try #require(second[.constitution])
        #expect(constitution % 2 == 1)
    }
}
