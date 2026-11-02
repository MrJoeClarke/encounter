//
//  Resources.swift
//  encounter
//

import Foundation

/// A kind of rest a rule system has, such as a short or a long rest.
nonisolated struct RestDefinition: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
}

/// How a rest gives back a resource.
nonisolated struct Restoration: Equatable, Sendable {
    enum Amount: Equatable, Sendable {
        /// All of it.
        case full
        /// None of it. Only for what the page keeps the remaining amount of, such as temporary hit points.
        case empty
        /// A number worked out by a formula, such as "max(1, floor(level / 2))".
        case formula(String)
    }

    var amount: Amount
    /// A formula that must be more than 0 for the rest to restore anything, such as "usesPactMagic".
    var condition: String?

    static let full = Restoration(amount: .full)
    static let empty = Restoration(amount: .empty)
    static func formula(_ text: String, when condition: String? = nil) -> Restoration { Restoration(amount: .formula(text), condition: condition) }
    static func full(when condition: String) -> Restoration { Restoration(amount: .full, condition: condition) }
}

/// Something a character has that goes down and up as they play, kept on its page: hit points, Hope, stress, spell slots, the
/// marks of death saves.
nonisolated struct ResourceDefinition: Equatable, Identifiable, Sendable {
    enum Storage: Equatable, Sendable {
        /// The page keeps what is left. A rest restores towards the maximum, and "full" is the maximum.
        case remaining
        /// The page keeps what has been used. A rest takes it back down, and "full" is none used.
        case spent
        /// The page keeps a comma-separated list of what has been used at each level, as spell slots do. Only "full" applies.
        case spentList
    }

    var id: String
    var name: String
    /// The key of the attribute on the page that holds it.
    var key: String
    var storage: Storage
    /// A formula for the most there can be, or nil if there is no most.
    var maximum: String?
    /// What each kind of rest does to it, by the rest's id. A rest not listed leaves it alone.
    var restoredBy: [String: Restoration]
    /// What it is when the page has no value yet. Nil means the maximum, for what remains, and none, for what is spent.
    var startsAt: Double?

    init(
        id: String, name: String, key: String, storage: Storage, maximum: String? = nil,
        restoredBy: [String: Restoration] = [:], startsAt: Double? = nil
    ) {
        self.id = id
        self.name = name
        self.key = key
        self.storage = storage
        self.maximum = maximum
        self.restoredBy = restoredBy
        self.startsAt = startsAt
    }
}

nonisolated enum ResourceRules {
    /// What a resource's stored value becomes after a rest, or nil if the rest leaves it alone. `current` is the stored value
    /// (nil if the page has none yet); `formulas` and `inputs` are what the maximum and the amounts are worked out from.
    static func valueAfter(
        rest: String, resource: ResourceDefinition, current: Double?, formulas: FormulaSet, inputs: [String: Double]
    ) -> Double? {
        guard resource.storage != .spentList, let restoration = resource.restoredBy[rest] else { return nil }
        if let condition = restoration.condition {
            guard let value = Formula(condition)?.evaluate({ formulas.value($0, inputs) }), value > 0 else { return nil }
        }
        let maximum = resource.maximum.flatMap { Formula($0)?.evaluate { formulas.value($0, inputs) } }
        let stored = current ?? resource.startsAt ?? (resource.storage == .remaining ? maximum ?? 0 : 0)

        switch (restoration.amount, resource.storage) {
        case (.full, .remaining): return maximum ?? stored
        case (.empty, .remaining): return 0
        case (.empty, _): return nil
        case (.full, _): return 0
        case (.formula(let text), _):
            guard let amount = Formula(text)?.evaluate({ formulas.value($0, inputs) }) else { return nil }
            if resource.storage == .remaining {
                let raised = stored + amount
                return maximum.map { min($0, raised) } ?? raised
            }
            return max(0, stored - amount)
        }
    }

    /// The same for a list stored as text: after a rest that restores it fully, nothing is used.
    static func textAfter(rest: String, resource: ResourceDefinition, formulas: FormulaSet, inputs: [String: Double]) -> String? {
        guard resource.storage == .spentList, let restoration = resource.restoredBy[rest], restoration.amount == .full else { return nil }
        if let condition = restoration.condition {
            guard let value = Formula(condition)?.evaluate({ formulas.value($0, inputs) }), value > 0 else { return nil }
        }
        return ""
    }
}
