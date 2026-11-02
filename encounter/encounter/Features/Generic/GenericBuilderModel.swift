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

    func options(for step: CreationStep) -> [ContentSource] { CreationEngine.options(for: step, in: world) }

    func selected(for step: CreationStep) -> ContentSource? { CharacterContent.resolve(draft.choices[step.id], in: world) }

    func choose(_ source: ContentSource, for step: CreationStep) { draft.choices[step.id] = source.choice }

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
