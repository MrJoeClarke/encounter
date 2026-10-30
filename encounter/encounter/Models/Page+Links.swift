//
//  Page+Links.swift
//  encounter
//

import Foundation
import SwiftData

/// One page pointing at another, as shown in a "Referenced by" list.
struct Backlink: Identifiable {
    let id: UUID
    let source: Page
    let role: String
}

extension Page {
    /// Everything that points at this page: mentions in other pages' notes and structured links such as a
    /// character's race or an event's location. Sorted by the other page's title.
    var backlinks: [Backlink] {
        (incomingLinks ?? [])
            .filter { !$0.isDeleted }
            .compactMap { link in link.source.map { Backlink(id: link.id, source: $0, role: link.role) } }
            .sorted { ($0.source.title, $0.role) < ($1.source.title, $1.role) }
    }

    /// The pages this page's notes mention, sorted by title.
    var mentionedPages: [Page] {
        (outgoingLinks ?? [])
            .filter { $0.role == LinkRole.mention && !$0.isDeleted }
            .compactMap(\.target)
            .sorted { $0.title < $1.title }
    }
}
