//
//  NameBank.swift
//  encounter
//

import Foundation

/// Names for what a generator makes: streets, quarters, inns, shops, chapels, landmarks, towns and realms. The proper name comes
/// from a root language (`RootLanguage`) and the plain word that goes with it from the user's language (`NameTerms`). Picked with a
/// seeded random source, so the same seed gives the same names, and kept unique within one map.
nonisolated struct NameBank: Sendable {
    private var used: Set<String> = []
    private let language: RootLanguage

    init(language: RootLanguage = RootLanguages.english) {
        self.language = language
    }

    // MARK: Proper names

    private static func word(_ language: RootLanguage, _ group: String, using random: inout SeededRandom) -> String {
        language.words(group).randomElement(using: &random) ?? RootLanguages.english.words(group).randomElement(using: &random) ?? ""
    }

    private static func name(_ language: RootLanguage, _ list: String, using random: inout SeededRandom) -> String {
        (language.names[list] ?? RootLanguages.english.names[list] ?? []).randomElement(using: &random) ?? ""
    }

    /// Two words that make one name, in the order the language puts a qualifying word and what it qualifies.
    private static func compound(_ language: RootLanguage, modifier: String, noun: String) -> String {
        language.modifierPosition == .before ? "\(modifier) \(noun)" : "\(noun) \(modifier)"
    }

    private mutating func unique(_ make: () -> String) -> String {
        for _ in 0..<40 {
            let candidate = make()
            if used.insert(candidate).inserted { return candidate }
        }
        var n = 2
        let base = make()
        while !used.insert("\(base) \(n)").inserted { n += 1 }
        return "\(base) \(n)"
    }

    mutating func named(_ base: String) -> String { unique { base } }

    // MARK: A settlement

    mutating func street(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique {
            let name = Self.word(language, "street", using: &random)
            return (NameTerms.streetKinds.randomElement(using: &random) ?? NameTerms.streetKinds[0])(name)
        }
    }

    mutating func quarter(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { NameTerms.quarter(Self.word(language, "quarter", using: &random)) }
    }

    mutating func inn(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique {
            let adjective = Self.word(language, "innAdjective", using: &random)
            let noun = Self.word(language, "innNoun", using: &random)
            return NameTerms.inn(Self.compound(language, modifier: adjective, noun: noun))
        }
    }

    mutating func forge(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { NameTerms.forge(Self.name(language, "shopOwner", using: &random)) }
    }

    /// A shop and what it sells, such as ("Marsh’s Bakery", "A bakery").
    mutating func shop(using random: inout SeededRandom) -> (name: String, summary: String) {
        let language = self.language
        let trade = NameTerms.trades.randomElement(using: &random) ?? NameTerms.trades[0]
        let name = unique { trade.name(Self.name(language, "shopOwner", using: &random)) }
        return (name, trade.summary)
    }

    mutating func chapel(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { NameTerms.chapel(Self.word(language, "chapelVirtue", using: &random)) }
    }

    /// A name for a river, such as "River Hale".
    mutating func river(using random: inout SeededRandom) -> String {
        named(NameTerms.river(Self.name(language, "riverName", using: &random)))
    }

    mutating func manor(using random: inout SeededRandom) -> String {
        named(NameTerms.manor(Self.name(language, "manorOwner", using: &random)))
    }

    /// A name for a landmark of a kind, such as "Cathedral of Mercy" or "Hale Keep".
    mutating func landmark(_ kind: Landmark, using random: inout SeededRandom) -> String {
        // The same three are drawn whatever the kind, so the names of a seed don't depend on which landmarks are chosen.
        let owner = Self.name(language, "landmarkOwner", using: &random)
        let adjective = Self.word(language, "landmarkAdjective", using: &random)
        let virtue = Self.word(language, "landmarkVirtue", using: &random)
        return named(NameTerms.landmark(kind, owner: owner, adjective: adjective, virtue: virtue))
    }

    /// "Market Square".
    mutating func marketSquare(inScene: Bool = false) -> String {
        named(inScene ? NameTerms.marketSquareInScene : NameTerms.marketSquare)
    }

    // MARK: Gates and roads

    /// A point of the compass as a proper name, by direction (0 is east, turning anticlockwise in eighths; any whole number wraps).
    private func direction(_ index: Int) -> String {
        let words = language.words("compass")
        guard words.count == 8 else { return "" }
        return words[((index % 8) + 8) % 8]
    }

    /// The gate itself: "North Gate".
    mutating func gate(direction index: Int) -> String { named(NameTerms.gate(direction(index))) }

    /// The road that leaves a gate, named for the direction: "North Road".
    mutating func road(direction index: Int) -> String { named(NameTerms.road(direction(index))) }

    /// The road that leaves a gate, named for the gate: "North Gate Road". Gate is here part of the proper name.
    mutating func gateRoad(direction index: Int) -> String {
        let gate = language.words("gate").first ?? RootLanguages.english.words("gate").first ?? ""
        return named(NameTerms.road(Self.compound(language, modifier: direction(index), noun: gate)))
    }

    // MARK: A world

    /// A name for a city, town or village, such as "Aldford" or "Thornbury".
    mutating func settlement(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { Self.name(language, "placeStart", using: &random) + Self.name(language, "placeEnd", using: &random) }
    }

    /// A name for a realm, such as "Kingdom of Carrow".
    mutating func realm(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique {
            let title = NameTerms.realmTitles.randomElement(using: &random) ?? NameTerms.realmTitles[0]
            return title(Self.name(language, "realmName", using: &random))
        }
    }

    mutating func forest(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { NameTerms.forest(Self.word(language, "woodAdjective", using: &random)) }
    }

    mutating func mountains(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { NameTerms.mountains(Self.word(language, "peakAdjective", using: &random)) }
    }

    mutating func sea(using random: inout SeededRandom) -> String {
        let language = self.language
        return unique { NameTerms.sea(Self.word(language, "seaAdjective", using: &random)) }
    }
}
