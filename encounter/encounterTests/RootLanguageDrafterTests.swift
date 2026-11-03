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
