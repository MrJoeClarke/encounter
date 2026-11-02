//
//  NameBank.swift
//  encounter
//

import Foundation

/// Names for what a generator makes: streets, quarters, inns, shops and chapels. Picked from short lists with a
/// seeded random source, so the same seed gives the same names, and kept unique within one map.
nonisolated struct NameBank: Sendable {
    private var used: Set<String> = []

    private static let streetStarts = ["Mill", "Bridge", "Market", "Church", "King’s", "Tanner’s", "Smith’s", "Baker’s", "Well", "Stone", "Oak", "Ash", "River", "High", "Low", "Old", "New", "Chapel", "Mason’s", "Weaver’s", "Fisher’s", "Cooper’s", "Rope", "Gate", "Hill", "Orchard", "Elm", "Briar", "Heron", "Lantern"]
    private static let streetEnds = ["Street", "Lane", "Row", "Way", "Walk", "Road", "Close"]
    private static let quarters = ["Old Quarter", "Craft Quarter", "Temple Quarter", "Merchant Quarter", "Garden Quarter", "Harbour Quarter", "Weavers’ Quarter", "Tanners’ Quarter", "Scholars’ Quarter", "Guild Quarter"]
    private static let innAdjectives = ["Gilded", "Rusty", "Laughing", "Sleeping", "Crooked", "Merry", "Silver", "Golden", "Drunken", "Wandering", "Black", "Red", "Broken", "Jolly"]
    private static let innNouns = ["Gull", "Stag", "Boar", "Lantern", "Anchor", "Crown", "Goose", "Barrel", "Raven", "Fox", "Wheel", "Plough", "Kettle", "Heron"]
    private static let surnames = ["Hale", "Marsh", "Thorne", "Wick", "Cobb", "Fenn", "Bram", "Locke", "Rudd", "Tarn", "Vane", "Yarrow", "Ames", "Dunn", "Pike", "Reeve", "Sorrel", "Whitlow"]
    private static let trades: [(shop: String, summary: String)] = [
        ("Bakery", "A bakery"), ("Tannery", "A tannery"), ("Chandlery", "A chandler’s shop"), ("Weavers", "A weaver’s workshop"),
        ("Cooperage", "A cooperage"), ("Apothecary", "An apothecary"), ("Grocer", "A grocer’s"), ("Fletchery", "A fletcher’s shop"),
        ("Masonry", "A mason’s yard"), ("Cobblers", "A cobbler’s shop"),
    ]
    private static let virtues = ["Light", "Mercy", "the Harvest", "the Hearth", "the Moon", "the Road", "Rest", "the Deep Wells"]

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

    mutating func street(using random: inout SeededRandom) -> String {
        unique { "\(Self.streetStarts.randomElement(using: &random) ?? "Mill") \(Self.streetEnds.randomElement(using: &random) ?? "Street")" }
    }

    mutating func quarter(using random: inout SeededRandom) -> String {
        unique { Self.quarters.randomElement(using: &random) ?? "Old Quarter" }
    }

    mutating func inn(using random: inout SeededRandom) -> String {
        unique { "The \(Self.innAdjectives.randomElement(using: &random) ?? "Gilded") \(Self.innNouns.randomElement(using: &random) ?? "Gull")" }
    }

    mutating func forge(using random: inout SeededRandom) -> String {
        unique { "\(Self.surnames.randomElement(using: &random) ?? "Hale")’s Forge" }
    }

    /// A shop and what it sells, such as ("Marsh’s Bakery", "A bakery").
    mutating func shop(using random: inout SeededRandom) -> (name: String, summary: String) {
        let trade = Self.trades.randomElement(using: &random) ?? Self.trades[0]
        let name = unique { "\(Self.surnames.randomElement(using: &random) ?? "Hale")’s \(trade.shop)" }
        return (name, trade.summary)
    }

    mutating func chapel(using random: inout SeededRandom) -> String {
        unique { "Chapel of \(Self.virtues.randomElement(using: &random) ?? "Light")" }
    }

    mutating func named(_ base: String) -> String { unique { base } }
}

extension NameBank {
    /// A name for a river, such as "River Hale".
    mutating func river(using random: inout SeededRandom) -> String {
        let surname = ["Hale", "Marsh", "Thorne", "Wick", "Fenn", "Bram", "Locke", "Rudd", "Tarn", "Vane", "Yarrow", "Dunn"].randomElement(using: &random) ?? "Hale"
        return named("River \(surname)")
    }
}

extension NameBank {
    mutating func manor(using random: inout SeededRandom) -> String {
        let surname = ["Hale", "Marsh", "Thorne", "Wick", "Cobb", "Fenn", "Bram", "Locke", "Rudd", "Tarn", "Vane", "Yarrow"].randomElement(using: &random) ?? "Hale"
        return named("\(surname) Manor")
    }

    private static let landmarkSurnames = ["Hale", "Marsh", "Thorne", "Wick", "Cobb", "Fenn", "Bram", "Locke", "Rudd", "Tarn", "Vane", "Yarrow"]
    private static let adjectives = ["Grey", "Iron", "White", "Black", "High", "Old", "Silent", "Stern", "Golden", "Red"]
    private static let landmarkVirtues = ["Light", "Mercy", "the Harvest", "the Hearth", "the Moon", "the Road", "Rest", "Wisdom"]

    /// A name for a landmark of a kind, such as "Cathedral of Mercy" or "Hale Keep".
    mutating func landmark(_ kind: Landmark, using random: inout SeededRandom) -> String {
        let surname = Self.landmarkSurnames.randomElement(using: &random) ?? "Hale"
        let adjective = Self.adjectives.randomElement(using: &random) ?? "Grey"
        let virtue = Self.landmarkVirtues.randomElement(using: &random) ?? "Light"
        switch kind {
        case .cathedral: return named(String(localized: "Cathedral of \(virtue)"))
        case .castle: return named(String(localized: "\(surname) Keep"))
        case .university: return named(String(localized: "University of \(surname)"))
        case .library: return named(String(localized: "The Great Library"))
        case .guildhall: return named(String(localized: "The \(adjective) Guildhall"))
        case .arena: return named(String(localized: "The \(adjective) Arena"))
        case .infirmary: return named(String(localized: "Infirmary of \(virtue)"))
        case .wizardsTower: return named(String(localized: "\(surname)’s Spire"))
        case .prison: return named(String(localized: "The \(adjective) Gaol"))
        }
    }
}
