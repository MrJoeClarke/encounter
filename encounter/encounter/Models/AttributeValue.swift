//
//  AttributeValue.swift
//  encounter
//

import Foundation

/// A value stored against a stable attribute key on a `Page`.
/// Attribute definitions (labels, types, rule-system grouping) arrive in the rule systems milestone.
nonisolated enum AttributeValue: Codable, Hashable, Sendable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case list([String])
    /// A list of named entries, such as a race's traits or a class's features.
    case entries([EntryValue])
}

/// One named entry in a list: a trait or a class feature. `level` is the class level it's gained at, if any.
nonisolated struct EntryValue: Codable, Hashable, Sendable {
    var name: String
    var level: Int?
    var text: String

    init(name: String = "", level: Int? = nil, text: String = "") {
        self.name = name
        self.level = level
        self.text = text
    }
}
