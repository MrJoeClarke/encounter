//
//  RuleSystem.swift
//  encounter
//

import Foundation

/// What a rule system has, as modules. Each is independent and optional: the screens ask the world's system whether it has
/// the module they need and show nothing if it doesn't, so a system with no levels has no Level Up, and a system with no
/// character sheet has no Sheet.
struct RuleModules: OptionSet, Sendable {
    let rawValue: Int

    /// A bundled content library (races, classes and so on) that can be searched, mentioned and built from.
    static let library = RuleModules(rawValue: 1 << 0)
    /// A guided flow that makes a playable character.
    static let characterCreation = RuleModules(rawValue: 1 << 1)
    /// Levelling a playable character up.
    static let advancement = RuleModules(rawValue: 1 << 2)
    /// A sheet to play a character from.
    static let sheet = RuleModules(rawValue: 1 << 3)
    /// Conditions that a character can be under, and what they do to its rolls.
    static let conditions = RuleModules(rawValue: 1 << 4)
}

/// A game system that contributes extra attributes to pages, such as D&D 5e's armor class, and the modules that make up
/// how it is played.
protocol RuleSystem {
    var id: RuleSystemID { get }
    /// Attributes this system adds. A definition whose key matches a core attribute replaces it.
    var attributes: [AttributeDefinition] { get }
    /// Page kinds that always appear in the sidebar of a world using this system, such as Classes.
    var additionalPageKinds: Set<PageKind> { get }
    /// The modules the system has.
    var modules: RuleModules { get }
}

extension RuleSystem {
    var additionalPageKinds: Set<PageKind> { [] }
    var modules: RuleModules { [] }

    /// Whether the system comes with a bundled content library (races, classes and so on).
    var hasContentLibrary: Bool { modules.contains(.library) }
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
