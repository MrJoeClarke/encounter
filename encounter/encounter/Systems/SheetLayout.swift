//
//  SheetLayout.swift
//  encounter
//

import Foundation

/// One line of a character sheet, as data.
nonisolated struct SheetRow: Equatable, Identifiable, Sendable {
    enum Kind: Equatable, Sendable {
        /// A number worked out by a formula. `inputs` says which page attribute each name in the formula stands for, and every
        /// number on the page can also be used by its full key, such as `dnd5e.strength`. `level` is the character's level.
        case stat(formula: String, inputs: [String: String])
        /// A number that is added to a roll, such as a saving throw, and what kind of roll that is for the conditions.
        case check(formula: String, inputs: [String: String], roll: String)
        /// One of the system's resources (see `ResourceDefinition`), shown with its maximum.
        case resource(String)
        case text(key: String)
        case entries(key: String)
    }

    var id: String
    var label: String
    var kind: Kind
}

nonisolated struct SheetSection: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var rows: [SheetRow]
}

/// How a system's character sheet is laid out: sections of rows, each worked out from the character's page. A generic screen can
/// show any system's sheet from this.
nonisolated struct SheetLayout: Equatable, Sendable {
    var sections: [SheetSection]
}

/// What a row comes to for one character.
nonisolated enum SheetValue: Equatable, Sendable {
    case number(Int)
    case check(modifier: Int, roll: String)
    /// What is left of a resource, and its most (nil if it has no most).
    case resource(current: Int, maximum: Int?)
    case text(String)
    case entries([EntryValue])
    /// A row whose formula can't be worked out, such as one with a number the character doesn't have yet.
    case unknown
}

nonisolated struct SheetRowValue: Equatable, Identifiable, Sendable {
    var row: SheetRow
    var value: SheetValue
    var id: String { row.id }
}

nonisolated struct SheetSectionValue: Equatable, Identifiable, Sendable {
    var section: SheetSection
    var rows: [SheetRowValue]
    var id: String { section.id }
}

@MainActor
enum SheetEngine {
    /// The numbers a character's formulas can use: every number on the page by its key, and the level.
    static func inputs(for page: Page, advancement: AdvancementRule?) -> [String: Double] {
        var result: [String: Double] = [:]
        for (key, value) in page.attributes {
            if case .number(let number) = value { result[key] = number }
        }
        if let advancement { result["level"] = Double(Advancement.level(of: page, rule: advancement)) }
        return result
    }

    /// Works out every row of the sheet.
    static func build(_ layout: SheetLayout, for page: Page, system: any RuleSystem) -> [SheetSectionValue] {
        let inputs = inputs(for: page, advancement: system.advancement)
        return layout.sections.map { section in
            SheetSectionValue(section: section, rows: section.rows.map { SheetRowValue(row: $0, value: value(of: $0, page: page, system: system, inputs: inputs)) })
        }
    }

    private static func value(of row: SheetRow, page: Page, system: any RuleSystem, inputs: [String: Double]) -> SheetValue {
        func number(_ formula: String, _ mapping: [String: String]) -> Int? {
            var scope = inputs
            for (name, key) in mapping { scope[name] = inputs[key] }
            return Formula(formula)?.evaluate({ system.formulas.value($0, scope) }).map { Int($0.rounded()) }
        }
        switch row.kind {
        case .stat(let formula, let mapping):
            return number(formula, mapping).map(SheetValue.number) ?? .unknown
        case .check(let formula, let mapping, let roll):
            return number(formula, mapping).map { .check(modifier: $0, roll: roll) } ?? .unknown
        case .resource(let id):
            guard let resource = system.resources.first(where: { $0.id == id }) else { return .unknown }
            return .resource(current: current(of: resource, page: page, system: system, inputs: inputs), maximum: maximum(of: resource, system: system, inputs: inputs))
        case .text(let key):
            return .text(page.attributeText(key))
        case .entries(let key):
            if case .entries(let list)? = page.attributes[key] { return .entries(list) }
            return .entries([])
        }
    }

    static func maximum(of resource: ResourceDefinition, system: any RuleSystem, inputs: [String: Double]) -> Int? {
        resource.maximum.flatMap { Formula($0)?.evaluate { system.formulas.value($0, inputs) } }.map { Int($0.rounded()) }
    }

    /// What is left of a resource, whichever way the page keeps it.
    static func current(of resource: ResourceDefinition, page: Page, system: any RuleSystem, inputs: [String: Double]) -> Int {
        let maximum = maximum(of: resource, system: system, inputs: inputs)
        let stored = page.attributeNumber(resource.key)
        switch resource.storage {
        case .remaining:
            let value = Int(stored ?? resource.startsAt ?? Double(maximum ?? 0))
            return max(0, maximum.map { min($0, value) } ?? value)
        case .spent:
            let spent = max(0, Int(stored ?? resource.startsAt ?? 0))
            return max(0, (maximum ?? spent) - spent)
        case .spentList:
            return 0
        }
    }

    /// Spends (negative) or gains (positive) some of a resource and keeps it between none and its most. Returns what is left.
    @discardableResult
    static func adjust(_ resourceID: String, by amount: Int, on page: Page, system: any RuleSystem) -> Int? {
        guard let resource = system.resources.first(where: { $0.id == resourceID }), resource.storage != .spentList else { return nil }
        let inputs = inputs(for: page, advancement: system.advancement)
        let maximum = maximum(of: resource, system: system, inputs: inputs)
        let left = max(0, maximum.map { min($0, current(of: resource, page: page, system: system, inputs: inputs) + amount) }
            ?? current(of: resource, page: page, system: system, inputs: inputs) + amount)
        switch resource.storage {
        case .remaining: page.setAttributeNumber(resource.key, Double(left))
        case .spent: page.setAttributeNumber(resource.key, Double(max(0, (maximum ?? 0) - left)))
        case .spentList: break
        }
        return left
    }
}
