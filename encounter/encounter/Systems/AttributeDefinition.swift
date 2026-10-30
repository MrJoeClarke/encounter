//
//  AttributeDefinition.swift
//  encounter
//

import Foundation

enum AttributeType: Hashable {
    case text
    case number
    /// A fixed set of options. The chosen option is stored as `AttributeValue.text`.
    case choice([String])
    /// A reference to another page of the given kind in the same world. Stored as a `PageLink` with
    /// the given role (not in `Page.attributes`) so it appears in backlinks.
    case pageReference(PageKind, role: String)
}

/// Describes one attribute: how it is labelled, edited and stored.
/// The editor builds its form from these, so rule systems add attributes without new UI.
struct AttributeDefinition: Identifiable {
    /// Stable storage key in `Page.attributes`, e.g. "core.creatureType". Never change a shipped key.
    let key: String
    let label: LocalizedStringResource
    let type: AttributeType
    let appliesTo: Set<PageKind>
    /// Section heading in the editor.
    let group: LocalizedStringResource

    var id: String { key }
}

/// Attributes that apply regardless of rule system.
enum CoreAttributes {
    static let all: [AttributeDefinition] = [
        // Characters
        .init(key: "core.race", label: "Race", type: .pageReference(.race, role: "race"), appliesTo: [.character], group: "Details"),
        .init(key: "core.creatureType", label: "Creature Type", type: .text, appliesTo: [.character], group: "Details"),
        .init(key: "core.age", label: "Age", type: .text, appliesTo: [.character], group: "Details"),
        .init(key: "core.occupation", label: "Occupation", type: .text, appliesTo: [.character], group: "Details"),

        // Places
        .init(
            key: "core.placeType",
            label: "Place Type",
            type: .choice(["Region", "Settlement", "Building", "Wilderness", "Point of Interest"]),
            appliesTo: [.place],
            group: "Details"
        ),
        .init(key: "core.population", label: "Population", type: .number, appliesTo: [.place], group: "Details"),

        // Items
        .init(key: "core.itemType", label: "Item Type", type: .text, appliesTo: [.item], group: "Details"),
        .init(key: "core.value", label: "Value", type: .text, appliesTo: [.item], group: "Details"),

        // Organisations
        .init(key: "core.organisationType", label: "Organisation Type", type: .text, appliesTo: [.organisation], group: "Details"),
        .init(key: "core.organisationSize", label: "Size", type: .text, appliesTo: [.organisation], group: "Details"),

        // Races
        .init(key: "core.lifespan", label: "Lifespan", type: .text, appliesTo: [.race], group: "Details"),
        .init(key: "core.raceSize", label: "Size", type: .text, appliesTo: [.race], group: "Details"),
    ]

    static func definitions(for kind: PageKind) -> [AttributeDefinition] {
        all.filter { $0.appliesTo.contains(kind) }
    }
}
