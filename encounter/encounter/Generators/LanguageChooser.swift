//
//  LanguageChooser.swift
//  encounter
//

import Foundation
import FoundationModels

/// Reads a description of a realm ("inspired by eastern Europe", "dwarvish names after Tolkien") and says which of the root languages
/// that ships with the app it draws on, and how much of each. Uses the on-device model, so it is optional: where there isn't one the
/// caller keeps whatever languages were chosen by hand.
enum LanguageChooser {
    /// The most languages one description is allowed to draw on.
    static let mostLanguages = 3

    /// The weights from the pairs of (language, share) the model gave: unknown languages and repeats dropped, shares kept within
    /// 1 to 100, the biggest shares first, and no more than `mostLanguages`. Nil if nothing usable is left.
    nonisolated static func weights(from pairs: [(id: String, share: Int)]) -> [LanguageWeight]? {
        var seen = Set<String>()
        var result: [LanguageWeight] = []
        for pair in pairs {
            let id = RootLanguages.aliasedID(pair.id.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
            guard RootLanguages.all.contains(where: { $0.id == id }), seen.insert(id).inserted else { continue }
            result.append(LanguageWeight(id: id, weight: min(max(pair.share, 1), 100)))
        }
        result.sort { $0.weight > $1.weight }
        return result.isEmpty ? nil : Array(result.prefix(mostLanguages))
    }

    /// The schema of the answer: a short list of a language (one of the shipped ids) and a share from 1 to 100.
    private static func schema() throws -> GenerationSchema {
        let language = DynamicGenerationSchema(
            name: "Language", description: "The id of one language", anyOf: RootLanguages.all.map(\.id)
        )
        let share = DynamicGenerationSchema(
            name: "Share",
            properties: [
                .init(name: "language", schema: DynamicGenerationSchema(referenceTo: "Language")),
                .init(name: "share", description: "How much of the names come from it, 1 to 100", schema: DynamicGenerationSchema(type: Int.self, guides: [.range(1...100)])),
            ]
        )
        let root = DynamicGenerationSchema(
            name: "Choice",
            properties: [.init(name: "languages", schema: DynamicGenerationSchema(arrayOf: DynamicGenerationSchema(referenceTo: "Share"), minimumElements: 1, maximumElements: mostLanguages))]
        )
        return try GenerationSchema(root: root, dependencies: [language, share])
    }

    /// The languages a description draws on, or nil if the model is unavailable, gives nothing usable, or declines.
    static func choose(for description: String) async -> [LanguageWeight]? {
        let text = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, RootLanguageDrafter.availability == .available else { return nil }
        let catalogue = RootLanguages.all.map { "\($0.id): \($0.summary)" }.joined(separator: "\n")
        let session = LanguageModelSession(instructions: """
            You help a game master pick the languages that the place names of a fantasy realm should sound like.
            Choose one to \(mostLanguages) from this list, using the ids only, and give each a share:
            \(catalogue)
            """)
        do {
            let schema = try schema()
            let response = try await session.respond(to: "The realm: \(text)", schema: schema)
            let items = try response.content.value([GeneratedContent].self, forProperty: "languages")
            let pairs = try items.map { item in
                (id: try item.value(String.self, forProperty: "language"), share: try item.value(Int.self, forProperty: "share"))
            }
            return weights(from: pairs)
        } catch {
            return nil
        }
    }
}
