//
//  Page+Library.swift
//  encounter
//

import Foundation
import SwiftData

/// What a page refers to for a role such as "race": nothing, a page in the world, or a library entry.
enum ContentReference: Hashable {
    case none
    case page(Page)
    case library(String)
}

extension Page {
    private func libraryAttributeKey(role: String) -> String {
        "library.\(role)"
    }

    /// The key of the library entry this page refers to with the given role, such as a character's race.
    func libraryKey(role: String) -> String? {
        if case .text(let key) = attributes[libraryAttributeKey(role: role)], !key.isEmpty { key } else { nil }
    }

    func setLibraryKey(_ key: String?, role: String) {
        attributes[libraryAttributeKey(role: role)] = key.map { .text($0) }
    }

    /// What the page refers to for the role. A page refers to either a world page or a library entry, never both.
    func reference(role: String) -> ContentReference {
        if let linked = linkedPage(role: role) {
            .page(linked)
        } else if let key = libraryKey(role: role) {
            .library(key)
        } else {
            .none
        }
    }

    /// Points the role at a page, a library entry or nothing, clearing whichever it pointed at before.
    func setReference(_ reference: ContentReference, role: String, in context: ModelContext) {
        switch reference {
        case .none:
            setLinkedPage(nil, role: role, in: context)
            setLibraryKey(nil, role: role)
        case .page(let target):
            setLibraryKey(nil, role: role)
            setLinkedPage(target, role: role, in: context)
        case .library(let key):
            setLinkedPage(nil, role: role, in: context)
            setLibraryKey(key, role: role)
        }
    }
}
