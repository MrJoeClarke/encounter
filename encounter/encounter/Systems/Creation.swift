//
//  Creation.swift
//  encounter
//

import Foundation
import SwiftData

/// How a system's numbers are given out at creation, such as D&D's six ability scores or Daggerheart's six traits.
nonisolated struct NumberRule: Equatable, Sendable {
    struct Entry: Equatable, Sendable {
        /// The attribute on the page that holds it.
        var key: String
        var label: String
        /// What a formula calls it, such as "agility".
        var variable: String
    }

    enum Method: Equatable, Sendable {
        /// Each of these numbers is given to one entry, once, as in D&D's standard array or Daggerheart's +2, +1, +1, 0, 0, −1.
        case assignFrom([Int])
        /// Any whole number in the range.
        case free(ClosedRange<Int>)
    }

    var entries: [Entry]
    var method: Method
}

/// One step of making a character.
nonisolated struct CreationStep: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A name and a line about the character.
        case concept
        /// Pick one entry of a list in the library, or a page of the matching kind in the world. It is kept as a reference with
        /// the step's id as its role, and the numbers in what was picked are available to formulas.
        case choose(list: LibraryList, isRequired: Bool)
        /// Pick one of the children of what was picked at another step, such as a class's subclass.
        case chooseChild(of: String, isRequired: Bool)
        /// Name some things the character has, such as Experiences, each given the same value text, and kept as a list of entries.
        case names(count: Int, key: String, valueText: String)
        /// Pick several library entries that pass a filter, such as domain cards, kept as a list of entries.
        case pickEntries(list: LibraryList, count: Int, key: String, filter: EntryFilter)
        /// Give out numbers.
        case numbers(NumberRule)
        /// Look it over and make the character.
        case review
    }

    var id: String
    var title: String
    var kind: Kind
}

/// How a system makes a character, as data: the steps in order, the numbers worked out from the choices, and where the level is
/// kept.
nonisolated struct CreationFlow: Equatable, Sendable {
    var steps: [CreationStep]
    /// Attribute key → formula for numbers the character starts with. A formula can use the variables of the numbers given out,
    /// and of each choice's numeric attributes as `<stepId>_<name>`, where the name is the last part of the attribute's key.
    var derived: [(key: String, formula: String)]
    var levelKey: String?
    var startingLevel = 1
    /// A list of entries on the page that gets the features of what was chosen, each named after where it came from.
    var featuresKey: String?

    static func == (a: CreationFlow, b: CreationFlow) -> Bool {
        a.steps == b.steps && a.levelKey == b.levelKey && a.startingLevel == b.startingLevel && a.featuresKey == b.featuresKey
            && a.derived.map(\.key) == b.derived.map(\.key) && a.derived.map(\.formula) == b.derived.map(\.formula)
    }
}

/// What has been chosen so far.
nonisolated struct CreationDraft: Equatable, Sendable {
    var name = ""
    var summary = ""
    /// What was picked at each choosing step, by the step's id.
    var choices: [String: ContentChoice] = [:]
    /// The numbers given out, by attribute key.
    var numbers: [String: Int] = [:]
    /// What was typed at each naming step, by the step's id.
    var names: [String: [String]] = [:]
    /// The library entries picked at each picking step, by the step's id.
    var picks: [String: [String]] = [:]
}

/// What a draft comes to: what is in the way, and the numbers worked out from it.
nonisolated struct CreationPlan: Equatable, Sendable {
    var problems: [String] = []
    var derived: [String: Double] = [:]
    var isReady: Bool { problems.isEmpty }
}

@MainActor
enum CreationEngine {
    /// What can be picked at a step: the library's entries, then the world's own pages of the matching kind. A step that picks
    /// a child of an earlier choice offers that choice's children; one that picks entries offers those that pass its filter.
    static func options(for step: CreationStep, in world: World, draft: CreationDraft = CreationDraft(), formulas: FormulaSet = FormulaSet([:]), level: Int = 1) -> [ContentSource] {
        switch step.kind {
        case .choose(let list, _):
            var result: [ContentSource] = []
            if world.rules.contains(.library) {
                result += Library.shared.topLevelEntries(in: list, edition: world.edition).map { CharacterContent.source(for: $0) }
            }
            if let pageKind = list.kind.pageKind {
                let pages = (world.pages ?? []).filter {
                    $0.kind == pageKind && (list.kind != .entry || $0.attributeText(CoreAttributes.entryKindKey) == list.subKind)
                }
                result += pages.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }.map { CharacterContent.source(for: $0) }
            }
            return result
        case .chooseChild(let parent, _):
            guard case .library(let key)? = draft.choices[parent], let entry = Library.shared.entry(forKey: key) else { return [] }
            return Library.shared.children(of: entry, in: LibraryEdition(key: key) ?? world.edition).map { CharacterContent.source(for: $0) }
        case .pickEntries(let list, _, _, let filter):
            guard world.rules.contains(.library) else { return [] }
            let inputs = ["level": Double(level)]
            return Library.shared.topLevelEntries(in: list, edition: world.edition)
                .filter { filter.matches($0, chosen: { chosenAttributes($0, draft: draft, world: world) }, inputs: inputs, formulas: formulas) }
                .map { CharacterContent.source(for: $0) }
        default:
            return []
        }
    }

    /// The attributes of what was chosen at a step.
    static func chosenAttributes(_ step: String, draft: CreationDraft, world: World) -> [String: AttributeValue]? {
        CharacterContent.resolve(draft.choices[step], in: world)?.attributes
    }

    /// What is in the way of making the character, and the numbers worked out from the draft.
    static func plan(_ draft: CreationDraft, flow: CreationFlow, formulas: FormulaSet, in world: World) -> CreationPlan {
        var plan = CreationPlan()
        var inputs: [String: Double] = ["level": Double(flow.startingLevel)]

        for step in flow.steps {
            switch step.kind {
            case .concept:
                if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { plan.problems.append("Give the character a name.") }
            case .choose(_, let isRequired), .chooseChild(_, let isRequired):
                let source = CharacterContent.resolve(draft.choices[step.id], in: world)
                if let source {
                    for (key, value) in source.attributes {
                        if case .number(let number) = value, let name = key.split(separator: ".").last { inputs["\(step.id)_\(name)"] = number }
                    }
                } else if isRequired {
                    plan.problems.append("Choose the character’s \(step.title.lowercased()).")
                }
            case .names(let count, _, _):
                let given = (draft.names[step.id] ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                if given.count != count { plan.problems.append("Name \(count) for the character’s \(step.title.lowercased()).") }
            case .pickEntries(_, let count, _, _):
                if (draft.picks[step.id] ?? []).count != count { plan.problems.append("Pick \(count) for the character’s \(step.title.lowercased()).") }
            case .numbers(let rule):
                problems(in: draft, rule: rule, step: step, into: &plan)
                for entry in rule.entries { inputs[entry.variable] = Double(draft.numbers[entry.key] ?? 0) }
            case .review:
                break
            }
        }

        for (key, formula) in flow.derived {
            if let value = Formula(formula)?.evaluate({ formulas.value($0, inputs) }) { plan.derived[key] = value }
        }
        return plan
    }

    private static func problems(in draft: CreationDraft, rule: NumberRule, step: CreationStep, into plan: inout CreationPlan) {
        let given = rule.entries.map { draft.numbers[$0.key] }
        switch rule.method {
        case .assignFrom(let available):
            if given.contains(where: { $0 == nil }) || given.compactMap({ $0 }).sorted() != available.sorted() {
                plan.problems.append("Give each of the \(step.title.lowercased()) one of \(available.map(String.init).joined(separator: ", ")).")
            }
        case .free(let range):
            if given.contains(where: { $0 == nil || !range.contains($0!) }) {
                plan.problems.append("Each of the \(step.title.lowercased()) must be from \(range.lowerBound) to \(range.upperBound).")
            }
        }
    }

    /// Makes the character, if nothing is in the way.
    static func create(_ draft: CreationDraft, flow: CreationFlow, formulas: FormulaSet, in world: World, context: ModelContext) -> Page? {
        let plan = plan(draft, flow: flow, formulas: formulas, in: world)
        guard plan.isReady else { return nil }

        let page = world.addPage(kind: .character, in: context)
        page.title = draft.name.trimmingCharacters(in: .whitespaces)
        page.characterRole = .playable
        var names: [String] = []
        var features: [EntryValue] = []
        for step in flow.steps {
            switch step.kind {
            case .choose, .chooseChild:
                guard let choice = draft.choices[step.id], let source = CharacterContent.resolve(choice, in: world) else { continue }
                if case .choose = step.kind { names.append(source.name) }
                switch choice {
                case .library(let key): page.setReference(.library(key), role: step.id, in: context)
                case .page(let id):
                    if let target = world.pages?.first(where: { $0.id == id }) { page.setReference(.page(target), role: step.id, in: context) }
                }
                features += source.entries.filter { ($0.level ?? 0) <= flow.startingLevel }
                    .map { EntryValue(name: "\(source.name): \($0.name)", level: $0.level, text: $0.text) }
            case .names(_, let key, let valueText):
                let list = (draft.names[step.id] ?? []).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                page.attributes[key] = .entries(list.map { EntryValue(name: $0, text: valueText) })
            case .pickEntries(_, _, let key, _):
                let list = (draft.picks[step.id] ?? []).compactMap { Library.shared.entry(forKey: $0) }
                page.attributes[key] = .entries(list.map { EntryValue(name: $0.name, text: $0.detail ?? "") })
            case .numbers(let rule):
                for entry in rule.entries { page.setAttributeNumber(entry.key, draft.numbers[entry.key].map(Double.init)) }
            case .concept, .review:
                break
            }
        }
        if let featuresKey = flow.featuresKey, !features.isEmpty { page.attributes[featuresKey] = .entries(features) }
        for (key, value) in plan.derived { page.setAttributeNumber(key, value) }
        if let levelKey = flow.levelKey { page.setAttributeNumber(levelKey, Double(flow.startingLevel)) }
        page.summary = draft.summary.isEmpty ? names.joined(separator: " ") : draft.summary
        return page
    }
}
