//
//  SheetAndConditionDataTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// A made-up system with a sheet, resources and conditions that are all data.
private struct MadeUpSystem: RuleSystem {
    let id = RuleSystemID.none
    let attributes: [AttributeDefinition] = []
    var formulas: FormulaSet {
        FormulaSet(["tier": "1 + ceil((level - 1) / 3)", "evasion": "made.baseEvasion + tier"])
    }
    var advancement: AdvancementRule? { AdvancementRule(levelKey: "made.level", maxLevel: 10, gains: []) }
    var resources: [ResourceDefinition] {
        [
            ResourceDefinition(id: "hp", name: "Hit Points", key: "made.hp", storage: .spent, maximum: "made.hpSlots", restoredBy: ["long": .full]),
            ResourceDefinition(id: "hope", name: "Hope", key: "made.hope", storage: .remaining, maximum: "6", restoredBy: ["short": .formula("1")]),
        ]
    }
    var conditions: [ConditionDefinition] {
        [
            ConditionDefinition("vulnerable", "Vulnerable", effects: [.init(["check", "save"], .disadvantage)]),
            ConditionDefinition("hidden", "Hidden", effects: [.init(["attack"], .advantage)]),
            ConditionDefinition("tired", "Tired", hasLevels: true, effects: [.init(["check"], .penalty(formula: "-1 * level", reason: "Tired"))]),
        ]
    }
    var sheetLayout: SheetLayout? {
        SheetLayout(sections: [
            SheetSection(id: "a", title: "A", rows: [
                SheetRow(id: "hp", label: "Hit Points", kind: .resource("hp")),
                SheetRow(id: "hope", label: "Hope", kind: .resource("hope")),
                SheetRow(id: "evasion", label: "Evasion", kind: .stat(formula: "evasion", inputs: [:])),
                SheetRow(id: "agility", label: "Agility", kind: .check(formula: "x", inputs: ["x": "made.agility"], roll: "check")),
                SheetRow(id: "missing", label: "Missing", kind: .stat(formula: "made.nothing + 1", inputs: [:])),
                SheetRow(id: "motto", label: "Motto", kind: .text(key: "made.motto")),
            ]),
        ])
    }
}

@MainActor
struct SheetAndConditionDataTests {
    private func makePage(system: RuleSystemID = .none) throws -> (Page, World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: system)
        context.insert(world)
        return (world.addPage(kind: .character, in: context), world, context)
    }

    @Test func aSheetIsWorkedOutFromItsLayout() throws {
        let (page, _, _) = try makePage()
        page.setAttributeNumber("made.level", 5)
        page.setAttributeNumber("made.baseEvasion", 9)
        page.setAttributeNumber("made.agility", 2)
        page.setAttributeNumber("made.hpSlots", 6)
        page.setAttributeNumber("made.hp", 2)
        page.setAttributeText("made.motto", "Onward")
        let system = MadeUpSystem()

        let rows = SheetEngine.build(system.sheetLayout!, for: page, system: system).flatMap(\.rows)
        let values = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0.value) })
        #expect(values["hp"] == .resource(current: 4, maximum: 6))
        #expect(values["hope"] == .resource(current: 6, maximum: 6))
        #expect(values["evasion"] == .number(12))
        #expect(values["agility"] == .check(modifier: 2, roll: "check"))
        #expect(values["missing"] == .unknown)
        #expect(values["motto"] == .text("Onward"))
    }

    @Test func spendingAndGainingStayBetweenNoneAndTheMost() throws {
        let (page, _, _) = try makePage()
        let system = MadeUpSystem()
        page.setAttributeNumber("made.hpSlots", 6)
        page.setAttributeNumber("made.hope", 2)

        // Hope is kept as what remains, hit points as what is spent.
        #expect(SheetEngine.adjust("hope", by: -1, on: page, system: system) == 1)
        #expect(page.attributeNumber("made.hope") == 1)
        #expect(SheetEngine.adjust("hope", by: -5, on: page, system: system) == 0)
        #expect(SheetEngine.adjust("hope", by: 10, on: page, system: system) == 6)
        #expect(SheetEngine.adjust("hp", by: -2, on: page, system: system) == 4)
        #expect(page.attributeNumber("made.hp") == 2)
        #expect(SheetEngine.adjust("hp", by: 99, on: page, system: system) == 6)
        #expect(page.attributeNumber("made.hp") == 0)
        #expect(SheetEngine.adjust("nothing", by: 1, on: page, system: system) == nil)
    }

    @Test func conditionsChangeRollsAsTheirDataSays() {
        let system = MadeUpSystem()
        func effect(_ roll: String, _ active: [String: Int]) -> RollConditionEffect {
            ConditionEngine.effect(on: roll, active: active, definitions: system.conditions)
        }
        #expect(effect("check", ["vulnerable": 1]).mode == .disadvantage)
        #expect(effect("save.dexterity", ["vulnerable": 1]).disadvantage == ["Vulnerable"])
        #expect(effect("attack", ["vulnerable": 1]).isEmpty)
        #expect(effect("attack", ["hidden": 1, "vulnerable": 1]).mode == .advantage)
        #expect(effect("check", ["tired": 3]).penalty == -3 && effect("check", ["tired": 0]).isEmpty)
        // Advantage and disadvantage cancel.
        let both = ConditionEngine.effect(on: "check", active: ["vulnerable": 1, "extra": 1], definitions: system.conditions + [
            ConditionDefinition("extra", "Extra", effects: [.init(["check"], .advantage)]),
        ])
        #expect(both.mode == .normal && both.advantage == ["Extra"] && both.disadvantage == ["Vulnerable"])
    }

    @Test func dndsSheetNumbersFromDataMatchTheSheet() throws {
        let (page, _, _) = try makePage(system: .dnd5e)
        page.setAttributeNumber("dnd5e.classLevel", 9)
        for (ability, score) in zip(Ability.allCases, [8, 14, 15, 10, 13, 20]) { page.setAttributeNumber(ability.attributeKey, Double(score)) }
        page.setAttributeNumber("dnd5e.hitPoints", 60)
        page.setAttributeNumber("dnd5e.currentHitPoints", 41)
        page.setAttributeNumber("dnd5e.temporaryHitPoints", 5)
        let sheet = try #require(CharacterSheet(page: page))
        let system = DnD5eSystem()

        let values = Dictionary(uniqueKeysWithValues: SheetEngine.build(try #require(system.sheetLayout), for: page, system: system).flatMap(\.rows).map { ($0.id, $0.value) })
        for ability in Ability.allCases { #expect(values[ability.attributeKey] == .number(sheet.modifier(ability)), "\(ability)") }
        #expect(values["proficiencyBonus"] == .number(sheet.proficiencyBonus))
        #expect(values["hitPoints"] == .resource(current: sheet.currentHitPoints, maximum: sheet.maximumHitPoints))
        #expect(values["temporaryHitPoints"] == .resource(current: sheet.temporaryHitPoints, maximum: nil))
    }

    /// The data for D&D's conditions must say what `ConditionRules` says, for every kind of roll in both editions.
    @Test func dndConditionDataMatchesTheRulesInCode() {
        var random = SeededRandom(seed: 7)
        let definitions = DnD5eSystem().conditions
        #expect(definitions.map(\.id) == Condition.allCases.map(\.rawValue))
        for edition in LibraryEdition.allCases {
            for sample in 0..<250 {
                var state = ConditionState()
                for condition in Condition.allCases where condition != .exhaustion && Bool.random(using: &random) && sample % 3 != 0 { state.active.insert(condition) }
                state.exhaustion = Int.random(in: 0...6, using: &random)
                var levels = Dictionary(uniqueKeysWithValues: state.active.map { ($0.rawValue, 1) })
                if state.exhaustion > 0 { levels["exhaustion"] = state.exhaustion }
                let inputs: [String: Double] = ["edition2024": edition == .srd52 ? 1 : 0]

                func same(_ roll: String, _ code: RollConditionEffect, _ note: String) {
                    let data = ConditionEngine.effect(on: roll, active: levels, definitions: definitions, inputs: inputs)
                    #expect(data.mode == code.mode, "\(note) mode")
                    #expect(Set(data.advantage) == Set(code.advantage) && data.advantage.count == code.advantage.count, "\(note) advantage")
                    #expect(Set(data.disadvantage) == Set(code.disadvantage) && data.disadvantage.count == code.disadvantage.count, "\(note) disadvantage")
                    #expect(data.penalty == code.penalty, "\(note) penalty")
                    #expect((data.autoFail == nil) == (code.autoFail == nil), "\(note) auto-fail")
                }
                let note = "\(edition) \(state)"
                same("attack", ConditionRules.attack(state, edition: edition), note + " attack")
                same("check", ConditionRules.abilityCheck(state, edition: edition), note + " check")
                same("initiative", ConditionRules.initiative(state, edition: edition), note + " initiative")
                for ability in Ability.allCases {
                    same("save.\(ability.rawValue.lowercased())", ConditionRules.save(ability, state, edition: edition), note + " \(ability) save")
                }
            }
        }
    }
}
