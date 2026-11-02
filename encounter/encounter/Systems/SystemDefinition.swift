//
//  SystemDefinition.swift
//  encounter
//

import Foundation

/// A whole rule system written as data (JSON), so a system can be supplied as a file instead of Swift. It brings together the
/// pieces a system is made of: attributes, modules, how checks are rolled, formulas, rests and resources, how a character is
/// made and levels, conditions, and the layout of the sheet.
nonisolated struct SystemDefinition: Decodable, Sendable {
    /// The highest `formatVersion` this app can read.
    static let supportedFormatVersion = 1

    var formatVersion: Int
    /// Raised by the author when the system's rules change, so worlds made under an older one can say so.
    var version: Int
    /// Permanent, and begins with the author's own name, such as "made.up".
    var id: String
    var name: String
    var modules: [String]
    /// Page kinds that always appear in the sidebar of a world using the system, by raw name ("class", "entry").
    var pageKinds: [String]
    /// The library editions (pack ids) worlds of the system can use, the first being the one they start on.
    var libraryEditions: [String]
    var attributes: [AttributeSpec]
    var rollModel: RollModel?
    var formulas: [String: String]
    var rests: [RestDefinition]
    var resources: [ResourceDefinition]
    var creation: CreationFlow?
    var advancement: AdvancementRule?
    var conditions: [ConditionDefinition]
    var sheet: SheetLayout?

    private enum CodingKeys: String, CodingKey {
        case formatVersion, version, id, name, modules, pageKinds, libraryEditions, attributes, rollModel, formulas, rests, resources, creation, advancement, conditions, sheet
    }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try c.decode(Int.self, forKey: .formatVersion)
        version = max(1, try c.decodeIfPresent(Int.self, forKey: .version) ?? 1)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        modules = try c.decodeIfPresent([String].self, forKey: .modules) ?? []
        pageKinds = try c.decodeIfPresent([String].self, forKey: .pageKinds) ?? []
        libraryEditions = try c.decodeIfPresent([String].self, forKey: .libraryEditions) ?? []
        attributes = try c.decodeIfPresent([AttributeSpec].self, forKey: .attributes) ?? []
        rollModel = try c.decodeIfPresent(RollModel.self, forKey: .rollModel)
        formulas = try c.decodeIfPresent([String: String].self, forKey: .formulas) ?? [:]
        rests = try c.decodeIfPresent([RestDefinition].self, forKey: .rests) ?? []
        resources = try c.decodeIfPresent([ResourceDefinition].self, forKey: .resources) ?? []
        creation = try c.decodeIfPresent(CreationFlow.self, forKey: .creation)
        advancement = try c.decodeIfPresent(AdvancementRule.self, forKey: .advancement)
        conditions = try c.decodeIfPresent([ConditionDefinition].self, forKey: .conditions) ?? []
        sheet = try c.decodeIfPresent(SheetLayout.self, forKey: .sheet)
    }

    /// Reads a system. Nil if it isn't valid JSON of the right shape or was written for a newer version of the app.
    static func decode(from data: Data) -> SystemDefinition? {
        guard let definition = try? JSONDecoder().decode(SystemDefinition.self, from: data),
              definition.formatVersion <= supportedFormatVersion
        else { return nil }
        return definition
    }

    fileprivate static let moduleNames: [String: RuleModules] = [
        "library": .library, "characterCreation": .characterCreation, "advancement": .advancement, "sheet": .sheet, "conditions": .conditions,
    ]

    /// What is wrong with the definition, in words for its author. Empty if it can be used.
    var problems: [String] {
        var found: [String] = []
        func formula(_ text: String, _ context: String) {
            if Formula(text) == nil { found.append("\(context): “\(text)” is not a formula.") }
        }
        func unique(_ ids: [String], _ what: String) {
            for id in Set(ids) where ids.filter({ $0 == id }).count > 1 { found.append("Two \(what) are called “\(id)”.") }
        }

        if id.isEmpty { found.append("The system has no id.") }
        for module in modules where Self.moduleNames[module] == nil { found.append("“\(module)” is not a module.") }
        for kind in pageKinds where PageKind(rawValue: kind) == nil { found.append("“\(kind)” is not a kind of page.") }
        for edition in libraryEditions where LibraryEdition(rawValue: edition) == nil { found.append("“\(edition)” is not a library this app has.") }
        for attribute in attributes where attribute.definition == nil { found.append("Attribute \(attribute.key) has an unknown type or page kind.") }
        for (name, text) in formulas { formula(text, "Formula \(name)") }

        unique(rests.map(\.id), "rests")
        unique(resources.map(\.id), "resources")
        unique(conditions.map(\.id), "conditions")
        for resource in resources {
            if let maximum = resource.maximum { formula(maximum, "Resource \(resource.id) maximum") }
            for (rest, restoration) in resource.restoredBy {
                if !rests.contains(where: { $0.id == rest }) { found.append("Resource \(resource.id) is restored by “\(rest)”, which is not a rest.") }
                if case .formula(let text) = restoration.amount { formula(text, "Resource \(resource.id) on \(rest)") }
                if let condition = restoration.condition { formula(condition, "Resource \(resource.id) on \(rest) condition") }
            }
        }
        for condition in conditions {
            for rule in condition.effects {
                if let when = rule.when { formula(when, "Condition \(condition.id)") }
                if case .penalty(let text, _) = rule.effect { formula(text, "Condition \(condition.id) penalty") }
            }
        }
        if let creation {
            unique(creation.steps.map(\.id), "creation steps")
            for (key, text) in creation.derived { formula(text, "Starting value \(key)") }
        }
        if let advancement {
            for gain in advancement.gains { formula(gain.formula, "Gain \(gain.key)") }
        }
        if let sheet {
            unique(sheet.sections.flatMap { $0.rows.map(\.id) }, "sheet rows")
            for row in sheet.sections.flatMap(\.rows) {
                switch row.kind {
                case .stat(let text, _), .check(let text, _, _): formula(text, "Sheet row \(row.id)")
                case .resource(let id):
                    if !resources.contains(where: { $0.id == id }) { found.append("Sheet row \(row.id) shows resource “\(id)”, which does not exist.") }
                case .text, .entries: break
                }
            }
        }
        return found
    }
}

/// An attribute a system adds to pages, as it is written in a system file.
nonisolated struct AttributeSpec: Decodable, Sendable {
    var key: String
    var label: String
    /// "text", "number", "bool", "choice" or "entries" (a list of named parts).
    var type: String
    var options: [String]
    /// Page kinds, by their raw names ("character", "item", and so on).
    var appliesTo: [String]
    var group: String

    private enum CodingKeys: String, CodingKey { case key, label, type, options, appliesTo, group }

    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key)
        label = try c.decode(String.self, forKey: .label)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "text"
        options = try c.decodeIfPresent([String].self, forKey: .options) ?? []
        appliesTo = try c.decode([String].self, forKey: .appliesTo)
        group = try c.decodeIfPresent(String.self, forKey: .group) ?? "Details"
    }

    /// The definition the page editor uses. Nil if the type or a page kind isn't known.
    var definition: AttributeDefinition? {
        let attributeType: AttributeType
        switch type {
        case "text": attributeType = .text
        case "number": attributeType = .number
        case "bool": attributeType = .bool
        case "choice": attributeType = .choice(options)
        case "entries": attributeType = .entries(showsLevel: false)
        default: return nil
        }
        let kinds = appliesTo.compactMap { PageKind(rawValue: $0) }
        guard !kinds.isEmpty, kinds.count == appliesTo.count else { return nil }
        return AttributeDefinition(
            key: key, label: LocalizedStringResource(stringLiteral: label), type: attributeType, appliesTo: Set(kinds),
            group: LocalizedStringResource(stringLiteral: group)
        )
    }
}

/// A rule system made from a `SystemDefinition`.
struct DataRuleSystem: RuleSystem {
    let definition: SystemDefinition
    /// Worlds can only choose from the systems the app names, so this stands in for it until they can choose any.
    let id = RuleSystemID.none

    var key: String { definition.id }
    var version: Int { definition.version }

    var attributes: [AttributeDefinition] { definition.attributes.compactMap(\.definition) }

    var modules: RuleModules {
        definition.modules.reduce(into: RuleModules()) { result, name in
            if let module = SystemDefinition.moduleNames[name] { result.insert(module) }
        }
    }

    var additionalPageKinds: Set<PageKind> { Set(definition.pageKinds.compactMap { PageKind(rawValue: $0) }) }
    var libraryEditions: [LibraryEdition] { definition.libraryEditions.compactMap { LibraryEdition(rawValue: $0) } }
    /// A system read from a file is shown by the generic screens.
    var usesGenericScreens: Bool { true }
    var rollModel: RollModel? { definition.rollModel }
    var formulas: FormulaSet { FormulaSet(definition.formulas) }
    var rests: [RestDefinition] { definition.rests }
    var resources: [ResourceDefinition] { definition.resources }
    var creationFlow: CreationFlow? { definition.creation }
    var advancement: AdvancementRule? { definition.advancement }
    var conditions: [ConditionDefinition] { definition.conditions }
    var sheetLayout: SheetLayout? { definition.sheet }

    /// A system from a file's contents. Nil if it can't be read or has problems.
    init?(data: Data) {
        guard let definition = SystemDefinition.decode(from: data), definition.problems.isEmpty else { return nil }
        self.definition = definition
    }
}
