//
//  AttributeValue.swift
//  encounter
//

import Foundation

/// A value stored against a stable attribute key on a `Page`.
/// Attribute definitions (labels, types, rule-system grouping) arrive in the rule systems milestone.
enum AttributeValue: Codable, Hashable {
    case text(String)
    case number(Double)
    case bool(Bool)
    case list([String])
}
