//
//  DaggerheartTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// Daggerheart as a system built only from the modules: a system file and a content pack, shown by the generic screens' engines.
@MainActor
struct DaggerheartTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Demo")
        context.insert(world)
        world.choose(systemKey: "daggerheart")
        return (world, context)
    }

    private func makeCharacter(in world: World, context: ModelContext, className: String = "Bard") throws -> Page {
        let model = try #require(GenericBuilderModel(world: world))
        func pick(_ stepID: String, _ name: String) throws {
            let step = try #require(model.flow.steps.first { $0.id == stepID })
            let option = try #require(model.options(for: step).first { $0.name == name }, "\(name) is on offer")
            model.choose(option, for: step)
        }
        model.draft.name = "Ash"
        try pick("class", className)
        try pick("ancestry", "Human")
        try pick("community", "Wanderborne")
        return try #require(model.create(in: context))
    }

    @Test func theSystemShipsWithTheAppAndIsValid() throws {
        let system = try #require(SystemRegistry.shared.system(forKey: "daggerheart"))
        #expect(system.definition.problems.isEmpty)
        #expect(system.modules == [.library, .characterCreation, .advancement, .sheet, .conditions])
        #expect(system.libraryEditions == [.daggerheart] && system.usesGenericScreens)
        #expect(system.additionalPageKinds == [.characterClass, .contentEntry])
        #expect(RuleSystems.choices.contains { $0.key == "daggerheart" && $0.title == "Daggerheart" })
        let model = try #require(system.rollModel)
        #expect(model.dice.map(\.name) == ["Hope", "Fear"] && model.dice[0].gains == "hope" && model.dice[1].gains == nil)
        #expect(model.critical == .matchingDice && model.criticalAlwaysMeetsTarget && model.advantage == .bonusDie(sides: 6))
        #expect(system.resources.map(\.id) == ["hp", "stress", "armor", "hope"])
        #expect(DnD5eSystem().usesGenericScreens == false)
    }

    @Test func theContentPackHasTheSRDsClassesAncestriesCommunitiesAndCards() throws {
        let pack = try #require(Library.shared.pack(for: .daggerheart))
        #expect(pack.attribution.contains("Daggerheart System Reference Document 2.0") && pack.attribution.contains("Darrington Press Community Gaming"))
        let keys = pack.entries.map(\.key)
        #expect(Set(keys).count == keys.count && keys.allSatisfy { $0.hasPrefix("daggerheart.") })
        let classes = pack.entries.filter { $0.kind == .class }
        #expect(classes.count == 13 && pack.entries.filter { $0.kind == .subclass }.count == 26 && pack.entries.filter { $0.kind == .race }.count == 25)
        for entry in classes {
            #expect(Library.shared.children(of: entry, in: .daggerheart).count == 2, "\(entry.name) has two subclasses")
            guard case .number(let hp)? = entry.attributes["daggerheart.hitPoints"], case .number(let evasion)? = entry.attributes["daggerheart.evasion"] else {
                Issue.record("\(entry.name) needs hit points and evasion"); continue
            }
            #expect((4...10).contains(hp) && (8...13).contains(evasion), "\(entry.name)")
            #expect(entry.entries.count >= 2 && entry.entries.allSatisfy { !$0.text.isEmpty })
        }
        let cards = pack.entries.filter { $0.subKind == "daggerheart.domainCard" }
        #expect(cards.count == 210 && cards.allSatisfy { if case .number(let level)? = $0.attributes["daggerheart.cardLevel"] { (1...10).contains(level) } else { false } })
        #expect(pack.entries.filter { $0.subKind == "daggerheart.community" }.count == 15)
        // The text is plain: no markdown left over.
        #expect(!pack.entries.contains { $0.summary.contains("**") || $0.entries.contains { $0.text.contains("**") } })
        let lists = Library.shared.lists(in: .daggerheart)
        #expect(lists.contains(LibraryList(.class)) && lists.contains(LibraryList(.race)) && lists.contains(LibraryList(.entry, subKind: "daggerheart.domainCard")))
        #expect(String(localized: Library.shared.title(of: LibraryList(.race), in: .daggerheart)) == "Ancestries")
        // D&D's libraries are untouched.
        #expect(Library.shared.lists(in: .srd52).allSatisfy { $0.kind != .entry })
    }

    @Test func aWorldMovesToTheSystemsLibraryAndBack() throws {
        let (world, _) = try makeWorld()
        #expect(world.edition == .daggerheart && world.rules.contains(.library) && world.systemTitle == "Daggerheart" && world.systemStatus == .current)
        #expect(world.visibleKinds.contains(.characterClass) && world.visibleKinds.contains(.contentEntry))
        world.choose(systemKey: "dnd5e")
        #expect(world.edition == .srd52 && !world.visibleKinds.contains(.contentEntry))
        world.choose(systemKey: "daggerheart")
        #expect(world.edition == .daggerheart)
        let dnd = World(name: "D")
        dnd.choose(systemKey: "dnd5e")
        dnd.edition = .srd51
        dnd.choose(systemKey: "dnd5e")
        #expect(dnd.edition == .srd51, "a D&D world keeps the edition it has")
    }

    @Test func aCharacterIsMadeFromTheLibraryThroughTheFlow() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let bard = try #require(Library.shared.entry(forKey: "daggerheart.class.bard"))
        guard case .number(let hp)? = bard.attributes["daggerheart.hitPoints"], case .number(let evasion)? = bard.attributes["daggerheart.evasion"] else {
            Issue.record("no stats"); return
        }
        #expect(page.title == "Ash" && page.kind == .character && page.summary == "Bard Human Wanderborne")
        #expect(page.attributeNumber("daggerheart.hitPointSlots") == hp && page.attributeNumber("daggerheart.evasion") == evasion)
        #expect(page.attributeNumber("daggerheart.level") == 1 && page.attributeNumber("daggerheart.stressSlots") == 6 && page.attributeNumber("daggerheart.hope") == 2)
        #expect(page.libraryKey(role: "class") == bard.key && page.libraryKey(role: "ancestry") == "daggerheart.race.human")
        // The six traits are the +2, +1, +1, 0, 0, −1.
        let traits = ["agility", "strength", "finesse", "instinct", "presence", "knowledge"].compactMap { page.attributeNumber("daggerheart.\($0)") }
        #expect(traits.sorted() == [-1, 0, 0, 1, 1, 2])
    }

    @Test func theBuilderNeedsEachChoiceAndSwapsTraits() throws {
        let (world, _) = try makeWorld()
        let model = try #require(GenericBuilderModel(world: world))
        #expect(model.flow.steps.map(\.id) == ["concept", "class", "ancestry", "community", "traits", "review"])
        #expect(!model.plan.isReady && model.plan.problems.count == 4)
        guard case .numbers(let rule) = model.flow.steps[4].kind else { Issue.record("traits step"); return }
        let before = rule.entries.map { model.draft.numbers[$0.key] ?? 99 }
        #expect(before.sorted() == [-1, 0, 0, 1, 1, 2])
        model.assign(-1, to: "daggerheart.agility", in: rule)
        let after = rule.entries.map { model.draft.numbers[$0.key] ?? 99 }
        #expect(after[0] == -1 && after.sorted() == [-1, 0, 0, 1, 1, 2], "swapped, so each number is still used once")
        #expect(model.offered(rule) == [2, 1, 0, -1])
    }

    @Test func theSheetIsWorkedOutFromTheLayout() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        func values() throws -> [String: SheetValue] {
            Dictionary(uniqueKeysWithValues: SheetEngine.build(try #require(system.sheetLayout), for: page, system: system).flatMap(\.rows).map { ($0.id, $0.value) })
        }
        let start = try values()
        #expect(start["tier"] == .number(1) && start["major"] == .number(6) && start["severe"] == .number(12) && start["proficiency"] == .number(1))
        guard case .resource(let hp, let maximum)? = start["hp"], let slots = maximum else { Issue.record("hp row"); return }
        #expect(hp == slots)
        #expect(start["stress"] == .resource(current: 6, maximum: 6) && start["hope"] == .resource(current: 2, maximum: 6))
        guard case .check(let modifier, "check")? = start["agility"] else { Issue.record("agility row"); return }
        #expect(modifier == Int(page.attributeNumber("daggerheart.agility") ?? 99))

        // Marking hit points and stress, and spending and gaining Hope, within limits.
        #expect(SheetEngine.adjust("hp", by: -2, on: page, system: system) == slots - 2)
        #expect(page.attributeNumber("daggerheart.hitPointsMarked") == 2)
        #expect(SheetEngine.adjust("hope", by: 10, on: page, system: system) == 6)
        #expect(SheetEngine.adjust("hope", by: -10, on: page, system: system) == 0)
    }

    @Test func aShortRestRollsItsDiceAndALongRestClearsEverything() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        page.setAttributeNumber("daggerheart.hitPointsMarked", 5)
        page.setAttributeNumber("daggerheart.stressMarked", 4)
        let inputs = SheetEngine.inputs(for: page, advancement: system.advancement)
        let hp = try #require(system.resources.first { $0.id == "hp" })
        // 1d4 + tier, with the die showing 3 and the tier 1.
        #expect(ResourceRules.valueAfter(rest: "short", resource: hp, current: 5, formulas: system.formulas, inputs: inputs, dice: { _, _ in 3 }) == 1)
        #expect(ResourceRules.valueAfter(rest: "short", resource: hp, current: 5, formulas: system.formulas, inputs: inputs) == nil, "dice that can't be rolled give nothing")
        #expect(ResourceRules.valueAfter(rest: "long", resource: hp, current: 5, formulas: system.formulas, inputs: inputs) == 0)
        let hope = try #require(system.resources.first { $0.id == "hope" })
        #expect(ResourceRules.valueAfter(rest: "long", resource: hope, current: 1, formulas: system.formulas, inputs: inputs) == nil, "Hope is not restored by resting")
    }

    @Test func levellingTakesTheTierGainsAndTwoChoices() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        let rule = try #require(system.advancement)
        let slots = page.attributeNumber("daggerheart.hitPointSlots") ?? 0
        let evasion = page.attributeNumber("daggerheart.evasion") ?? 0

        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas) == nil, "the choices must use the points")
        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, picks: ["proficiency", "evasion"]) == nil)
        #expect(page.attributeNumber("daggerheart.level") == 1)
        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, picks: ["hitPoint", "evasion"]) != nil)
        #expect(page.attributeNumber("daggerheart.level") == 2 && page.attributeNumber("daggerheart.hitPointSlots") == slots + 1)
        #expect(page.attributeNumber("daggerheart.evasion") == evasion + 1 && page.attributeNumber("daggerheart.proficiency") == 2, "level 2 is a tier achievement")
        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, picks: ["proficiency"]) != nil)
        #expect(page.attributeNumber("daggerheart.proficiency") == 3)
        // Tiers and thresholds follow the level.
        let values = Dictionary(uniqueKeysWithValues: SheetEngine.build(system.sheetLayout!, for: page, system: system).flatMap(\.rows).map { ($0.id, $0.value) })
        #expect(values["tier"] == .number(2) && values["major"] == .number(8) && values["severe"] == .number(14))
        // Up to level 10 and no further.
        for _ in 4...10 { #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, picks: ["stress", "stress"]) != nil) }
        #expect(page.attributeNumber("daggerheart.level") == 10 && !Advancement.canLevelUp(page, rule: rule))
        #expect(page.attributeNumber("daggerheart.proficiency") == 5, "+1 at levels 2, 5 and 8, and the extra level 3 pick")
    }

    @Test func aDualityRollIsReadByHopeAndFear() throws {
        let system = RuleSystems.system(forKey: "daggerheart")
        let model = try #require(system.rollModel)
        var sawHope = false, sawFear = false
        for seed in UInt64(1)...60 {
            var generator = SeededRandom(seed: seed)
            let result = CheckRoller.roll(model, modifier: 2, mode: .advantage, target: 12, using: &generator)
            if result.higherDie == "Hope" { sawHope = true }
            if result.higherDie == "Fear" { sawFear = true }
            #expect(result.meetsTarget == (result.isCritical || result.total >= 12))
        }
        #expect(sawHope && sawFear)
    }

    @Test func formulasCanRollDice() {
        let formula = Formula("2d6 + d4 + bonus")
        #expect(formula?.hasDice == true && Formula("1 + bonus")?.hasDice == false)
        #expect(formula?.evaluate(["bonus": 1]) == nil, "no roller, no value")
        #expect(formula?.evaluate({ _ in 1 }, dice: { count, sides in Double(count * sides) }) == 17.0)
        #expect(Formula("0d6") == nil && Formula("1d1") == nil && Formula("d") != nil, "a bare d is just a name")
        #expect(Formula("1d4 + tier")?.variables == ["tier"])
    }
}
