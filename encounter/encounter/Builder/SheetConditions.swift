//
//  SheetConditions.swift
//  encounter
//

import Foundation

extension CharacterSheet {
    var edition: LibraryEdition { world.edition }

    // MARK: What the character is under

    var conditionState: ConditionState {
        let names = page.attributeText("dnd5e.conditions").split(separator: ",").compactMap { Condition(title: String($0)) }
        let level = min(6, max(0, Int(page.attributeNumber("dnd5e.exhaustionLevel") ?? 0)))
        return ConditionState(active: Set(names).subtracting([.exhaustion]), exhaustion: level)
    }

    func addCondition(_ condition: Condition) {
        if condition == .exhaustion {
            setExhaustion(max(1, conditionState.exhaustion))
            return
        }
        var state = conditionState
        state.active.insert(condition)
        store(state)
    }

    func removeCondition(_ condition: Condition) {
        if condition == .exhaustion {
            setExhaustion(0)
            return
        }
        var state = conditionState
        state.active.remove(condition)
        store(state)
    }

    func setExhaustion(_ level: Int) {
        var state = conditionState
        state.exhaustion = min(6, max(0, level))
        store(state)
    }

    private func store(_ state: ConditionState) {
        let names = Condition.allCases.filter { state.active.contains($0) }.map(\.title)
        page.setAttributeText("dnd5e.conditions", names.joined(separator: ", "))
        page.setAttributeNumber("dnd5e.exhaustionLevel", state.exhaustion == 0 ? nil : Double(state.exhaustion))
    }

    // MARK: What it does

    var attackEffect: RollConditionEffect { ConditionRules.attack(conditionState, edition: edition) }
    var checkEffect: RollConditionEffect { ConditionRules.abilityCheck(conditionState, edition: edition) }
    func saveEffect(_ ability: Ability) -> RollConditionEffect { ConditionRules.save(ability, conditionState, edition: edition) }
    var initiativeEffect: RollConditionEffect { ConditionRules.initiative(conditionState, edition: edition) }

    /// The conditions that stop the character taking actions or reactions.
    var incapacitatingConditions: [Condition] { ConditionRules.cantAct(conditionState) }

    /// What others get against the character while it is under these conditions.
    var againstYou: [String] { ConditionRules.againstYou(conditionState, edition: edition) }

    /// The speed in feet, from the speed's text ("30 feet", "30 ft., fly 60 ft."), or nil if it has none.
    var baseSpeed: Int? {
        speed.firstMatch(of: /\d+/).flatMap { Int($0.output) }
    }

    /// The speed with conditions applied, said as the sheet shows it. Unchanged when no condition changes it.
    var effectiveSpeed: String {
        guard let base = baseSpeed else { return speed }
        let now = ConditionRules.speed(base: base, conditionState, edition: edition)
        return now == base ? speed : "\(now) feet"
    }

    var speedIsChanged: Bool { baseSpeed.map { ConditionRules.speed(base: $0, conditionState, edition: edition) != $0 } ?? false }

    /// The hit point maximum with conditions applied.
    var effectiveMaximumHitPoints: Int { ConditionRules.maximumHitPoints(maximumHitPoints, conditionState, edition: edition) }

    /// The rules text of a condition from the library, if the edition has it.
    func rulesText(of condition: Condition) -> String? {
        Library.shared.entries(.condition, in: edition).first { $0.name == condition.title }?.summary
    }
}
