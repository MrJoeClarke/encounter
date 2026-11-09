//
//  Page+Publishing.swift
//  encounter
//

import Foundation
import SwiftData

/// What players see of a page: its published version. The page's own fields are the draft the DM works on; this is a copy of them
/// from the moment the DM published. DM Notes, the page's place in the world (parent, maps, links) and its pictures are not in it.
nonisolated struct PublishedPage: Codable, Equatable, Sendable {
    var title: String
    var summary: String
    var body: AttributedString
    var attributes: [String: AttributeValue]
    var tags: [String]
    var characterRoleRaw: String?
    var eventOriginRaw: String?
    var startDate: InWorldDate?
    var endDate: InWorldDate?
}

/// Where a page stands with players.
enum PublishState {
    /// Players can't see it.
    case hidden
    /// Players see the published version, which is the page as it is.
    case published
    /// Players see the published version, and the page has been changed since.
    case publishedWithChanges

    var title: LocalizedStringResource {
        switch self {
        case .hidden: "Hidden from players"
        case .published: "Published"
        case .publishedWithChanges: "Published, with changes"
        }
    }

    var systemImage: String {
        switch self {
        case .hidden: "eye.slash"
        case .published: "eye"
        case .publishedWithChanges: "eye.trianglebadge.exclamationmark"
        }
    }
}

extension Page {
    /// The page as it is now, in the shape that is published.
    var draftVersion: PublishedPage {
        PublishedPage(
            title: title,
            summary: summary,
            body: body,
            attributes: attributes,
            tags: tags,
            characterRoleRaw: characterRoleRaw,
            eventOriginRaw: eventOriginRaw,
            startDate: startDate,
            endDate: endDate
        )
    }

    /// The version that was last published, if there is one.
    var publishedVersion: PublishedPage? {
        publishedData.flatMap { try? JSONDecoder().decode(PublishedPage.self, from: $0) }
    }

    /// What players see of this page: the published version. The world's own place is always shown, as it is.
    var versionForPlayers: PublishedPage? {
        if isWorldRoot { return draftVersion }
        return isPublished ? publishedVersion : nil
    }

    /// Whether players can see the page.
    var isVisibleToPlayers: Bool { versionForPlayers != nil }

    var publishState: PublishState {
        guard isPublished else { return .hidden }
        return publishedVersion == draftVersion ? .published : .publishedWithChanges
    }

    /// Makes the page as it is now the version players see. Also used to publish changes.
    func publish() {
        guard let data = try? JSONEncoder().encode(draftVersion) else { return }
        publishedData = data
        isPublished = true
    }

    /// Hides the page from players. The published version is kept, so a later Revert to Published has nothing lost.
    func unpublish() {
        isPublished = false
    }

    /// Puts the page back as it was when last published, losing the changes made since.
    func revertToPublished() {
        guard isPublished, let version = publishedVersion else { return }
        title = version.title
        summary = version.summary
        body = version.body
        attributes = version.attributes
        tags = version.tags
        characterRoleRaw = version.characterRoleRaw
        eventOriginRaw = version.eventOriginRaw
        startDate = version.startDate
        endDate = version.endDate
        updateSearchText()
    }
}

extension World {
    /// Publishes every page that is hidden, as it is now, and leaves published pages as they are.
    @discardableResult
    func publishAllHiddenPages() -> Int {
        var count = 0
        for page in pages ?? [] where !page.isDeleted && !page.isPublished && !page.isWorldRoot {
            page.publish()
            count += 1
        }
        return count
    }
}
