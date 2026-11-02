//
//  FormulaAndRollTests.swift
//  encounterTests
//

import Foundation
import Testing
@testable import encounter

struct FormulaTests {
    @Test func evaluatesArithmeticWithPrecedence() {
        #expect(Formula("2 + 3 * 4")?.evaluate([:]) == 14)
        #expect(Formula("(2 + 3) * 4")?.evaluate([:]) == 20)
        #expect(Formula("-3 + 10 / 4")?.evaluate([:]) == -0.5)
        #expect(Formula("10 − 4")?.evaluate([:]) == 6)
    }

    @Test func usesNamesAndFunctions() {
        let formula = Formula("max(floor(level / 2), 1) + bonus")
        #expect(formula?.evaluate(["level": 5, "bonus": 3]) == 5)
        #expect(formula?.variables == ["level", "bonus"])
        #expect(Formula("round(2.5)")?.evaluate([:]) == 3)
        #expect(Formula("ceil(1.1)")?.evaluate([:]) == 2)
        #expect(Formula("abs(-2)")?.evaluate([:]) == 2)
        #expect(Formula("min(4, 2, 9)")?.evaluate([:]) == 2)
        #expect(Formula("max(4, 2, 9) - min(4, 2)")?.evaluate([:]) == 7)
    }

    @Test func rejectsWhatIsNotAFormula() {
        for text in ["", "2 +", "(1 + 2", "1 2", "foo(", "3 $ 4", "1..2"] { #expect(Formula(text) == nil, "\(text)") }
    }

    @Test func givesNilForUnknownNamesAndDivisionByZero() {
        #expect(Formula("a + 1")?.evaluate([:]) == nil)
        #expect(Formula("1 / (a - a)")?.evaluate(["a": 2]) == nil)
        #expect(Formula("nothing(1)")?.evaluate([:]) == nil)
    }

    @Test func formulasUseEachOtherAndInputsWin() {
        let set = FormulaSet(["double": "x * 2", "plusOne": "double + 1", "loop": "loop + 1", "broken": "1 +"])
        #expect(set.value("plusOne", ["x": 4]) == 9)
        #expect(set.value("plusOne", ["double": 10]) == 11)
        #expect(set.value("loop") == nil)
        #expect(set.value("broken") == nil)
        #expect(set.value("missing") == nil)
    }
}

/// The D&D numbers now come from formulas; they must come out as they did before.
struct DnDFormulaParityTests {
    @Test func abilityModifier() {
        for score in 1...30 {
            #expect(CharacterRules.modifier(for: score) == Int((Double(score - 10) / 2).rounded(.down)), "score \(score)")
        }
        #expect(CharacterRules.modifier(for: 8) == -1)
        #expect(CharacterRules.modifier(for: 9) == -1)
        #expect(CharacterRules.modifier(for: 15) == 2)
    }

    @Test func proficiencyBonus() {
        for level in 0...20 { #expect(CharacterRules.proficiencyBonus(atLevel: level) == 2 + (max(level, 1) - 1) / 4, "level \(level)") }
        #expect(CharacterRules.proficiencyBonus(atLevel: 17) == 6)
    }

    @Test func spellNumbers() {
        for bonus in 2...6 {
            for score in 3...30 {
                #expect(SheetRules.spellSaveDC(proficiencyBonus: bonus, abilityScore: score) == 8 + bonus + (score - 10 - (score % 2 == 0 ? 0 : 1)) / 2)
                #expect(SheetRules.spellAttackBonus(proficiencyBonus: bonus, abilityScore: score) == bonus + CharacterRules.modifier(for: score))
            }
        }
    }

    @Test func skillBonuses() {
        let set = DnD5eSystem.formulaSet
        func bonus(_ multiplier: Double) -> Int? {
            set.integer("skillBonus", ["score": 14, "proficiencyBonus": 5, "proficiencyMultiplier": multiplier])
        }
        #expect(bonus(0) == 2)
        #expect(bonus(0.5) == 4)
        #expect(bonus(1) == 7)
        #expect(bonus(2) == 12)
    }

    @Test func systemsExposeTheirModels() {
        #expect(DnD5eSystem().rollModel == .d20)
        #expect(NoRuleSystem().rollModel == nil)
        #expect(NoRuleSystem().formulas.names.isEmpty)
    }
}

struct CheckRollerTests {
    /// The same random numbers must give the same d20 as the existing roller, so D&D rolls don't change.
    @Test func d20MatchesTheExistingRoller() {
        for mode in AdvantageMode.allCases {
            for seed in UInt64(1)...30 {
                var a = SeededRandom(seed: seed), b = SeededRandom(seed: seed)
                let old = DiceRoller.roll(.d20.adding(5), mode: mode, using: &a)
                let new = CheckRoller.roll(.d20, modifier: 5, mode: mode, using: &b)
                #expect(new.dice == old.dice && new.discarded == old.discarded && new.total == old.total, "\(mode) \(seed)")
                #expect(new.isCritical == old.isNaturalTwenty && new.isFumble == old.isNaturalOne)
            }
        }
    }

    @Test func d20TargetIsMetByTotalAlone() {
        for seed in UInt64(1)...40 {
            var generator = SeededRandom(seed: seed)
            let result = CheckRoller.roll(.d20, modifier: 3, target: 15, using: &generator)
            #expect(result.meetsTarget == (result.total >= 15))
        }
    }

    @Test func dualityRollsTwoD12sAndNamesTheHigher() {
        var sawHope = false, sawFear = false, sawCritical = false
        for seed in UInt64(1)...200 {
            var generator = SeededRandom(seed: seed)
            let result = CheckRoller.roll(.duality, modifier: 2, target: 12, using: &generator)
            #expect(result.dice.count == 2 && result.dice.allSatisfy { (1...12).contains($0) })
            #expect(result.bonusDie == 0 && result.total == result.dice[0] + result.dice[1] + 2)
            switch result.dice[0] - result.dice[1] {
            case 1...: #expect(result.higherDie == "Hope"); sawHope = true
            case ..<0: #expect(result.higherDie == "Fear"); sawFear = true
            default:
                #expect(result.higherDie == nil && result.isCritical && result.meetsTarget == true)
                sawCritical = true
            }
            if !result.isCritical { #expect(result.meetsTarget == (result.total >= 12)) }
        }
        #expect(sawHope && sawFear && sawCritical)
    }

    @Test func dualityAdvantageAddsAndDisadvantageSubtractsAD6() {
        for seed in UInt64(1)...50 {
            var a = SeededRandom(seed: seed), b = SeededRandom(seed: seed)
            let advantage = CheckRoller.roll(.duality, mode: .advantage, using: &a)
            let disadvantage = CheckRoller.roll(.duality, mode: .disadvantage, using: &b)
            #expect((1...6).contains(advantage.bonusDie) && (-6)...(-1) ~= disadvantage.bonusDie)
            #expect(advantage.bonusDie == -disadvantage.bonusDie && advantage.dice == disadvantage.dice)
            #expect(advantage.total == advantage.dice.reduce(0, +) + advantage.bonusDie)
        }
    }
}

struct ResourceRulesTests {
    private let formulas = FormulaSet([:])

    private func after(_ rest: String, _ resource: ResourceDefinition, _ current: Double?, _ inputs: [String: Double] = [:]) -> Double? {
        ResourceRules.valueAfter(rest: rest, resource: resource, current: current, formulas: formulas, inputs: inputs)
    }

    @Test func remainingResourcesRiseToTheMaximumAndNoFurther() {
        let hope = ResourceDefinition(
            id: "hope", name: "Hope", key: "x.hope", storage: .remaining, maximum: "6",
            restoredBy: ["short": .formula("1"), "long": .full, "never": .empty]
        )
        #expect(after("short", hope, 2) == 3)
        #expect(after("short", hope, 6) == 6)
        #expect(after("long", hope, 1) == 6)
        #expect(after("never", hope, 4) == 0)
        #expect(after("other", hope, 4) == nil)
        // No value yet counts as the maximum.
        #expect(after("short", hope, nil) == 6)
    }

    @Test func spentResourcesFallToNone() {
        let dice = ResourceDefinition(id: "dice", name: "Dice", key: "x.dice", storage: .spent, maximum: "level", restoredBy: ["long": .formula("max(1, floor(level / 2))"), "short": .full])
        #expect(after("long", dice, 5, ["level": 8]) == 1)
        #expect(after("long", dice, 2, ["level": 8]) == 0)
        #expect(after("long", dice, 3, ["level": 3]) == 2)
        #expect(after("short", dice, 5, ["level": 8]) == 0)
    }

    @Test func aConditionStopsARestRestoringAnything() {
        let slots = ResourceDefinition(id: "slots", name: "Slots", key: "x.slots", storage: .spentList, restoredBy: ["short": .full(when: "pact")])
        #expect(ResourceRules.textAfter(rest: "short", resource: slots, formulas: formulas, inputs: ["pact": 1]) == "")
        #expect(ResourceRules.textAfter(rest: "short", resource: slots, formulas: formulas, inputs: ["pact": 0]) == nil)
        #expect(ResourceRules.textAfter(rest: "long", resource: slots, formulas: formulas, inputs: ["pact": 1]) == nil)
    }

    @Test func maximumsCanUseTheSystemsFormulas() {
        let set = FormulaSet(["tier": "1 + floor((level - 1) / 4)"])
        let stress = ResourceDefinition(id: "stress", name: "Stress", key: "x.stress", storage: .spent, restoredBy: ["short": .formula("tier + 1")])
        #expect(ResourceRules.valueAfter(rest: "short", resource: stress, current: 5, formulas: set, inputs: ["level": 6]) == 2)
    }

    @Test func dndResourcesAreAllOnTheKeysTheSheetAlreadyUses() {
        let keys = Set(DnD5eSystem.resourceList.map(\.key))
        #expect(keys == ["dnd5e.currentHitPoints", "dnd5e.temporaryHitPoints", "dnd5e.deathSaveSuccesses", "dnd5e.deathSaveFailures", "dnd5e.spellSlotsUsed", "dnd5e.hitDiceSpent"])
        #expect(DnD5eSystem().rests.map(\.id) == ["short", "long"])
        for resource in DnD5eSystem.resourceList {
            for restId in resource.restoredBy.keys { #expect(DnD5eSystem.restList.contains { $0.id == restId }) }
        }
        #expect(NoRuleSystem().resources.isEmpty && NoRuleSystem().rests.isEmpty)
    }
}
