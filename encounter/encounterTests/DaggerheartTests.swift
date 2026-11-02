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
        func step(_ id: String) throws -> CreationStep { try #require(model.flow.steps.first { $0.id == id }) }
        func pick(_ stepID: String, _ name: String? = nil) throws {
            let step = try step(stepID)
            let options = model.options(for: step)
            let option = try #require(name.map { name in options.first { $0.name == name } } ?? options.first, "\(name ?? "something") is on offer for \(stepID)")
            model.choose(option, for: step)
        }
        model.draft.name = "Ash"
        try pick("class", className)
        try pick("ancestry", "Human")
        try pick("community", "Wanderborne")
        try pick("subclass")
        model.draft.names["experiences"] = ["Blacksmith", "Wanderer"]
        let cards = try step("domainCards")
        for option in model.options(for: cards).prefix(2) { model.togglePick(option, for: cards) }
        return try #require(model.create(in: context))
    }

    /// Takes the next level with the first of what each pick offers.
    @discardableResult
    private func levelUp(_ page: Page, picks: [String], selections: [String: [String]] = [:]) throws -> LevelUpResult {
        let system = RuleSystems.system(forKey: "daggerheart")
        let rule = try #require(system.advancement)
        let level = Advancement.level(of: page, rule: rule) + 1
        var required: [String: [String]] = [:]
        for choice in rule.required(onLevel: level) {
            switch choice.target {
            case .libraryEntry(let list, let key, let filter)?:
                required[choice.id] = Advancement.options(list: list, filter: filter, key: key, for: page, level: level, system: system).prefix(1).map(\.key)
            case .newEntry?: required[choice.id] = ["Experience \(level)"]
            default: break
            }
        }
        var counts: [String: Int] = [:]
        let leveled = picks.map { id -> LevelUpPick in
            counts[id, default: 0] += 1
            return LevelUpPick(id: id, selections: selections["\(id)#\(counts[id]! - 1)"] ?? selections[id] ?? [])
        }
        return try #require(Advancement.levelUp(page, rule: rule, formulas: system.formulas, system: system, picks: leveled, required: required))
    }

    @Test func theSystemShipsWithTheAppAndIsValid() throws {
        let system = try #require(SystemRegistry.shared.system(forKey: "daggerheart"))
        #expect(system.definition.problems.isEmpty)
        #expect(system.modules == [.library, .characterCreation, .advancement, .sheet, .conditions])
        #expect(system.libraryEditions == [.daggerheart] && system.usesGenericScreens)
        #expect(system.additionalPageKinds == [.characterClass, .contentEntry])
        #expect(RuleSystems.choices.contains { $0.key == "daggerheart" && $0.title == "Daggerheart" })
        let model = try #require(system.rollModel)
        #expect(model.dice.map(\.name) == ["Hope", "Fear"] && model.dice[0].gains == "hope" && model.dice[1].gains == "fear")
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
        // The Witch's subclasses are called Hedge and Moon in the SRD, and tables are plain lines.
        #expect(Library.shared.children(of: try #require(Library.shared.entry(forKey: "daggerheart.class.witch")), in: .daggerheart).map(\.name) == ["Hedge", "Moon"])
        #expect(!pack.entries.contains { $0.summary.contains("|") || $0.entries.contains { $0.text.contains("|") } })
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
        #expect(model.flow.steps.map(\.id) == ["concept", "class", "ancestry", "community", "subclass", "traits", "experiences", "domainCards", "review"])
        #expect(!model.plan.isReady && model.plan.problems.count == 7)
        guard case .numbers(let rule) = model.flow.steps[5].kind else { Issue.record("traits step"); return }
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

    @Test func aRestOffersMovesThatRollTheirDice() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        let short = try #require(system.rests.first { $0.id == "short" })
        let long = try #require(system.rests.first { $0.id == "long" })
        #expect(short.movesToChoose == 2 && short.moves.count == 5 && long.moves.count == 6)
        page.setAttributeNumber("daggerheart.hitPointsMarked", 5)
        page.setAttributeNumber("daggerheart.stressMarked", 4)
        page.setAttributeNumber("daggerheart.hope", 1)

        // The moves must be a valid choice of exactly two.
        #expect(RestEngine.take(short, moves: ["tendWounds"], on: page, system: system, dice: { _, _ in 3 }) == nil)
        #expect(RestEngine.take(short, moves: ["tendWounds", "nonsense"], on: page, system: system, dice: { _, _ in 3 }) == nil)
        #expect(page.attributeNumber("daggerheart.hitPointsMarked") == 5)
        // 1d4 + tier with the die showing 3 and the tier 1, taking two moves, and the same move may be taken twice.
        let lines = try #require(RestEngine.take(short, moves: ["tendWounds", "clearStress"], on: page, system: system, dice: { _, _ in 3 }))
        #expect(page.attributeNumber("daggerheart.hitPointsMarked") == 1 && page.attributeNumber("daggerheart.stressMarked") == 0)
        #expect(lines.contains("Hit Points: −4") && lines.contains("Stress: −4"))
        _ = RestEngine.take(short, moves: ["tendWounds", "tendWounds"], on: page, system: system, dice: { _, _ in 3 })
        #expect(page.attributeNumber("daggerheart.hitPointsMarked") == 0, "never below none marked")
        // Dice that can't be rolled change nothing.
        page.setAttributeNumber("daggerheart.hitPointsMarked", 3)
        _ = RestEngine.take(short, moves: ["tendWounds", "tendWounds"], on: page, system: system, dice: nil)
        #expect(page.attributeNumber("daggerheart.hitPointsMarked") == 3)
        // A long rest clears everything of a kind, and Preparing gives Hope, more with the party.
        _ = RestEngine.take(long, moves: ["tendAllWounds", "prepareParty"], on: page, system: system, dice: nil)
        #expect(page.attributeNumber("daggerheart.hitPointsMarked") == 0 && page.attributeNumber("daggerheart.hope") == 3)
        _ = RestEngine.take(long, moves: ["prepareParty", "prepareParty"], on: page, system: system, dice: nil)
        #expect(page.attributeNumber("daggerheart.hope") == 6, "Hope stops at its most")
    }

    @Test func aNewCharacterHasItsFeaturesExperiencesCardsAndSubclass() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        guard case .entries(let experiences)? = page.attributes["daggerheart.experiences"], case .entries(let cards)? = page.attributes["daggerheart.domainCards"],
              case .entries(let features)? = page.attributes["daggerheart.features"] else { Issue.record("lists"); return }
        #expect(experiences.map(\.name) == ["Blacksmith", "Wanderer"] && experiences.allSatisfy { $0.text == "+2" })
        #expect(cards.count == 2 && cards.allSatisfy { !$0.name.isEmpty })
        // The cards are of the class's domains and no higher than level 1.
        for card in cards {
            let entry = try #require(Library.shared.entries(.entry, in: .daggerheart).first { $0.name == card.name })
            guard case .text(let domain)? = entry.attributes["daggerheart.domain"], case .number(let level)? = entry.attributes["daggerheart.cardLevel"] else { Issue.record("card"); continue }
            #expect(["Grace", "Codex"].contains(domain) && level == 1)
        }
        // Features come from the class (with its Hope feature), the ancestry, the community, and the subclass's foundation only.
        #expect(features.contains { $0.name.hasPrefix("Bard: Hope Feature") } && features.contains { $0.name.hasPrefix("Human:") } && features.contains { $0.name.hasPrefix("Wanderborne:") })
        let subclass = try #require(page.libraryKey(role: "subclass").flatMap { Library.shared.entry(forKey: $0) })
        #expect(features.contains { $0.name.hasPrefix("\(subclass.name):") } && features.allSatisfy { ($0.level ?? 1) <= 1 })
        #expect(subclass.parent == "daggerheart.class.bard")
        _ = system
    }

    @Test func aSubclassCanOnlyBeOneOfTheClassesOwn() throws {
        let (world, _) = try makeWorld()
        let model = try #require(GenericBuilderModel(world: world))
        let classStep = try #require(model.flow.steps.first { $0.id == "class" })
        let subclassStep = try #require(model.flow.steps.first { $0.id == "subclass" })
        #expect(model.options(for: subclassStep).isEmpty, "no class yet")
        model.choose(try #require(model.options(for: classStep).first { $0.name == "Wizard" }), for: classStep)
        let wizards = model.options(for: subclassStep).map(\.name)
        #expect(wizards.sorted() == ["School of Knowledge", "School of War"])
        model.choose(try #require(model.options(for: subclassStep).first), for: subclassStep)
        model.choose(try #require(model.options(for: classStep).first { $0.name == "Bard" }), for: classStep)
        #expect(model.draft.choices["subclass"] == nil, "changing class clears the subclass")
        #expect(Set(model.options(for: subclassStep).map(\.name)) == ["Troubadour", "Wordsmith"])
    }

    @Test func levellingTakesTheTierGainsTheFreeCardAndTwoChoices() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        let rule = try #require(system.advancement)
        let slots = page.attributeNumber("daggerheart.hitPointSlots") ?? 0
        let evasion = page.attributeNumber("daggerheart.evasion") ?? 0

        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, system: system, picks: []) == nil, "the choices must use the points")
        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, system: system, picks: [LevelUpPick(id: "proficiency"), LevelUpPick(id: "evasion")]) == nil)
        #expect(Advancement.levelUp(page, rule: rule, formulas: system.formulas, system: system, picks: [LevelUpPick(id: "hitPoint"), LevelUpPick(id: "evasion")]) == nil, "a new card and a new Experience must be said")
        #expect(page.attributeNumber("daggerheart.level") == 1)

        let result = try levelUp(page, picks: ["hitPoint", "evasion"])
        #expect(page.attributeNumber("daggerheart.level") == 2 && page.attributeNumber("daggerheart.hitPointSlots") == slots + 1)
        #expect(page.attributeNumber("daggerheart.evasion") == evasion + 1 && page.attributeNumber("daggerheart.proficiency") == 2, "level 2 is a tier achievement")
        #expect(result.notes.contains { $0.hasPrefix("New domain card:") } && result.notes.contains("New Experience: Experience 2 +2"))
        guard case .entries(let cards)? = page.attributes["daggerheart.domainCards"], case .entries(let experiences)? = page.attributes["daggerheart.experiences"] else { Issue.record("lists"); return }
        #expect(cards.count == 3 && experiences.count == 3)
        try levelUp(page, picks: ["proficiency"])
        #expect(page.attributeNumber("daggerheart.proficiency") == 3)
        let values = Dictionary(uniqueKeysWithValues: SheetEngine.build(system.sheetLayout!, for: page, system: system).flatMap(\.rows).map { ($0.id, $0.value) })
        #expect(values["tier"] == .number(2) && values["major"] == .number(8) && values["severe"] == .number(14))
        // Up to level 10 and no further.
        for _ in 4...10 { try levelUp(page, picks: ["stress", "stress"]) }
        #expect(page.attributeNumber("daggerheart.level") == 10 && !Advancement.canLevelUp(page, rule: rule))
        #expect(page.attributeNumber("daggerheart.proficiency") == 5, "+1 at levels 2, 5 and 8, and the extra level 3 pick")
    }

    @Test func traitsRaisedOnLevellingAreMarkedUntilTheNextTier() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        let rule = try #require(system.advancement)
        let agility = page.attributeNumber("daggerheart.agility") ?? 0
        let strength = page.attributeNumber("daggerheart.strength") ?? 0

        try levelUp(page, picks: ["traits", "hitPoint"], selections: ["traits#0": ["daggerheart.agility", "daggerheart.strength"]])
        #expect(page.attributeNumber("daggerheart.agility") == agility + 1 && page.attributeNumber("daggerheart.strength") == strength + 1)
        #expect(page.attributeText("daggerheart.markedTraits") == "daggerheart.agility, daggerheart.strength")
        // Marked traits can't be raised again, nor the same one twice, and the pick must name two.
        let open = Advancement.openAttributes(keys: ["daggerheart.agility", "daggerheart.strength", "daggerheart.finesse"], marks: "daggerheart.markedTraits", on: page)
        #expect(open == ["daggerheart.finesse"])
        let again = LevelUpPick(id: "traits", selections: ["daggerheart.agility", "daggerheart.finesse"])
        let choice = try #require(rule.choices.first { $0.id == "traits" })
        #expect(!Advancement.isComplete(again, choice: choice, on: page, level: 3, system: system))
        #expect(!Advancement.isComplete(LevelUpPick(id: "traits", selections: ["daggerheart.finesse", "daggerheart.finesse"]), choice: choice, on: page, level: 3, system: system))
        #expect(Advancement.isComplete(LevelUpPick(id: "traits", selections: ["daggerheart.finesse", "daggerheart.instinct"]), choice: choice, on: page, level: 3, system: system), "two traits that are still open can be raised")
        // The marks come off at the next tier, level 5.
        try levelUp(page, picks: ["stress", "stress"])
        try levelUp(page, picks: ["stress", "stress"])
        #expect(page.attributeText("daggerheart.markedTraits") == "daggerheart.agility, daggerheart.strength")
        try levelUp(page, picks: ["stress", "stress"])
        #expect(page.attributeNumber("daggerheart.level") == 5 && page.attributeText("daggerheart.markedTraits").isEmpty)
    }

    @Test func experiencesAndSubclassCardsAreRaisedAndTaken() throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let subclass = try #require(page.libraryKey(role: "subclass").flatMap { Library.shared.entry(forKey: $0) })

        let result = try levelUp(page, picks: ["experiences", "subclass"], selections: ["experiences#0": ["Blacksmith", "Wanderer"]])
        guard case .entries(let experiences)? = page.attributes["daggerheart.experiences"], case .entries(let features)? = page.attributes["daggerheart.features"] else { Issue.record("lists"); return }
        #expect(experiences.prefix(2).map(\.text) == ["+3", "+3"] && experiences.last?.text == "+2")
        #expect(result.notes.contains("Blacksmith +2 → +3"))
        let specialization = subclass.entries.filter { $0.level == 2 }.map { "\(subclass.name): \($0.name)" }
        #expect(!specialization.isEmpty && specialization.allSatisfy { name in features.contains { $0.name == name } })
        #expect(features.contains { $0.level == 2 } && !features.contains { $0.level == 3 })
        // The next card is the mastery, and after that there is nothing to take.
        try levelUp(page, picks: ["subclass", "stress"])
        #expect(features.count < ({ if case .entries(let all)? = page.attributes["daggerheart.features"] { all.count } else { 0 } })())
        let system = RuleSystems.system(forKey: "daggerheart")
        #expect(Advancement.nextSubclassFeatures(role: "subclass", key: "daggerheart.features", on: page).isEmpty)
        let pick = LevelUpPick(id: "subclass")
        #expect(!Advancement.isComplete(pick, choice: try #require(system.advancement?.choices.first { $0.id == "subclass" }), on: page, level: 4, system: system))
        // An experience that isn't there can't be raised.
        let bogus = LevelUpPick(id: "experiences", selections: ["Nobody", "Wanderer"])
        #expect(!Advancement.isComplete(bogus, choice: try #require(system.advancement?.choices.first { $0.id == "experiences" }), on: page, level: 4, system: system))
    }

    @Test func fearBelongsToTheWholeWorld() async throws {
        let (world, context) = try makeWorld()
        let page = try makeCharacter(in: world, context: context)
        let system = RuleSystems.system(forKey: "daggerheart")
        let fear = try #require(system.worldResources.first { $0.id == "fear" })
        #expect(SheetEngine.worldValue(fear, world: world, system: system) == (0, 12))
        #expect(SheetEngine.adjustWorld("fear", by: 3, on: world, system: system) == 3)
        #expect(SheetEngine.adjustWorld("fear", by: -9, on: world, system: system) == 0)
        #expect(SheetEngine.adjustWorld("fear", by: 99, on: world, system: system) == 12)
        #expect(SheetEngine.adjustWorld("nothing", by: 1, on: world, system: system) == nil)
        // A second character in the same world sees the same Fear, and the rolled Fear die gives it.
        let other = world.addPage(kind: .character, in: context)
        #expect(other.world === page.world && world.systemState["fear"] == 12)
        let model = try #require(system.rollModel)
        #expect(model.dice[1].gains == "fear" && system.worldResources.contains { $0.id == model.dice[1].gains })
        // It is kept with the world through export and import.
        let contents = try WorldPackage.contents(of: WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world)))
        let (imported, _) = await WorldImporter.importWorld(contents, into: ModelContext(try AppSchema.makeContainer(inMemory: true)))
        #expect(imported.systemState == ["fear": 12])
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

    @Test func theSystemFileCatchesMistakesInTheNewParts() throws {
        let url = try #require(Bundle(for: SystemRegistry.self).url(forResource: "daggerheart.system", withExtension: "json"))
        let original = try String(contentsOf: url, encoding: .utf8)
        func problems(_ edit: (String) -> String) -> [String] {
            SystemDefinition.decode(from: Data(edit(original).utf8))?.problems ?? ["unreadable"]
        }
        #expect(problems { $0 }.isEmpty)
        #expect(problems { $0.replacingOccurrences(of: "\"of\": \"class\"", with: "\"of\": \"nothing\"") }.contains { $0.contains("not an earlier step") })
        #expect(problems { $0.replacingOccurrences(of: "\"resource\": \"stress\"", with: "\"resource\": \"luck\"") }.contains { $0.contains("luck") })
        #expect(problems { $0.replacingOccurrences(of: "\"gains\": \"fear\"", with: "\"gains\": \"doom\"") }.contains { $0.contains("not a resource") })
        #expect(problems { $0.replacingOccurrences(of: "\"formula\": \"level\"", with: "\"formula\": \"level +\"") }.contains { $0.contains("filter") })
        #expect(problems { $0.replacingOccurrences(of: "\"type\": \"newEntry\"", with: "\"type\": \"somethingElse\"") } == ["unreadable"])
    }
}

