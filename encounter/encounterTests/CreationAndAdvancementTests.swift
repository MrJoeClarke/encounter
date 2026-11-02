//
//  CreationAndAdvancementTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// A made-up, Daggerheart-shaped system proves the creation flow and advancement are data, not D&D.
@MainActor
struct CreationAndAdvancementTests {
    private static let traits = ["agility", "strength", "finesse", "instinct", "presence", "knowledge"]

    private let flow = CreationFlow(
        steps: [
            CreationStep(id: "concept", title: "Concept", kind: .concept),
            CreationStep(id: "class", title: "Class", kind: .choose(list: LibraryList(.class), isRequired: true)),
            CreationStep(id: "heritage", title: "Heritage", kind: .choose(list: LibraryList(.race), isRequired: false)),
            CreationStep(id: "traits", title: "Traits", kind: .numbers(NumberRule(
                entries: Self.traits.map { .init(key: "made.\($0)", label: $0.capitalized, variable: $0) },
                method: .assignFrom([2, 1, 1, 0, 0, -1])
            ))),
            CreationStep(id: "review", title: "Review", kind: .review),
        ],
        derived: [("made.hitPoints", "class_startingHitPoints"), ("made.evasion", "class_evasion + 0 * agility"), ("made.tier", "1 + ceil((level - 1) / 3)")],
        levelKey: "made.level"
    )

    private let advancement = AdvancementRule(
        levelKey: "made.level", maxLevel: 10,
        gains: [.init(key: "made.tier", formula: "1 + ceil((level - 1) / 3)"), .init(key: "made.hitPoints", formula: "current + 1")]
    )

    private func makeWorld() throws -> (World, ModelContext, Page) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W", system: .none)
        context.insert(world)
        let warrior = world.addPage(kind: .characterClass, in: context)
        warrior.title = "Warrior"
        warrior.setAttributeNumber("made.startingHitPoints", 6)
        warrior.setAttributeNumber("made.evasion", 11)
        return (world, context, warrior)
    }

    private func goodDraft(_ warrior: Page) -> CreationDraft {
        var draft = CreationDraft(name: "Ash")
        draft.choices["class"] = .page(warrior.id)
        for (trait, value) in zip(Self.traits, [2, 1, 1, 0, 0, -1]) { draft.numbers["made.\(trait)"] = value }
        return draft
    }

    @Test func aPlanSaysWhatIsMissing() throws {
        let (world, _, warrior) = try makeWorld()
        let empty = CreationEngine.plan(CreationDraft(), flow: flow, formulas: FormulaSet([:]), in: world)
        #expect(empty.problems.count == 3)
        #expect(empty.problems.contains { $0.contains("name") } && empty.problems.contains { $0.contains("class") } && empty.problems.contains { $0.contains("traits") })

        // The optional heritage is never in the way, and the numbers must be the ones on offer, each once.
        var draft = goodDraft(warrior)
        #expect(CreationEngine.plan(draft, flow: flow, formulas: FormulaSet([:]), in: world).isReady)
        draft.numbers["made.agility"] = 1
        #expect(!CreationEngine.plan(draft, flow: flow, formulas: FormulaSet([:]), in: world).isReady)
        draft.numbers["made.agility"] = nil
        #expect(!CreationEngine.plan(draft, flow: flow, formulas: FormulaSet([:]), in: world).isReady)
    }

    @Test func freeNumbersMustBeInRange() throws {
        let (world, _, _) = try makeWorld()
        let rule = NumberRule(entries: [.init(key: "k", label: "K", variable: "k")], method: .free(1...5))
        let flow = CreationFlow(steps: [CreationStep(id: "n", title: "Numbers", kind: .numbers(rule))], derived: [("d", "k * 2")], levelKey: nil)
        var draft = CreationDraft()
        draft.numbers["k"] = 6
        #expect(!CreationEngine.plan(draft, flow: flow, formulas: FormulaSet([:]), in: world).isReady)
        draft.numbers["k"] = 3
        let plan = CreationEngine.plan(draft, flow: flow, formulas: FormulaSet([:]), in: world)
        #expect(plan.isReady && plan.derived["d"] == 6)
    }

    @Test func theCharacterIsMadeFromTheChoicesAndTheDerivedNumbers() throws {
        let (world, context, warrior) = try makeWorld()
        let page = try #require(CreationEngine.create(goodDraft(warrior), flow: flow, formulas: FormulaSet([:]), in: world, context: context))

        #expect(page.kind == .character && page.title == "Ash" && page.characterRole == .playable && page.summary == "Warrior")
        #expect(page.reference(role: "class") == .page(warrior))
        #expect(page.attributeNumber("made.agility") == 2 && page.attributeNumber("made.knowledge") == -1)
        #expect(page.attributeNumber("made.hitPoints") == 6 && page.attributeNumber("made.evasion") == 11)
        #expect(page.attributeNumber("made.level") == 1 && page.attributeNumber("made.tier") == 1)
        #expect(CreationEngine.create(CreationDraft(), flow: flow, formulas: FormulaSet([:]), in: world, context: context) == nil)
    }

    @Test func aChoiceOffersLibraryEntriesAndTheWorldsPages() throws {
        let (world, _, warrior) = try makeWorld()
        let step = try #require(flow.steps.first { $0.id == "class" })
        // Without a library only the world's page is offered.
        #expect(CreationEngine.options(for: step, in: world).map(\.name) == [warrior.title])
        #expect(CreationEngine.options(for: flow.steps[0], in: world).isEmpty)
    }

    @Test func levellingFollowsTheFormulasAndStopsAtTheMaximum() throws {
        let (world, context, warrior) = try makeWorld()
        let page = try #require(CreationEngine.create(goodDraft(warrior), flow: flow, formulas: FormulaSet([:]), in: world, context: context))
        var tiers: [Double] = []
        for expected in 2...10 {
            let changes = try #require(Advancement.levelUp(page, rule: advancement, formulas: FormulaSet([:])))
            #expect(page.attributeNumber("made.level") == Double(expected))
            #expect(changes.contains { $0.key == "made.hitPoints" })
            tiers.append(page.attributeNumber("made.tier") ?? 0)
        }
        #expect(tiers == [2, 2, 2, 3, 3, 3, 4, 4, 4])
        #expect(page.attributeNumber("made.hitPoints") == 15)
        #expect(!Advancement.canLevelUp(page, rule: advancement))
        #expect(Advancement.levelUp(page, rule: advancement, formulas: FormulaSet([:])) == nil)
    }

    @Test func dndDescribesItsSharedStepsAndItsProficiencyAsData() throws {
        let flow = try #require(DnD5eSystem().creationFlow)
        // The steps match the builder's, in order, and are stored under the roles the builder uses.
        let builderOrder = ["concept", "race", "class", "background", "abilities", "review"]
        #expect(flow.steps.map(\.id) == builderOrder)
        let modelOrder = CharacterBuilderModel.Step.allCases.map { "\($0)" }
        let shared = ["concept", "race", "characterClass", "background", "abilities", "review"]
        #expect(modelOrder.filter { shared.contains($0) } == shared)
        #expect(flow.levelKey == "dnd5e.classLevel")

        let rule = try #require(DnD5eSystem().advancement)
        for level in 1...20 {
            let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
            let world = World(name: "W", system: .dnd5e)
            context.insert(world)
            let page = world.addPage(kind: .character, in: context)
            page.setAttributeNumber("dnd5e.classLevel", Double(level))
            if level < 20 {
                Advancement.levelUp(page, rule: rule, formulas: DnD5eSystem.formulaSet)
                #expect(page.attributeNumber("dnd5e.proficiencyBonus") == Double(CharacterRules.proficiencyBonus(atLevel: level + 1)), "level \(level + 1)")
            }
        }
        #expect(NoRuleSystem().creationFlow == nil && NoRuleSystem().advancement == nil)
    }
}
