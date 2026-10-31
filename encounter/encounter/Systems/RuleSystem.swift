//
//  RuleSystem.swift
//  encounter
//

import Foundation

/// A game system that contributes extra attributes to pages, such as D&D 5e's armor class.
protocol RuleSystem {
    var id: RuleSystemID { get }
    /// Attributes this system adds. A definition whose key matches a core attribute replaces it.
    var attributes: [AttributeDefinition] { get }
    /// Page kinds that always appear in the sidebar of a world using this system, such as Classes.
    var additionalPageKinds: Set<PageKind> { get }
    /// Whether the system comes with a bundled content library (races, classes and so on).
    var hasContentLibrary: Bool { get }
}

extension RuleSystem {
    var additionalPageKinds: Set<PageKind> { [] }
    var hasContentLibrary: Bool { false }
}

/// No game system: only the core attributes apply.
struct NoRuleSystem: RuleSystem {
    let id = RuleSystemID.none
    let attributes: [AttributeDefinition] = []
}

enum RuleSystems {
    static func system(for id: RuleSystemID) -> any RuleSystem {
        switch id {
        case .none: NoRuleSystem()
        case .dnd5e: DnD5eSystem()
        }
    }

    /// The attributes for a page kind under a rule system: the core attributes, with any the system
    /// overrides replaced in place, followed by the system's additions.
    /// Values for attributes not listed here stay stored on the page, so switching systems loses nothing.
    static func definitions(for kind: PageKind, system id: RuleSystemID) -> [AttributeDefinition] {
        var result = CoreAttributes.definitions(for: kind)
        for definition in system(for: id).attributes where definition.appliesTo.contains(kind) {
            if let index = result.firstIndex(where: { $0.key == definition.key }) {
                result[index] = definition
            } else {
                result.append(definition)
            }
        }
        return result
    }
}
