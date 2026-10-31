//
//  CharacterBuilderModel.swift
//  encounter
//

import Foundation
import Observation
import SwiftData

/// The state of the character builder: the draft, the step it's on, and what the draft comes to.
@MainActor
@Observable
final class CharacterBuilderModel {
    enum Step: Int, CaseIterable, Identifiable {
        case concept, race, characterClass, background, abilities, skills, tools, equipment, spells, review

        var id: Int { rawValue }
    }

    let world: World
    var draft = CharacterDraft()
    var step = Step.concept

    let races: [ContentSource]
    let classes: [ContentSource]
    let backgrounds: [ContentSource]

    init(world: World) {
        self.world = world
        races = CharacterContent.races(in: world)
        classes = CharacterContent.classes(in: world)
        backgrounds = CharacterContent.backgrounds(in: world)
        // The standard array to begin with, in the order the abilities are listed.
        draft.scores = Dictionary(uniqueKeysWithValues: zip(Ability.allCases, CharacterRules.standardArray))
    }

    var edition: LibraryEdition { world.edition }

    // MARK: What's chosen

    var race: ContentSource? { CharacterContent.resolve(draft.race, subrace: draft.subrace, in: world) }
    var characterClass: ContentSource? { CharacterContent.resolve(draft.characterClass, in: world) }
    var background: ContentSource? { CharacterContent.resolve(draft.background, in: world) }

    var subraces: [LibraryEntry] {
        guard let choice = draft.race, let base = races.first(where: { $0.choice == choice }) else { return [] }
        return CharacterContent.subraces(of: base, in: world)
    }

    var levelOneSubclasses: [LibraryEntry] {
        characterClass.map { CharacterContent.levelOneSubclasses(of: $0, in: world) } ?? []
    }

    var subclass: LibraryEntry? { draft.subclass.flatMap { Library.shared.entry(forKey: $0) } }

    var plan: CharacterPlan {
        var plan = CharacterPlanner.plan(draft, edition: edition, race: race, characterClass: characterClass, background: background,
                                         toolOptions: CharacterContent.toolOptions(in: world))
        if !levelOneSubclasses.isEmpty, draft.subclass == nil { plan.problems.append("Choose the class’s subclass.") }
        return plan
    }

    /// The abilities the race's bonus leaves for the player to choose from (2014).
    var raceBonus: AbilityBonuses? {
        guard edition == .srd51, let text = race?.entryText(named: "Ability Score Increase") else { return nil }
        let parsed = AbilityBonuses.parse(text)
        return parsed.isUnderstood ? parsed : nil
    }

    /// The abilities a 2024 background offers.
    var backgroundAbilities: [Ability] {
        SkillList.parse(background?.text("dnd5e.backgroundAbilityScores") ?? "").compactMap { Ability(name: $0) }
    }

    func spells(level: Int) -> [LibraryEntry] {
        characterClass.map { CharacterContent.spells(level: level, for: $0, in: world) } ?? []
    }

    // MARK: Changing the choices

    func chooseRace(_ source: ContentSource) {
        draft.race = source.choice
        draft.subrace = nil
        draft.raceBonusChoices = []
    }

    func chooseClass(_ source: ContentSource) {
        draft.characterClass = source.choice
        draft.subclass = nil
        draft.skills = draft.skills.intersection(Set(plan.backgroundSkills))
        draft.equipmentChoices = [:]
        draft.toolPicks["class"] = nil
        draft.cantrips = []
        draft.spells = []
    }

    func chooseBackground(_ source: ContentSource) {
        draft.background = source.choice
        draft.backgroundBonus = nil
        draft.skills = []
        draft.toolPicks["background"] = nil
        draft.equipmentChoices = [:]
    }

    /// Moves between the three ways of setting scores, starting each from a sensible set.
    func chooseMethod(_ method: ScoreMethod) {
        draft.method = method
        switch method {
        case .standardArray: draft.scores = Dictionary(uniqueKeysWithValues: zip(Ability.allCases, CharacterRules.standardArray))
        case .pointBuy: draft.scores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 8) })
        case .manual: draft.scores = Dictionary(uniqueKeysWithValues: Ability.allCases.map { ($0, 10) })
        }
    }

    /// Gives an ability a number from the standard array, swapping it with the ability that had it.
    func assign(_ value: Int, to ability: Ability) {
        guard let other = Ability.allCases.first(where: { draft.scores[$0] == value && $0 != ability }) else {
            draft.scores[ability] = value
            return
        }
        draft.scores[other] = draft.scores[ability]
        draft.scores[ability] = value
    }

    var pointsSpent: Int { CharacterRules.pointBuyTotal(of: Array(draft.scores.values)) ?? 0 }

    // MARK: Steps

    /// The steps in order, leaving out the spells for a class that doesn't cast.
    var steps: [Step] {
        let plan = plan
        return Step.allCases.filter { ($0 != .spells || plan.spellLimits.isCaster) && ($0 != .tools || !plan.toolChoices.isEmpty) }
    }

    var canGoBack: Bool { steps.first != step }
    var canGoForward: Bool { steps.last != step }

    func goBack() {
        if let index = steps.firstIndex(of: step), index > 0 { step = steps[index - 1] }
    }

    func goForward() {
        if let index = steps.firstIndex(of: step), index + 1 < steps.count { step = steps[index + 1] }
    }

    /// Makes the character, if the plan has nothing in the way.
    func create(in context: ModelContext) -> Page? {
        let plan = plan
        guard plan.problems.isEmpty, let race, let characterClass, let background else { return nil }
        return CharacterBuilder.create(draft, plan: plan, race: race, characterClass: characterClass, background: background,
                                       subclass: subclass, in: world, context: context)
    }
}
