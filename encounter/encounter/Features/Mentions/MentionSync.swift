//
//  MentionSync.swift
//  encounter
//

import Foundation
import SwiftData

/// Keeps `PageLink`s with the "mention" role in step with the mentions in each page's notes, and keeps the
/// mentions themselves tidy when a page is renamed or deleted.
enum MentionSync {
    /// Makes the page's mention links match its notes: one link per distinct page mentioned, none for pages
    /// outside the world or for the page itself. Links with other roles are never touched.
    static func sync(_ page: Page, in context: ModelContext) {
        guard let world = page.world else { return }

        let pagesByID = Dictionary((world.pages ?? []).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let wanted = Mention.mentionedIDs(in: page.body)
            .filter { $0 != page.id }
            .compactMap { pagesByID[$0] }
        let wantedIDs = Set(wanted.map(\.id))

        var linked = Set<UUID>()
        for link in page.outgoingLinks ?? [] where link.role == LinkRole.mention && !link.isDeleted {
            if let target = link.target, wantedIDs.contains(target.id), linked.insert(target.id).inserted {
                continue
            }
            context.delete(link)
        }
        for target in wanted where !linked.contains(target.id) {
            context.insert(PageLink(source: page, target: target, role: LinkRole.mention))
        }
    }

    /// After a page is renamed, updates the text of mentions of it in other pages' notes.
    /// A blank title is ignored, so clearing the field while retyping doesn't wipe the mentions.
    static func refreshMentions(of target: Page) {
        guard !target.title.isEmpty else { return }
        for link in target.incomingLinks ?? [] where link.role == LinkRole.mention && !link.isDeleted {
            guard let source = link.source else { continue }
            var body = source.body
            Mention.refreshTitles(in: &body, titles: [target.id: target.title])
            if body != source.body {
                source.body = body
                source.updateSearchText()
            }
        }
    }

    /// Deletes a page. Mentions of it in other pages' notes become plain text first, so nothing is left
    /// pointing at a page that no longer exists. Its links are removed along with it.
    static func delete(_ page: Page, in context: ModelContext) {
        for link in page.incomingLinks ?? [] where link.role == LinkRole.mention && !link.isDeleted {
            guard let source = link.source else { continue }
            var body = source.body
            Mention.stripMentions(of: [page.id], from: &body)
            if body != source.body {
                source.body = body
                source.updateSearchText()
            }
        }
        context.delete(page)
    }
}
