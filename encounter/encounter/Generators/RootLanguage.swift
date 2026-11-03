//
//  RootLanguage.swift
//  encounter
//

import Foundation

/// A root language: where the proper names of a place come from. It gives the words that are part of a name (Mill, Golden, Stag,
/// Iron, the points of the compass), people's names, and the parts that place names are made of. It never gives the plain words
/// that say what a thing is (Street, Road, Bakery, Chapel): those belong to the user's language, in `NameTerms`.
///
/// A language is data, in `Content/naming.json`, so more can be added without changing the generators. Its words are bare: no
/// articles, no agreement, each in the form it takes inside a name.
nonisolated struct RootLanguage: Codable, Identifiable, Hashable, Sendable {
    /// Whether a word that qualifies another comes before it (English: "Golden Stag") or after it ("Cervo Oro").
    enum ModifierPosition: String, Codable, Sendable {
        case before, after
    }

    var id: String
    var title: String
    var summary: String
    var modifierPosition: ModifierPosition
    /// The word for each concept, by group (such as "street" or "innNoun") and then concept (such as "mill"). A language may
    /// leave a concept out, and it is then never used.
    var words: [String: [String: String]]
    /// Lists of names: owners of shops and manors, rivers, the starts and ends of place names, realms.
    var names: [String: [String]]

    /// The lists of names every language must have, and the fewest each needs.
    static let requiredNames = ["shopOwner", "riverName", "manorOwner", "landmarkOwner", "placeStart", "placeEnd", "realmName"]
    static let fewestWords = 5
    static let fewestNames = 8

    /// The words a language has for a group, in the standard order of the concepts. Order matters: it is what a seed picks from.
    func words(_ group: String) -> [String] {
        (RootLanguages.concepts[group] ?? []).compactMap { words[group]?[$0] }
    }

    /// What is wrong with the language, in words for its author. Empty if it can be used.
    var problems: [String] {
        var found: [String] = []
        if title.isEmpty || summary.isEmpty { found.append("\(id): needs a title and a summary.") }
        for (group, concepts) in RootLanguages.concepts {
            let given = words[group] ?? [:]
            for concept in given.keys where !concepts.contains(concept) { found.append("\(id): “\(concept)” is not a concept of \(group).") }
            for (concept, word) in given where word.trimmingCharacters(in: .whitespaces).isEmpty { found.append("\(id): \(group) \(concept) is empty.") }
            let needed = group == "compass" ? 8 : group == "gate" ? 1 : Self.fewestWords
            if words(group).count < needed { found.append("\(id): \(group) needs at least \(needed) words, and has \(words(group).count).") }
        }
        for group in words.keys where RootLanguages.concepts[group] == nil { found.append("\(id): “\(group)” is not a group of words.") }
        for key in Self.requiredNames where (names[key] ?? []).count < Self.fewestNames {
            found.append("\(id): \(key) needs at least \(Self.fewestNames) names.")
        }
        return found
    }
}

/// The root languages that ship with the app, read from `Content/naming.json` the first time they are needed.
nonisolated enum RootLanguages {
    private struct File: Decodable {
        var formatVersion: Int
        var concepts: [String: [String]]
        var languages: [RootLanguage]
    }

    /// The highest `formatVersion` this app can read.
    static let supportedFormatVersion = 2

    private final class BundleToken {}

    private static let file: File? = {
        guard let url = Bundle(for: BundleToken.self).url(forResource: "naming", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data), file.formatVersion <= supportedFormatVersion
        else { return nil }
        return file
    }()

    /// The concepts of each group, in order. Every language's words are for these.
    static let concepts: [String: [String]] = file?.concepts ?? [:]

    static let all: [RootLanguage] = (file?.languages ?? []).filter { $0.problems.isEmpty }

    static let englishID = "english"

    /// Names a language used before they were called by what they are, so a map saved under the old name still opens.
    private static let aliases = ["italian": "romance", "german": "germanic", "welsh": "celtic"]

    /// A language with nothing in it, used only if the file couldn't be read.
    private static let empty = RootLanguage(id: englishID, title: "English", summary: "", modifierPosition: .before, words: [:], names: [:])

    /// English, from which a language that lacks something borrows it.
    static let english: RootLanguage = all.first { $0.id == englishID } ?? empty

    static func aliasedID(_ id: String) -> String { aliases[id] ?? id }

    /// The language with the id, or English if there isn't one.
    static func language(_ id: String) -> RootLanguage {
        let id = aliases[id] ?? id
        return all.first { $0.id == id } ?? english
    }
}

/// How much of a place's names come from one root language, compared with the others it is mixed with.
nonisolated struct LanguageWeight: Codable, Equatable, Hashable, Sendable {
    var id: String
    var weight: Int
}

extension RootLanguages {
    /// The languages and weights as they are used: unknown ids dropped, nothing left giving English.
    static func mix(_ weights: [LanguageWeight]) -> [(language: RootLanguage, weight: Double)] {
        let known = weights.filter { $0.weight > 0 }.map { (language(aliasedID($0.id)), Double($0.weight)) }
        return known.isEmpty ? [(english, 1)] : known
    }
}
