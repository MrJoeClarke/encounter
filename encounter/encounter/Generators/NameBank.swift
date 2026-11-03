//
//  NameBank.swift
//  encounter
//

import Foundation

/// Names for what a generator makes: streets, quarters, inns, shops and chapels. Built from a `NamingStyle` with a seeded
/// random source, so the same seed gives the same names, and kept unique within one map.
nonisolated struct NameBank: Sendable {
    private var used: Set<String> = []
    private let style: NamingStyle

    init(style: NamingStyle = NamingStyles.english) {
        self.style = style
    }

    // MARK: Building names from the style

    /// A name from the pattern for a kind, with each `{word}` filled from its list (or from `preset`). A kind with one pattern
    /// uses it without drawing, so adding patterns to a style never changes what a style with one pattern gives.
    private func fill(_ kind: String, using random: inout SeededRandom, preset: [String: String] = [:]) -> String {
        Self.fill(style, kind, using: &random, preset: preset)
    }

    private static func fill(_ style: NamingStyle, _ kind: String, using random: inout SeededRandom, preset: [String: String] = [:]) -> String {
        let options = style.patterns[kind] ?? NamingStyles.english.patterns[kind] ?? []
        guard let pattern = options.count == 1 ? options.first : options.randomElement(using: &random) else { return kind }
        var result = ""
        var rest = pattern[...]
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            result += rest[..<open]
            let name = String(rest[rest.index(after: open)..<close])
            result += preset[name] ?? Self.word(style, name, using: &random)
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    private func word(_ list: String, using random: inout SeededRandom) -> String {
        Self.word(style, list, using: &random)
    }

    private static func word(_ style: NamingStyle, _ list: String, using random: inout SeededRandom) -> String {
        (style.lists[list] ?? NamingStyles.english.lists[list] ?? []).randomElement(using: &random) ?? ""
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

    // MARK: A settlement

    mutating func street(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "street", using: &random) }
    }

    mutating func quarter(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "quarter", using: &random) }
    }

    mutating func inn(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "inn", using: &random) }
    }

    mutating func forge(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "forge", using: &random) }
    }

    /// A shop and what it sells, such as ("Marsh’s Bakery", "A bakery").
    mutating func shop(using random: inout SeededRandom) -> (name: String, summary: String) {
        let trades = style.trades.isEmpty ? NamingStyles.english.trades : style.trades
        guard let trade = trades.randomElement(using: &random) else { return (named("Shop"), "A shop") }
        let style = self.style
        let name = unique { Self.fill(style, "shop", using: &random, preset: ["shop": trade.shop]) }
        return (name, trade.summary)
    }

    mutating func chapel(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "chapel", using: &random) }
    }

    mutating func named(_ base: String) -> String { unique { base } }

    /// The name of the road that leaves a gate, and of the road and the gate itself, for the direction (0 is east, turning
    /// anticlockwise in eighths).
    mutating func gateRoad(direction: Int) -> String { named(compassName("gateRoad", direction)) }
    mutating func road(direction: Int) -> String { named(compassName("road", direction)) }
    mutating func gate(direction: Int) -> String { named(compassName("gate", direction)) }

    private func compassName(_ kind: String, _ direction: Int) -> String {
        var unused = SeededRandom(seed: 0)
        let words = style.lists["compass"] ?? NamingStyles.english.lists["compass"] ?? []
        return fill(kind, using: &unused, preset: ["compass": words.indices.contains(((direction % 8) + 8) % 8) ? words[((direction % 8) + 8) % 8] : ""])
    }

    /// "Market Square", or what the style calls it.
    mutating func marketSquare(inScene: Bool = false) -> String {
        var random = SeededRandom(seed: 0)
        let kind = inScene && style.patterns["marketSquare.scene"] != nil ? "marketSquare.scene" : "marketSquare"
        return named(fill(kind, using: &random))
    }
}

extension NameBank {
    /// A name for a river, such as "River Hale".
    mutating func river(using random: inout SeededRandom) -> String {
        named(fill("river", using: &random))
    }

    mutating func manor(using random: inout SeededRandom) -> String {
        named(fill("manor", using: &random))
    }

    /// A name for a landmark of a kind, such as "Cathedral of Mercy" or "Hale Keep".
    mutating func landmark(_ kind: Landmark, using random: inout SeededRandom) -> String {
        // The same three words are drawn whatever the kind, so the names of a seed don't depend on which landmarks are chosen.
        let surname = word("landmarkSurname", using: &random)
        let adjective = word("landmarkAdjective", using: &random)
        let virtue = word("landmarkVirtue", using: &random)
        var unused = SeededRandom(seed: 0)
        return named(fill("landmark.\(kind.rawValue)", using: &unused, preset: ["surname": surname, "adjective": adjective, "virtue": virtue]))
    }
}

extension NameBank {
    /// A name for a city, town or village, such as "Aldford" or "Thornbury".
    mutating func settlement(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "settlement", using: &random) }
    }

    /// A name for a realm, such as "Kingdom of Carrow".
    mutating func realm(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "realm", using: &random) }
    }

    mutating func forest(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "forest", using: &random) }
    }

    mutating func mountains(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "mountains", using: &random) }
    }

    mutating func sea(using random: inout SeededRandom) -> String {
        let style = self.style
        return unique { Self.fill(style, "sea", using: &random) }
    }
}
