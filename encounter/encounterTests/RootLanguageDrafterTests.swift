//
//  RootLanguageDrafterTests.swift
//  encounterTests
//

import Testing
import Foundation
@testable import encounter

struct RootLanguageDraftTests {
    /// A draft as the model might give it: every group the right length, and some names repeated or padded.
    private func draft(skipping skipped: Set<String> = [], wrongLength: Set<String> = []) -> RootLanguageDraft {
        var words: [String: [String]] = [:]
        for (group, concepts) in RootLanguages.concepts where !skipped.contains(group) {
            let made = concepts.indices.map { "w\($0)" }
            words[group] = wrongLength.contains(group) ? Array(made.dropLast()) : made
        }
        let list = (0..<20).map { "name\($0)" }
        return RootLanguageDraft(
            title: "Test", summary: "A test language.", modifierPosition: .after,
            owners: list + [" name1 ", ""], rivers: list, townStarts: list, townEnds: list, realmStarts: list, realmEnds: list, words: words
        )
    }

    @Test func aCompleteDraftBecomesAValidLanguage() {
        let made = draft().language(id: "test")
        #expect(made.language.problems.isEmpty, Comment(rawValue: "\(made.language.problems)"))
        #expect(made.borrowed.isEmpty && made.language.modifierPosition == .after)
        // Repeats, blanks and stray spaces are cleaned from the lists of names.
        #expect(made.language.names["shopOwner"]?.count == 20)
        #expect(made.language.words("street").first == "w0")
    }

    @Test func aGroupTheModelLeftOutOrGotWrongIsBorrowedFromEnglish() {
        let made = draft(skipping: ["gate"], wrongLength: ["street"]).language(id: "test")
        #expect(Set(made.borrowed) == ["gate", "street"])
        #expect(made.language.words("street") == RootLanguages.english.words("street"))
        #expect(made.language.problems.isEmpty)
    }

    @Test func aDraftedLanguageMakesNamesLikeAnyOther() {
        let language = draft().language(id: "test").language
        var bank = NameBank(language: language)
        var random = SeededRandom(seed: 2)
        let towns = (0..<10).map { _ in bank.settlement(using: &random) }
        #expect(towns.allSatisfy { $0.hasPrefix("name") })
        #expect(Set(towns).count == towns.count)
    }
}

/// Tries the real on-device model, when this machine has one and RUN_MODEL_TESTS is set (it takes over a minute), and prints what it
/// made so the quality can be judged. Skipped otherwise, so the whole suite stays fast and works on a machine without the model.
struct RootLanguageDrafterModelTests {
    static let canRun = ProcessInfo.processInfo.environment["RUN_MODEL_TESTS"] != nil && RootLanguageDrafter.availability == .available

    @Test(.enabled(if: RootLanguageDrafterModelTests.canRun), .timeLimit(.minutes(5)))
    func theModelDraftsALanguageFromADescription() async throws {
        let started = Date()
        let draft = try await RootLanguageDrafter.draft(from: "Eastern European, Slavic, with long vowels and soft consonants")
        let (language, borrowed) = draft.language(id: "draft")
        var bank = NameBank(language: language)
        var random = SeededRandom(seed: 5)
        print("DRAFT seconds:", Date().timeIntervalSince(started))
        print("DRAFT title:", language.title, "|", language.summary, "|", language.modifierPosition)
        print("DRAFT borrowed:", borrowed, "problems:", language.problems)
        print("DRAFT starts:", language.names["placeStart"] ?? [])
        print("DRAFT ends:", language.names["placeEnd"] ?? [])
        print("DRAFT realm parts:", language.names["realmStart"] ?? [], language.names["realmEnd"] ?? [])
        print("DRAFT owners:", language.names["shopOwner"] ?? [])
        for group in ["street", "innNoun", "innAdjective", "compass", "chapelVirtue"] { print("DRAFT \(group):", language.words(group)) }
        print("DRAFT towns:", (0..<8).map { _ in bank.settlement(using: &random) })
        print("DRAFT realms:", (0..<3).map { _ in bank.realm(using: &random) })
        print("DRAFT streets:", (0..<6).map { _ in bank.street(using: &random) })
        print("DRAFT inns:", (0..<4).map { _ in bank.inn(using: &random) })
    }

    @Test(.enabled(if: RootLanguageDrafterModelTests.canRun), .timeLimit(.minutes(2)))
    func theModelDescribesRealms() async throws {
        let started = Date()
        let realms = try await RootLanguageDrafter.realmDescriptions(count: 3, hint: "a grim land of mountains and old forests")
        print("REALMS seconds:", Date().timeIntervalSince(started))
        for realm in realms { print("REALMS:", realm) }
        #expect(realms.count == 3)
    }
}

struct LanguageChooserTests {
    @Test func theModelsAnswerIsCleanedIntoWeights() {
        let made = LanguageChooser.weights(from: [("Slavic", 70), ("nonsense", 90), ("germanic", 250), ("slavic", 10), ("welsh", 0), ("norse", 5), ("romance", 5)])
        // Unknown ids and repeats go, shares are kept within 1 to 100, the biggest first, and at most three remain.
        #expect(made == [LanguageWeight(id: "germanic", weight: 100), LanguageWeight(id: "slavic", weight: 70), LanguageWeight(id: "norse", weight: 5)])
    }

    @Test func nothingUsableGivesNoChoice() {
        #expect(LanguageChooser.weights(from: []) == nil)
        #expect(LanguageChooser.weights(from: [("klingon", 50)]) == nil)
    }

    @Test func descriptionsAndLanguagesAreKeptWithTheOptions() throws {
        var options = WorldOptions()
        options.setDescription("Cold mountain clans", forRealm: 1)
        options.setLanguages([LanguageWeight(id: "norse", weight: 80), LanguageWeight(id: "celtic", weight: 20)], forRealm: 1)
        #expect(options.description(forRealm: 0).isEmpty && options.description(forRealm: 1) == "Cold mountain clans")
        let back = try JSONDecoder().decode(WorldOptions.self, from: JSONEncoder().encode(options))
        #expect(back == options && back.languages(forRealm: 1).map(\.id) == ["norse", "celtic"])
        options.setLanguages([], forRealm: 1)
        #expect(options.languages(forRealm: 1).count == 2)
        #expect(try JSONDecoder().decode(WorldOptions.self, from: Data("{}".utf8)).realmDescriptions.isEmpty)
    }

    /// With the real model, on a machine that has one and RUN_MODEL_TESTS set: what a few descriptions give.
    @Test(.enabled(if: RootLanguageDrafterModelTests.canRun), .timeLimit(.minutes(3)))
    func theModelPicksSensibleLanguages() async {
        for text in ["Inspired by eastern Europe", "Welsh hill farmers and old stone circles", "Viking raiders of the frozen north", "A merchant republic like Renaissance Italy", "Dwarvish names after Tolkien"] {
            let started = Date()
            let mix = await LanguageChooser.choose(for: text)
            print("CHOICE \(text) ->", mix?.map { "\($0.id) \($0.weight)" } ?? ["nil"], Date().timeIntervalSince(started))
        }
    }
}
