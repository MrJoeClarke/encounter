//
//  Page+Editing.swift
//  encounter
//

import Foundation
import SwiftData

extension World {
    /// Creates a blank page of the given kind in this world.
    @discardableResult
    func addPage(kind: PageKind, in context: ModelContext) -> Page {
        let page = Page(title: "", kind: kind)
        context.insert(page)
        page.world = self
        // Every place is inside the world's root place, unless something puts it somewhere more particular.
        if kind == .event { page.eventOrigin = .backstory }
        if kind == .place, let root = rootPlace {
            page.parent = root
            page.parentSource = .automatic
        }
        return page
    }
}

extension Page {
    func attributeText(_ key: String) -> String {
        if case .text(let value) = attributes[key] { value } else { "" }
    }

    /// An empty string removes the attribute rather than storing an empty value.
    func setAttributeText(_ key: String, _ value: String) {
        attributes[key] = value.isEmpty ? nil : .text(value)
    }

    func attributeNumber(_ key: String) -> Double? {
        if case .number(let value) = attributes[key] { value } else { nil }
    }

    func setAttributeNumber(_ key: String, _ value: Double?) {
        attributes[key] = value.map { .number($0) }
    }

    func attributeBool(_ key: String) -> Bool {
        if case .bool(let value) = attributes[key] { value } else { false }
    }

    /// False removes the attribute rather than storing it.
    func setAttributeBool(_ key: String, _ value: Bool) {
        attributes[key] = value ? .bool(true) : nil
    }

    /// The page this page links to with the given role, if any.
    func linkedPage(role: String) -> Page? {
        outgoingLinks?.first { $0.role == role && !$0.isDeleted }?.target
    }

    /// Replaces any existing link with the given role. Pass nil to clear it.
    func setLinkedPage(_ target: Page?, role: String, in context: ModelContext) {
        for link in outgoingLinks ?? [] where link.role == role {
            context.delete(link)
        }
        if let target {
            context.insert(PageLink(source: self, target: target, role: role))
        }
    }

    /// Adds a trimmed tag unless it's empty or already present (ignoring case). Returns whether it was added.
    @discardableResult
    func addTag(_ rawTag: String) -> Bool {
        let tag = rawTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty,
              !tags.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame })
        else { return false }
        tags.append(tag)
        return true
    }
}
