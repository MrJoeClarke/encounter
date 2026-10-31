//
//  Mention.swift
//  encounter
//

import Foundation
import SwiftUI

/// What a mention points at: a page in the world, or an entry in the content library.
enum MentionTarget: Hashable {
    case page(UUID)
    case library(String)
}

/// Mentions of other pages, and of library entries such as a class or species, inside a page's notes.
///
/// A mention is a standard link run in the notes pointing at `encounter://page/<page id>` or
/// `encounter://library/<entry key>`. A standard link is used because custom text attributes don't survive
/// being saved or exported with the default coders.
enum Mention {
    static let scheme = "encounter"
    static let host = "page"
    static let libraryHost = "library"

    static func url(forLibraryKey key: String) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = libraryHost
        components.path = "/" + key
        guard let url = components.url else {
            fatalError("A scheme, host and library key always make a valid URL")
        }
        return url
    }

    /// The library entry a mention URL points at, or nil if it isn't a library mention URL.
    static func libraryKey(from url: URL) -> String? {
        guard url.scheme == scheme, url.host == libraryHost else { return nil }
        let key = url.lastPathComponent
        return key.isEmpty || key == "/" ? nil : key
    }

    static func target(from url: URL) -> MentionTarget? {
        if let id = pageID(from: url) { return .page(id) }
        if let key = libraryKey(from: url) { return .library(key) }
        return nil
    }

    /// The library entries mentioned in the notes, in order of first appearance, without repeats.
    static func mentionedLibraryKeys(in body: AttributedString) -> [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for run in body.runs {
            if let url = run.link, let key = libraryKey(from: url), seen.insert(key).inserted {
                ordered.append(key)
            }
        }
        return ordered
    }

    /// A mention of a library entry: its name as a link to the entry.
    static func mention(libraryEntry entry: LibraryEntry) -> AttributedString {
        var text = AttributedString(entry.name)
        text.link = url(forLibraryKey: entry.key)
        return text
    }

    static func url(for pageID: UUID) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = "/" + pageID.uuidString
        guard let url = components.url else {
            fatalError("A scheme, host and UUID path always make a valid URL")
        }
        return url
    }

    /// The page a mention URL points at, or nil if it isn't a mention URL.
    static func pageID(from url: URL) -> UUID? {
        guard url.scheme == scheme, url.host == host else { return nil }
        return UUID(uuidString: url.lastPathComponent)
    }

    /// The text to show for a page.
    static func displayTitle(of title: String) -> String {
        title.isEmpty ? String(localized: "Untitled") : title
    }

    /// The pages mentioned in the notes, in order of first appearance, without repeats.
    static func mentionedIDs(in body: AttributedString) -> [UUID] {
        var seen = Set<UUID>()
        var ordered: [UUID] = []
        for run in body.runs {
            if let url = run.link, let id = pageID(from: url), seen.insert(id).inserted {
                ordered.append(id)
            }
        }
        return ordered
    }

    /// A mention: the title as a link to the page.
    static func mention(title: String, pageID: UUID) -> AttributedString {
        var text = AttributedString(displayTitle(of: title))
        text.link = url(for: pageID)
        return text
    }

    // MARK: Typing "@"

    /// The `@` and the text typed after it, up to the cursor.
    struct Query: Equatable {
        /// Character offsets covering the `@` through the cursor.
        var range: Range<Int>
        /// What was typed after the `@`.
        var text: String
    }

    /// Finds an `@` just before the cursor that starts a mention being typed.
    ///
    /// The `@` has to start the text or follow whitespace or an opening bracket, so email addresses don't
    /// count. The query may contain spaces, because page titles do, but it stops at a line break and is
    /// limited in length so a stray `@` far back in a paragraph doesn't keep suggestions open.
    static func activeQuery(in text: String, cursor: Int, maxLength: Int = 40) -> Query? {
        let characters = Array(text)
        guard cursor >= 0, cursor <= characters.count else { return nil }

        var index = cursor - 1
        let earliest = max(0, cursor - maxLength - 1)
        while index >= earliest {
            let character = characters[index]
            if character == "\n" { return nil }
            if character == "@" {
                if index > 0 {
                    let before = characters[index - 1]
                    guard before.isWhitespace || before == "(" else { return nil }
                }
                let query = String(characters[(index + 1)..<cursor])
                if query.first == " " { return nil }
                return Query(range: index..<cursor, text: query)
            }
            index -= 1
        }
        return nil
    }

    // MARK: Editing the notes

    /// Replaces `range` (character offsets) with a mention followed by a space, and puts the cursor after it.
    /// With no range, the current selection is replaced, or the mention is inserted at the cursor.
    static func insertMention(
        of pageID: UUID,
        title: String,
        replacing range: Range<Int>?,
        in body: inout AttributedString,
        selection: inout AttributedTextSelection
    ) {
        insert(mention(title: title, pageID: pageID), replacing: range, in: &body, selection: &selection)
    }

    /// Inserts a mention of a library entry, the same way as a mention of a page.
    static func insertMention(
        ofLibraryEntry entry: LibraryEntry,
        replacing range: Range<Int>?,
        in body: inout AttributedString,
        selection: inout AttributedTextSelection
    ) {
        insert(mention(libraryEntry: entry), replacing: range, in: &body, selection: &selection)
    }

    private static func insert(
        _ mentionText: AttributedString,
        replacing range: Range<Int>?,
        in body: inout AttributedString,
        selection: inout AttributedTextSelection
    ) {
        if let range {
            let characters = body.characters
            guard let lower = characters.index(characters.startIndex, offsetBy: range.lowerBound, limitedBy: characters.endIndex),
                  let upper = characters.index(characters.startIndex, offsetBy: range.upperBound, limitedBy: characters.endIndex)
            else { return }
            selection = AttributedTextSelection(range: lower..<upper)
        }
        let start = startOffset(of: selection, in: body)

        var content = mentionText
        // The space has no link, so what's typed next isn't part of the mention.
        content.append(AttributedString(" "))
        body.replaceSelection(&selection, with: content)

        // Replacing a range leaves the new text selected, so the next key would replace the mention.
        // Put the cursor after it instead.
        let end = start + content.characters.count
        if let caret = body.characters.index(body.startIndex, offsetBy: end, limitedBy: body.characters.endIndex) {
            selection = AttributedTextSelection(insertionPoint: caret)
        }
    }

    /// Where a selection begins, as a character offset.
    private static func startOffset(of selection: AttributedTextSelection, in body: AttributedString) -> Int {
        let characters = body.characters
        switch selection.indices(in: body) {
        case .insertionPoint(let index):
            return characters.distance(from: characters.startIndex, to: index)
        case .ranges(let ranges):
            guard let first = ranges.ranges.first else { return characters.count }
            return characters.distance(from: characters.startIndex, to: first.lowerBound)
        @unknown default:
            return characters.count
        }
    }

    // MARK: Treating a mention as one block

    /// The result of tidying up notes after an edit.
    struct Normalization: Equatable {
        var body: AttributedString
        /// Where the cursor belongs if a mention was removed, as a character offset.
        var caret: Int?
    }

    /// Makes mentions behave as single blocks after the notes were edited from `old` to `new`.
    ///
    /// The text editor treats a link as ordinary text, so left alone, typing next to a mention would extend
    /// the link and Delete would remove one letter of it. For each mention that no longer matches its text
    /// before the edit:
    /// - **Part of it was deleted:** the rest is deleted too, so the mention goes as one block.
    /// - **Text was typed against it** (before or after): that text loses the link and the mention is intact.
    /// - **Text was typed inside it:** the whole thing becomes plain text, keeping what was typed.
    ///
    /// A mention that is new in `new`, or unchanged, is left alone.
    static func normalize(old: AttributedString, new: AttributedString) -> Normalization {
        var expected: [MentionTarget: String] = [:]
        for group in mentionGroups(in: old) where expected[group.target] == nil {
            expected[group.target] = group.text
        }

        var body = new
        var caret: Int?
        // Work from the end so the offsets of earlier mentions stay valid as the text changes.
        for group in mentionGroups(in: new).reversed() {
            let title = expected[group.target] ?? group.text
            guard group.text != title else { continue }

            let characters = body.characters
            func index(_ offset: Int) -> AttributedString.Index {
                characters.index(characters.startIndex, offsetBy: offset)
            }

            if group.text.count < title.count {
                body.removeSubrange(index(group.range.lowerBound)..<index(group.range.upperBound))
                caret = group.range.lowerBound
            } else if group.text.count > title.count, group.text.hasPrefix(title) {
                body[index(group.range.lowerBound + title.count)..<index(group.range.upperBound)].link = nil
            } else if group.text.count > title.count, group.text.hasSuffix(title) {
                body[index(group.range.lowerBound)..<index(group.range.upperBound - title.count)].link = nil
            } else {
                body[index(group.range.lowerBound)..<index(group.range.upperBound)].link = nil
            }
        }
        return Normalization(body: body, caret: caret)
    }

    /// One mention in the text. A mention formatted in several runs (part of it bold, say) is one group.
    private struct MentionGroup {
        var target: MentionTarget
        /// Character offsets.
        var range: Range<Int>
        var text: String
    }

    private static func mentionGroups(in body: AttributedString) -> [MentionGroup] {
        var groups: [MentionGroup] = []
        var offset = 0
        for run in body.runs {
            let text = String(body[run.range].characters)
            let length = text.count
            if let url = run.link, let target = target(from: url) {
                if let last = groups.last, last.target == target, last.range.upperBound == offset {
                    groups[groups.count - 1].range = last.range.lowerBound..<(offset + length)
                    groups[groups.count - 1].text += text
                } else {
                    groups.append(MentionGroup(target: target, range: offset..<(offset + length), text: text))
                }
            }
            offset += length
        }
        return groups
    }

    /// Updates the visible text of mentions to match current titles, keeping each mention's formatting.
    /// A mention may be several runs if part of it is formatted differently, so runs for the same page that
    /// sit side by side are treated as one.
    static func refreshTitles(in body: inout AttributedString, titles: [UUID: String]) {
        var result = AttributedString()
        var pending: (target: MentionTarget, attributes: AttributeContainer, text: AttributedString)?

        func flush() {
            guard let group = pending else { return }
            let current = String(group.text.characters)
            if case .page(let id) = group.target, let title = titles[id], title != current {
                result.append(AttributedString(title, attributes: group.attributes))
            } else {
                result.append(group.text)
            }
            pending = nil
        }

        for run in body.runs {
            let piece = AttributedString(body[run.range])
            if let url = run.link, let target = target(from: url) {
                if pending?.target == target {
                    pending?.text.append(piece)
                } else {
                    flush()
                    pending = (target, run.attributes, piece)
                }
            } else {
                flush()
                result.append(piece)
            }
        }
        flush()
        if result != body {
            body = result
        }
    }

    /// Turns mentions of the given pages back into plain text, keeping the words.
    static func stripMentions(of ids: Set<UUID>, from body: inout AttributedString) {
        for run in body.runs {
            if let url = run.link, let id = pageID(from: url), ids.contains(id) {
                body[run.range].link = nil
            }
        }
    }

    /// Points mentions at new page IDs, as when a world is imported. A mention of a page that isn't in the
    /// map becomes plain text.
    static func remapMentions(in body: inout AttributedString, using map: [UUID: UUID]) {
        for run in body.runs {
            guard let url = run.link, let id = pageID(from: url) else { continue }
            body[run.range].link = map[id].map(Mention.url(for:))
        }
    }
}
