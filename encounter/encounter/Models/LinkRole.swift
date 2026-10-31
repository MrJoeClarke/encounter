//
//  LinkRole.swift
//  encounter
//

import Foundation

/// The `role` strings stored on `PageLink`, and how to describe them from the target's point of view.
enum LinkRole {
    /// A mention in a page's notes. Derived from the notes text, never edited directly.
    static let mention = "mention"
    static let race = "race"
    static let characterClass = "class"
    static let background = "background"
    static let participant = "participant"
    static let location = "location"
    static let home = "home"
    static let member = "member"

    /// Describes what a link means when read from the page it points at, such as "Has this race".
    static func incomingDescription(_ role: String) -> LocalizedStringResource {
        switch role {
        case mention: "Mentions this page"
        case race: "Has this race"
        case characterClass: "Has this class"
        case background: "Has this background"
        case participant: "Took part"
        case location: "Happened here"
        case home: "Lives here"
        case member: "Is a member"
        default: "Linked"
        }
    }
}
