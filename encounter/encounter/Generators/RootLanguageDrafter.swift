//
//  RootLanguageDrafter.swift
//  encounter
//

import Foundation
import FoundationModels

// A prototype, not yet used by the app: asks the on-device model to draft a root language from a description of a realm, and to
// suggest descriptions of realms. See "AI-assisted naming" in PLAN.md for what it is meant to find out.

/// What the model gives for the parts of place names. The counts are asked for exactly so the language is long enough to use.
@Generable
struct DraftedPlaceParts {
    @Guide(description: "Syllables or words that begin the name of a town", .count(24))
    var townStarts: [String]
    @Guide(description: "Endings that finish the name of a town, such as a suffix", .count(14))
    var townEnds: [String]
    @Guide(description: "Words that begin the name of a realm", .count(12))
    var realmStarts: [String]
    @Guide(description: "Endings that finish the name of a realm", .count(10))
    var realmEnds: [String]
}

/// People's names and river names.
@Generable
struct DraftedPersonAndRiverNames {
    @Guide(description: "Family names of ordinary people", .count(30))
    var familyNames: [String]
    @Guide(description: "Names of rivers, without the word river", .count(14))
    var riverNames: [String]
}

@Generable
enum DraftedModifierPosition: String {
    case before
    case after
}

/// How the language puts a describing word and the thing it describes, and a title and a summary for the language.
@Generable
struct DraftedCharacter {
    @Guide(description: "A short name for the language, such as 'Elvish'")
    var title: String
    @Guide(description: "One sentence on what the language sounds like and where its names come from")
    var summary: String
    @Guide(description: "Whether a describing word usually comes before the word it describes, or after it")
    var describingWord: DraftedModifierPosition
}

/// The words for the concepts of one group, in the order they were asked for.
@Generable
struct DraftedWords {
    @Guide(description: "One bare word for each concept, in the same order, with no article and no explanation")
    var words: [String]
}

/// Descriptions of realms for a world.
@Generable
struct DraftedRealmDescriptions {
    @Guide(description: "One description for each realm, each from a different real-world or fictional culture", .minimumCount(1), .maximumCount(8))
    var realms: [DraftedRealm]
}

@Generable
struct DraftedRealm {
    @Guide(description: "Exactly two complete sentences on the realm's people, land and character. Never give the realm, a place or a person a name: say 'the realm' or 'its people'")
    var description: String
}

/// Everything a draft asked of the model, before it is checked and turned into a language. Kept apart from the model so it can be
/// tested without one.
nonisolated struct RootLanguageDraft: Sendable {
    var title: String
    var summary: String
    var modifierPosition: RootLanguage.ModifierPosition
    var owners: [String]
    var rivers: [String]
    var townStarts: [String]
    var townEnds: [String]
    var realmStarts: [String]
    var realmEnds: [String]
    /// The words returned for each group, in the order of the group's concepts. A group whose count didn't match is left out.
    var words: [String: [String]]

    /// A usable language from the draft, with English words wherever the model gave none, and a list of what had to be borrowed.
    func language(id: String) -> (language: RootLanguage, borrowed: [String]) {
        var borrowed: [String] = []
        var wordsByGroup: [String: [String: String]] = [:]
        for (group, concepts) in RootLanguages.concepts.sorted(by: { $0.key < $1.key }) {
            let given = Self.clean(words[group] ?? [], keepDuplicates: true)
            if given.count == concepts.count, !given.contains(where: \.isEmpty) {
                wordsByGroup[group] = Dictionary(uniqueKeysWithValues: zip(concepts, given))
            } else {
                wordsByGroup[group] = RootLanguages.english.words[group] ?? [:]
                borrowed.append(group)
            }
        }
        let owners = Self.clean(self.owners)
        let names: [String: [String]] = [
            "shopOwner": owners, "manorOwner": owners, "landmarkOwner": owners,
            "riverName": Self.clean(rivers), "placeStart": Self.clean(townStarts), "placeEnd": Self.clean(townEnds),
            "realmStart": Self.clean(realmStarts), "realmEnd": Self.clean(realmEnds),
        ]
        let language = RootLanguage(
            id: id, title: title, summary: summary, modifierPosition: modifierPosition, words: wordsByGroup, names: names
        )
        return (language, borrowed)
    }

    /// Trimmed, with empty entries and (unless kept) repeats dropped.
    static func clean(_ list: [String], keepDuplicates: Bool = false) -> [String] {
        var seen = Set<String>()
        return list.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { word in
            if keepDuplicates { return true }
            return !word.isEmpty && seen.insert(word.lowercased()).inserted
        }
    }
}

/// Drafts root languages and realm descriptions with the on-device model.
enum RootLanguageDrafter {
    enum Availability: Equatable {
        case available
        /// Why not, in words for the user.
        case unavailable(String)
    }

    static var availability: Availability {
        switch SystemLanguageModel.default.availability {
        case .available: return .available
        case .unavailable(.deviceNotEligible): return .unavailable("This device can't run Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled): return .unavailable("Apple Intelligence is turned off.")
        case .unavailable(.modelNotReady): return .unavailable("The on-device model is still getting ready.")
        case .unavailable: return .unavailable("The on-device model isn't available.")
        }
    }

    /// Several short sessions, as the model's whole context is 4,096 tokens and a language is far more than that.
    static func draft(from description: String, progress: (@Sendable (String) -> Void)? = nil) async throws -> RootLanguageDraft {
        let role = """
            You invent names for a fantasy world. The names must sound like this: \(description)
            Give only the names or words asked for. Never explain.
            """
        progress?("character")
        let character = try await LanguageModelSession(instructions: role)
            .respond(to: "Describe the language that the names of this place come from.", generating: DraftedCharacter.self).content
        progress?("place parts")
        let parts = try await LanguageModelSession(instructions: role)
            .respond(to: "Give the parts that town names and realm names are built from.", generating: DraftedPlaceParts.self).content
        progress?("people and rivers")
        let people = try await LanguageModelSession(instructions: role)
            .respond(to: "Give family names and river names.", generating: DraftedPersonAndRiverNames.self).content

        var words: [String: [String]] = [:]
        for (group, concepts) in RootLanguages.concepts.sorted(by: { $0.key < $1.key }) {
            progress?(group)
            let english = RootLanguages.english.words[group] ?? [:]
            let list = concepts.map { "\(english[$0] ?? $0)" }.joined(separator: ", ")
            let prompt = "Give the word in this language for each of these, in order, \(concepts.count) words: \(list)"
            words[group] = try await LanguageModelSession(instructions: role)
                .respond(to: prompt, generating: DraftedWords.self).content.words
        }
        return RootLanguageDraft(
            title: character.title, summary: character.summary,
            modifierPosition: character.describingWord == .before ? .before : .after,
            owners: people.familyNames, rivers: people.riverNames,
            townStarts: parts.townStarts, townEnds: parts.townEnds, realmStarts: parts.realmStarts, realmEnds: parts.realmEnds,
            words: words
        )
    }

    /// Descriptions for a number of realms, each from a different inspiration. `hint` is the user's idea of the world, if any.
    static func realmDescriptions(count: Int, hint: String = "", cultures: [String] = []) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
            You help a game master design a fantasy world. Be concrete and brief. Never invent names for realms, places or people: \
            the game gives them names, so refer to 'the realm' and 'its people'.
            """)
        let theme = hint.isEmpty ? "" : " The world is: \(hint)."
        // A realm whose languages have been chosen draws on the cultures those languages come from; the others are left to the model.
        let steer = cultures.enumerated().compactMap { index, culture -> String? in
            culture.isEmpty ? nil : "Realm \(index + 1) draws on \(culture) culture."
        }.joined(separator: " ")
        let prompt = "Describe \(count) realms for a fantasy world, in order.\(theme) \(steer) Any other realm takes inspiration from a culture of its own, real or from fiction. Do not use the names of real countries."
        let made = try await session.respond(to: prompt, generating: DraftedRealmDescriptions.self).content.realms
        return Array(made.map { $0.description.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.prefix(count))
    }
}
