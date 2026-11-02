//
//  EntryFilter.swift
//  encounter
//

import Foundation

/// Which library entries can be picked, as data: such as domain cards that belong to the character's class and are no higher than
/// their level.
nonisolated struct EntryFilter: Equatable, Sendable {
    /// A text attribute of the entry that must be found in a text attribute of what was chosen earlier (a class, say).
    struct Within: Equatable, Sendable {
        var entryKey: String
        /// The step (or role) the earlier choice was made at.
        var step: String
        var key: String
    }

    /// A number attribute of the entry that must be no more than a formula, which can use `level`.
    struct AtMost: Equatable, Sendable {
        var entryKey: String
        var formula: String
    }

    var within: [Within] = []
    var atMost: [AtMost] = []

    static let none = EntryFilter()

    /// Whether the entry passes. `chosen` gives the attributes of what was chosen at a step.
    func matches(
        _ entry: LibraryEntry, chosen: (String) -> [String: AttributeValue]?, inputs: [String: Double], formulas: FormulaSet
    ) -> Bool {
        for rule in within {
            guard case .text(let value)? = entry.attributes[rule.entryKey],
                  case .text(let source)? = chosen(rule.step)?[rule.key], source.localizedCaseInsensitiveContains(value)
            else { return false }
        }
        for rule in atMost {
            guard case .number(let value)? = entry.attributes[rule.entryKey],
                  let limit = Formula(rule.formula)?.evaluate({ formulas.value($0, inputs) }), value <= limit
            else { return false }
        }
        return true
    }
}
