//
//  WorldSearch.swift
//  encounter
//

import Foundation
import SwiftData

/// What a search covers.
enum SearchScope: Hashable {
    case all
    case kind(PageKind)
    /// Library entries only.
    case library
}

/// Where in a page or entry a search matched, best first.
enum SearchField: Int, Comparable {
    case title, tag, summary, notes

    static func < (lhs: SearchField, rhs: SearchField) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// One search result: a page in the world or an entry in the content library, with why it matched.
struct SearchHit: Identifiable {
    enum Target {
        case page(Page)
        case library(LibraryEntry)
    }

    let target: Target
    let score: Int
    let field: SearchField
    /// A line of the text that matched, for results that didn't match on the title.
    let snippet: String?

    var id: String {
        switch target {
        case .page(let page): "page/\(page.id.uuidString)"
        case .library(let entry): "library/\(entry.key)"
        }
    }

    var title: String {
        switch target {
        case .page(let page): page.title
        case .library(let entry): entry.name
        }
    }
}

/// Searches a world's pages, and its edition's library entries, for what the user typed.
///
/// A result must contain every word typed, each in the title, tags, summary or notes. Words match anywhere
/// in a word and ignore case and accents. Results are ranked by how good the best match is: a title that is
/// the search, then a title that starts with it, then one that contains it, then tags, summary and notes.
enum WorldSearch {
    static let pageLimit = 100
    static let libraryLimit = 50

    @MainActor
    static func search(
        _ query: String,
        in world: World,
        scope: SearchScope = .all,
        context: ModelContext
    ) -> [SearchHit] {
        let words = words(in: query)
        guard !words.isEmpty else { return [] }

        var hits: [SearchHit] = []
        if scope != .library {
            hits += pageHits(words: words, phrase: words.joined(separator: " "), in: world, scope: scope, context: context)
        }
        if scope == .all || scope == .library, world.rules.contains(.library) {
            hits += libraryHits(words: words, phrase: words.joined(separator: " "), edition: world.edition)
        }
        return hits.sorted {
            ($1.score, $0.title.localizedLowercase) < ($0.score, $1.title.localizedLowercase)
        }
    }

    // MARK: Pages

    @MainActor
    private static func pageHits(words: [String], phrase: String, in world: World, scope: SearchScope, context: ModelContext) -> [SearchHit] {
        // The database narrows things down using the longest word. Everything else is checked afterwards.
        let anchor = words.max { $0.count < $1.count } ?? ""
        let worldID = world.id
        var descriptor = FetchDescriptor<Page>(predicate: #Predicate<Page> {
            $0.world?.id == worldID
                && ($0.title.localizedStandardContains(anchor)
                    || $0.summary.localizedStandardContains(anchor)
                    || $0.bodyText.localizedStandardContains(anchor))
        })
        descriptor.sortBy = [SortDescriptor(\.title)]
        var pages = (try? context.fetch(descriptor)) ?? []

        // Tags are a list, so they are matched here. Pages found by their tags join the rest.
        let found = Set(pages.map(\.id))
        let tagged = ((world.pages ?? []).filter { page in
            !found.contains(page.id) && page.tags.contains { contains($0, anchor) }
        })
        pages += tagged

        var hits: [SearchHit] = []
        for page in pages {
            if case .kind(let kind) = scope, page.kind != kind { continue }
            guard let match = match(
                words: words, phrase: phrase,
                title: page.title, tags: page.tags, summary: page.summary, notes: page.bodyText
            ) else { continue }
            hits.append(SearchHit(target: .page(page), score: match.score, field: match.field, snippet: match.snippet))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(pageLimit))
    }

    // MARK: Library

    private static func libraryHits(words: [String], phrase: String, edition: LibraryEdition) -> [SearchHit] {
        var hits: [SearchHit] = []
        for entry in Library.shared.allEntries(in: edition) {
            // Library entries match on their name and summary. Their full text isn't searched.
            guard let match = match(
                words: words, phrase: phrase,
                title: entry.name, tags: [], summary: entry.summary, notes: ""
            ) else { continue }
            hits.append(SearchHit(target: .library(entry), score: match.score, field: match.field, snippet: match.snippet))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(libraryLimit))
    }

    // MARK: Matching

    struct Match: Equatable {
        let score: Int
        let field: SearchField
        let snippet: String?
    }

    /// How well some text fields answer a search, or nil if any word is missing from all of them.
    static func match(words: [String], phrase: String, title: String, tags: [String], summary: String, notes: String) -> Match? {
        // Every word has to appear somewhere.
        for word in words where !(contains(title, word) || tags.contains { contains($0, word) } || contains(summary, word) || contains(notes, word)) {
            return nil
        }

        // Title: the whole search, then a start, then a word start, then anywhere.
        if contains(title, phrase) {
            if normalised(title) == normalised(phrase) { return Match(score: 1000, field: .title, snippet: nil) }
            if hasPrefix(title, phrase) { return Match(score: 900, field: .title, snippet: nil) }
            if startsAWord(title, phrase) { return Match(score: 800, field: .title, snippet: nil) }
            return Match(score: 700, field: .title, snippet: nil)
        }
        if words.allSatisfy({ contains(title, $0) }) { return Match(score: 600, field: .title, snippet: nil) }

        if let tag = tags.first(where: { tag in words.allSatisfy { contains(tag, $0) } }) {
            return Match(score: normalised(tag) == normalised(phrase) ? 500 : 400, field: .tag, snippet: tag)
        }
        if words.allSatisfy({ contains(summary, $0) }) {
            return Match(score: 300, field: .summary, snippet: snippet(in: summary, around: words[0]))
        }
        if words.allSatisfy({ contains(notes, $0) }) {
            return Match(score: 200, field: .notes, snippet: snippet(in: notes, around: words[0]))
        }
        // The words are spread across different fields.
        let field: SearchField = words.contains { contains(notes, $0) } ? .notes : .summary
        return Match(score: 100, field: field, snippet: nil)
    }

    static func words(in query: String) -> [String] {
        query.split(whereSeparator: \.isWhitespace).map(String.init)
    }

    private static let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: options) != nil
    }

    private static func hasPrefix(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: options.union(.anchored)) != nil
    }

    private static func startsAWord(_ text: String, _ word: String) -> Bool {
        var searchRange = text.startIndex..<text.endIndex
        while let found = text.range(of: word, options: options, range: searchRange) {
            if found.lowerBound == text.startIndex || !text[text.index(before: found.lowerBound)].isLetter { return true }
            searchRange = found.upperBound..<text.endIndex
        }
        return false
    }

    private static func normalised(_ text: String) -> String {
        text.folding(options: options, locale: nil).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// About a line of `text` around the first place `word` appears.
    static func snippet(in text: String, around word: String, radius: Int = 50) -> String? {
        guard let found = text.range(of: word, options: options) else { return nil }
        let start = text.index(found.lowerBound, offsetBy: -radius, limitedBy: text.startIndex) ?? text.startIndex
        let end = text.index(found.upperBound, offsetBy: radius, limitedBy: text.endIndex) ?? text.endIndex
        var line = String(text[start..<end]).replacingOccurrences(of: "\n", with: " ")
        if start > text.startIndex { line = "…" + line }
        if end < text.endIndex { line += "…" }
        return line
    }
}
