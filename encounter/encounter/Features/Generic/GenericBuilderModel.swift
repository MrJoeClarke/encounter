//
//  GenericBuilderModel.swift
//  encounter
//

import Foundation
import Observation
import SwiftData

/// The state of the character builder for a system that describes its creation as data (see `CreationFlow`): the draft, the
/// step it's on, and what the draft comes to.
@MainActor
@Observable
final class GenericBuilderModel {
    let world: World
    let system: any RuleSystem
    let flow: CreationFlow
    var draft = CreationDraft()
    var stepIndex = 0

    /// Nil if the world's system has no creation flow.
    init?(world: World) {
        let system = RuleSystems.system(forKey: world.systemRaw)
        guard let flow = system.creationFlow else { return nil }
        self.world = world
        self.system = system
        self.flow = flow
        for step in flow.steps {
            if case .names(let count, _, _) = step.kind { draft.names[step.id] = Array(repeating: "", count: count) }
        }
        // Each numbers step starts with its numbers given out in order, or its lowest number.
        for case .numbers(let rule) in flow.steps.map(\.kind) {
            for (index, entry) in rule.entries.enumerated() {
                switch rule.method {
                case .assignFrom(let available): draft.numbers[entry.key] = available.indices.contains(index) ? available[index] : available.first ?? 0
                case .free(let range): draft.numbers[entry.key] = range.lowerBound
                }
            }
        }
    }

    var step: CreationStep { flow.steps[stepIndex] }
    var canGoBack: Bool { stepIndex > 0 }
    var canGoForward: Bool { stepIndex + 1 < flow.steps.count }
    func goBack() { if canGoBack { stepIndex -= 1 } }
    func goForward() { if canGoForward { stepIndex += 1 } }

    var plan: CreationPlan { CreationEngine.plan(draft, flow: flow, formulas: system.formulas, in: world) }

    func options(for step: CreationStep) -> [ContentSource] {
        CreationEngine.options(for: step, in: world, draft: draft, formulas: system.formulas, level: flow.startingLevel)
    }

    /// Picks or unpicks an entry at a picking step, never holding more than the step asks for.
    func togglePick(_ source: ContentSource, for step: CreationStep) {
        guard case .pickEntries(_, let count, _, _) = step.kind, let key = source.libraryKey else { return }
        var picked = draft.picks[step.id] ?? []
        if let index = picked.firstIndex(of: key) { picked.remove(at: index) } else if picked.count < count { picked.append(key) }
        draft.picks[step.id] = picked
    }

    func selected(for step: CreationStep) -> ContentSource? { CharacterContent.resolve(draft.choices[step.id], in: world) }

    func choose(_ source: ContentSource, for step: CreationStep) {
        draft.choices[step.id] = source.choice
        // What was picked from this choice's children or entries no longer fits.
        for later in flow.steps {
            switch later.kind {
            case .chooseChild(let parent, _) where parent == step.id: draft.choices[later.id] = nil
            case .pickEntries: draft.picks[later.id] = []
            default: break
            }
        }
    }

    func clear(_ step: CreationStep) { draft.choices[step.id] = nil }

    /// Gives an entry a number from the set on offer, swapping with the entry that had it so each is used once.
    func assign(_ value: Int, to key: String, in rule: NumberRule) {
        guard let old = draft.numbers[key] else { return }
        if let other = rule.entries.first(where: { $0.key != key && draft.numbers[$0.key] == value }) { draft.numbers[other.key] = old }
        draft.numbers[key] = value
    }

    /// The numbers a numbers step offers, highest first and each once.
    func offered(_ rule: NumberRule) -> [Int] {
        switch rule.method {
        case .assignFrom(let available): Array(Set(available)).sorted(by: >)
        case .free(let range): Array(range)
        }
    }

    func create(in context: ModelContext) -> Page? {
        CreationEngine.create(draft, flow: flow, formulas: system.formulas, in: world, context: context)
    }
}
