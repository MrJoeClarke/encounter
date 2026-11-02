//
//  DataSystemTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// A whole made-up system written as a JSON file, run through each of the engines.
@MainActor
struct DataSystemTests {
    static let json = """
    {
      "formatVersion": 1, "id": "made.hearts", "name": "Hearts & Hammers",
      "modules": ["characterCreation", "advancement", "sheet", "conditions"],
      "attributes": [
        {"key": "made.level", "label": "Level", "type": "number", "appliesTo": ["character"]},
        {"key": "made.calling", "label": "Calling", "type": "choice", "options": ["Smith", "Singer"], "appliesTo": ["character"], "group": "Character"}
      ],
      "rollModel": {
        "dice": [{"name": "Hope", "sides": 12}, {"name": "Fear", "sides": 12}],
        "advantage": {"type": "bonusDie", "sides": 6}, "critical": "matchingDice", "criticalAlwaysMeetsTarget": true
      },
      "formulas": {"tier": "1 + ceil((level - 1) / 3)", "evasion": "made.baseEvasion + tier"},
      "rests": [{"id": "short", "name": "Short Rest"}, {"id": "long", "name": "Long Rest"}],
      "resources": [
        {"id": "hp", "name": "Hit Points", "key": "made.hp", "storage": "spent", "maximum": "made.hpSlots",
         "restoredBy": {"long": "full", "short": {"formula": "2 + tier"}}},
        {"id": "hope", "name": "Hope", "key": "made.hope", "maximum": "6", "restoredBy": {"short": {"formula": "1"}, "long": {"amount": "full"}}}
      ],
      "creation": {
        "levelKey": "made.level",
        "steps": [
          {"id": "concept", "type": "concept"},
          {"id": "class", "title": "Class", "type": "choose", "list": {"kind": "class"}},
          {"id": "traits", "title": "Traits", "type": "numbers", "assignFrom": [2, 1, 0],
           "entries": [{"key": "made.might", "variable": "might"}, {"key": "made.wit", "variable": "wit"}, {"key": "made.heart", "variable": "heart"}]},
          {"id": "review", "type": "review"}
        ],
        "derived": {"made.hpSlots": "class_startingHp", "made.baseEvasion": "class_evasion"}
      },
      "advancement": {"levelKey": "made.level", "maxLevel": 10, "gains": [{"key": "made.hpSlots", "formula": "current + 1"}]},
      "conditions": [
        {"id": "weary", "name": "Weary", "effects": [
          {"rolls": ["check", "save"], "effect": "disadvantage"},
          {"rolls": ["attack"], "effect": "penalty", "formula": "-2", "reason": "Weary"}]},
        {"id": "dazed", "name": "Dazed", "hasLevels": true, "effects": [
          {"rolls": ["save.heart"], "effect": "autoFail", "note": "Dazed: fails Heart saves", "when": "level - 1"}]}
      ],
      "sheet": {"sections": [
        {"id": "vitals", "title": "Vitals", "rows": [
          {"id": "hp", "type": "resource", "resource": "hp"},
          {"id": "hope", "type": "resource", "resource": "hope"},
          {"id": "evasion", "type": "stat", "formula": "evasion"},
          {"id": "might", "type": "check", "formula": "x", "inputs": {"x": "made.might"}, "roll": "check"}]}
      ]}
    }
    """

    private func makeSystem() throws -> DataRuleSystem { try #require(DataRuleSystem(data: Data(Self.json.utf8))) }

    @Test func aSystemFileIsReadIntoEveryPartOfASystem() throws {
        let system = try makeSystem()
        #expect(system.key == "made.hearts" && system.definition.name == "Hearts & Hammers" && system.definition.problems.isEmpty)
        #expect(system.modules == [.characterCreation, .advancement, .sheet, .conditions])
        #expect(system.rollModel?.dice.map(\.name) == ["Hope", "Fear"] && system.rollModel?.critical == .matchingDice && system.rollModel?.advantage == .bonusDie(sides: 6))
        #expect(system.attributes.map(\.key) == ["made.level", "made.calling"])
        #expect(system.rests.map(\.id) == ["short", "long"] && system.resources.map(\.id) == ["hp", "hope"])
        #expect(system.resources[0].restoredBy["long"] == .full && system.resources[1].restoredBy["long"] == .full)
        #expect(system.creationFlow?.steps.map(\.id) == ["concept", "class", "traits", "review"])
        #expect(system.advancement?.maxLevel == 10 && system.conditions.map(\.id) == ["weary", "dazed"])
        #expect(system.sheetLayout?.sections.first?.rows.count == 4)
        #expect(system.formulas.integer("tier", ["level": 5]) == 3)
    }

    @Test func aCharacterIsMadeLevelledRestedAndShownFromTheFile() throws {
        let system = try makeSystem()
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .none)
        context.insert(world)
        let warrior = world.addPage(kind: .characterClass, in: context)
        warrior.title = "Warrior"
        warrior.setAttributeNumber("made.startingHp", 5)
        warrior.setAttributeNumber("made.evasion", 9)
        var draft = CreationDraft(name: "Ash")
        draft.choices["class"] = .page(warrior.id)
        draft.numbers = ["made.might": 2, "made.wit": 1, "made.heart": 0]

        let flow = try #require(system.creationFlow)
        let page = try #require(CreationEngine.create(draft, flow: flow, formulas: system.formulas, in: world, context: context))
        #expect(page.attributeNumber("made.hpSlots") == 5 && page.attributeNumber("made.level") == 1 && page.attributeNumber("made.might") == 2)

        // The sheet.
        func values() -> [String: SheetValue] {
            Dictionary(uniqueKeysWithValues: SheetEngine.build(system.sheetLayout!, for: page, system: system).flatMap(\.rows).map { ($0.id, $0.value) })
        }
        #expect(values()["evasion"] == .number(10) && values()["might"] == .check(modifier: 2, roll: "check"))
        #expect(values()["hp"] == .resource(current: 5, maximum: 5))

        // Damage, then a short rest that gives back 2 + tier, then a long rest.
        #expect(SheetEngine.adjust("hp", by: -4, on: page, system: system) == 1)
        let rule = try #require(system.advancement)
        Advancement.levelUp(page, rule: rule, formulas: system.formulas)
        #expect(page.attributeNumber("made.level") == 2 && page.attributeNumber("made.hpSlots") == 6)
        let hp = system.resources[0]
        let inputs = SheetEngine.inputs(for: page, advancement: rule)
        #expect(ResourceRules.valueAfter(rest: "short", resource: hp, current: page.attributeNumber("made.hp"), formulas: system.formulas, inputs: inputs) == 0)  // 4 spent, 2 + tier 2 back
        #expect(ResourceRules.valueAfter(rest: "long", resource: hp, current: 4, formulas: system.formulas, inputs: inputs) == 0)
        let hope = system.resources[1]
        #expect(ResourceRules.valueAfter(rest: "short", resource: hope, current: nil, formulas: system.formulas, inputs: inputs) == 6)
    }

    @Test func aFilesRollsAndConditionsWork() throws {
        let system = try makeSystem()
        let model = try #require(system.rollModel)
        var generator = SeededRandom(seed: 3)
        let roll = CheckRoller.roll(model, modifier: 1, mode: .advantage, target: 10, using: &generator)
        #expect(roll.dice.count == 2 && (1...6).contains(roll.bonusDie) && roll.higherDie != nil || roll.isCritical)

        func effect(_ roll: String, _ active: [String: Int]) -> RollConditionEffect {
            ConditionEngine.effect(on: roll, active: active, definitions: system.conditions)
        }
        #expect(effect("check", ["weary": 1]).mode == .disadvantage)
        #expect(effect("attack", ["weary": 1]).penalty == -2)
        #expect(effect("save.heart", ["dazed": 1]).autoFail == nil)
        #expect(effect("save.heart", ["dazed": 2]).autoFail == "Dazed: fails Heart saves")
    }

    @Test func aFileWithProblemsIsNotUsedAndSaysWhy() throws {
        func problems(_ edit: (String) -> String) -> [String] {
            guard let definition = SystemDefinition.decode(from: Data(edit(Self.json).utf8)) else { return ["unreadable"] }
            return definition.problems
        }
        #expect(problems { $0.replacingOccurrences(of: "\"tier\": \"1 + ceil((level - 1) / 3)\"", with: "\"tier\": \"1 +\"") }.contains { $0.contains("Formula tier") })
        #expect(problems { $0.replacingOccurrences(of: "\"restoredBy\": {\"long\"", with: "\"restoredBy\": {\"never\"") }.contains { $0.contains("not a rest") })
        #expect(problems { $0.replacingOccurrences(of: "\"resource\": \"hope\"", with: "\"resource\": \"luck\"") }.contains { $0.contains("luck") })
        #expect(problems { $0.replacingOccurrences(of: "\"characterCreation\"", with: "\"magic\"") }.contains { $0.contains("not a module") })
        #expect(problems { $0.replacingOccurrences(of: "\"appliesTo\": [\"character\"]}", with: "\"appliesTo\": [\"dragon\"]}") }.contains { $0.contains("made.level") })
        #expect(problems { $0.replacingOccurrences(of: "{\"id\": \"short\", \"name\": \"Short Rest\"}", with: "{\"id\": \"long\", \"name\": \"Short Rest\"}") }.contains { $0.contains("Two rests") })
        #expect(DataRuleSystem(data: Data(Self.json.replacingOccurrences(of: "\"formatVersion\": 1", with: "\"formatVersion\": 99").utf8)) == nil)
        #expect(DataRuleSystem(data: Data("not json".utf8)) == nil)
        // A kind of thing the file gets wrong is refused rather than guessed.
        #expect(DataRuleSystem(data: Data(Self.json.replacingOccurrences(of: "\"matchingDice\"", with: "\"sometimes\"").utf8)) == nil)
        #expect(DataRuleSystem(data: Data(Self.json.replacingOccurrences(of: "\"bonusDie\"", with: "\"coinFlip\"").utf8)) == nil)
    }
}
