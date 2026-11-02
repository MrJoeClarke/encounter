//
//  RestEngine.swift
//  encounter
//

import Foundation

@MainActor
enum RestEngine {
    /// Takes a rest on a character's page: gives back what the resources say the rest gives back, then what each move chosen
    /// gives back, rolling any dice. Returns what changed as lines to show, or nil if the moves chosen aren't a valid choice.
    static func take(
        _ rest: RestDefinition, moves picks: [String], on page: Page, system: any RuleSystem,
        dice: ((_ count: Int, _ sides: Int) -> Double)?
    ) -> [String]? {
        guard rest.isValid(picks: picks) else { return nil }
        let inputs = SheetEngine.inputs(for: page, advancement: system.advancement)
        var lines: [String] = []

        func apply(_ resource: ResourceDefinition, rest id: String) {
            let before = page.attributeNumber(resource.key)
            guard let value = ResourceRules.valueAfter(
                rest: id, resource: resource, current: before, formulas: system.formulas, inputs: inputs, dice: dice
            ) else { return }
            page.setAttributeNumber(resource.key, value)
            let change = Int(value - (before ?? 0))
            if change != 0 { lines.append("\(resource.name): \(change > 0 ? "+" : "−")\(abs(change))") }
        }

        for resource in system.resources { apply(resource, rest: rest.id) }
        for pick in picks {
            guard let move = rest.moves.first(where: { $0.id == pick }) else { continue }
            for effect in move.effects {
                guard var resource = system.resources.first(where: { $0.id == effect.resource }) else { continue }
                // The move's own restoration stands in for what the resource says about this rest.
                resource.restoredBy[rest.id] = effect.restoration
                apply(resource, rest: rest.id)
            }
        }
        return lines
    }
}
