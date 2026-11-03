//
//  NamingStyleTests.swift
//  encounterTests
//

import Testing
import Foundation
@testable import encounter

struct NamingStyleTests {
    /// What the English names were before they came from a style file, for four seeds: they must not change, or a map made again
    /// from its seed would get new names.
    private static let golden: [String: [String]] = try! JSONDecoder().decode([String: [String]].self, from: Data("""
{
  "seed1": [
    "New Road",
    "Lantern Way",
    "High Road",
    "Elm Way",
    "Well Road",
    "River Walk",
    "Garden Quarter",
    "Harbour Quarter",
    "Craft Quarter",
    "The Wandering Plough",
    "The Wandering Kettle",
    "The Gilded Stag",
    "Rudd’s Forge",
    "Fenn’s Tannery|A tannery",
    "Tarn’s Bakery|A bakery",
    "Hale’s Fletchery|A fletcher’s shop",
    "Chapel of the Deep Wells",
    "Chapel of the Moon",
    "River Rudd",
    "River Fenn",
    "Fenn Manor",
    "Cathedral of the Moon",
    "Rudd Keep",
    "University of Vane",
    "The Great Library",
    "The Iron Guildhall",
    "The Black Arena",
    "Infirmary of the Hearth",
    "Marsh’s Spire",
    "The Golden Gaol",
    "Casby",
    "Blackchester",
    "Marford",
    "Aldworth",
    "Elmham",
    "Dominion of Corvane",
    "Principality of Oakenfell",
    "Duchy of Penhallow",
    "The Ancient Forest",
    "The Red Mountains",
    "The Grey Sea",
    "Weaver’s Lane"
  ],
  "seed2": [
    "Chapel Road",
    "Stone Row",
    "Cooper’s Road",
    "Baker’s Road",
    "Oak Way",
    "New Row",
    "Guild Quarter",
    "Temple Quarter",
    "Merchant Quarter",
    "The Merry Boar",
    "The Gilded Barrel",
    "The Merry Anchor",
    "Sorrel’s Forge",
    "Tarn’s Fletchery|A fletcher’s shop",
    "Hale’s Grocer|A grocer’s",
    "Reeve’s Weavers|A weaver’s workshop",
    "Chapel of the Moon",
    "Chapel of the Harvest",
    "River Fenn",
    "River Yarrow",
    "Cobb Manor",
    "Cathedral of Wisdom",
    "Thorne Keep",
    "University of Hale",
    "The Great Library",
    "The Old Guildhall",
    "The Black Arena",
    "Infirmary of the Moon",
    "Cobb’s Spire",
    "The Black Gaol",
    "Norford",
    "Eastworth",
    "Halworth",
    "Overwick",
    "Elmgate",
    "Dominion of Stormvale",
    "Realm of Lorrain",
    "Realm of Oakenfell",
    "The Grey Forest",
    "The Red Mountains",
    "The Stormy Sea",
    "Tanner’s Street"
  ],
  "seed3": [
    "Church Walk",
    "Mason’s Street",
    "Smith’s Walk",
    "King’s Close",
    "Low Close",
    "Fisher’s Walk",
    "Garden Quarter",
    "Merchant Quarter",
    "Tanners’ Quarter",
    "The Red Anchor",
    "The Rusty Boar",
    "The Drunken Plough",
    "Sorrel’s Forge",
    "Wick’s Grocer|A grocer’s",
    "Sorrel’s Grocer|A grocer’s",
    "Thorne’s Chandlery|A chandler’s shop",
    "Chapel of the Road",
    "Chapel of Rest",
    "River Tarn",
    "River Tarn 2",
    "Thorne Manor",
    "Cathedral of Mercy",
    "Fenn Keep",
    "University of Cobb",
    "The Great Library",
    "The Golden Guildhall",
    "The Iron Arena",
    "Infirmary of the Moon",
    "Cobb’s Spire",
    "The Old Gaol",
    "Oakham",
    "Thornfield",
    "Ashbridge",
    "Ashminster",
    "Kingfield",
    "Realm of Brightmarch",
    "Duchy of Lorrain",
    "Duchy of Fenwald",
    "The Elder Forest",
    "The Frost Mountains",
    "The Salt Sea",
    "Stone Row"
  ],
  "seed4": [
    "River Close",
    "Orchard Way",
    "Ash Walk",
    "Briar Way",
    "Tanner’s Way",
    "Gate Walk",
    "Harbour Quarter",
    "Weavers’ Quarter",
    "Scholars’ Quarter",
    "The Red Raven",
    "The Laughing Wheel",
    "The Rusty Crown",
    "Hale’s Forge",
    "Thorne’s Grocer|A grocer’s",
    "Sorrel’s Apothecary|An apothecary",
    "Reeve’s Apothecary|An apothecary",
    "Chapel of Mercy",
    "Chapel of the Road",
    "River Dunn",
    "River Hale",
    "Wick Manor",
    "Cathedral of Rest",
    "Locke Keep",
    "University of Thorne",
    "The Great Library",
    "The Red Guildhall",
    "The Black Arena",
    "Infirmary of the Harvest",
    "Rudd’s Spire",
    "The Iron Gaol",
    "Blackfield",
    "Greyton",
    "Oakham",
    "Halbridge",
    "Longbridge",
    "Principality of Eastmark",
    "Realm of Fenwald",
    "Kingdom of Aldermere",
    "The Elder Forest",
    "The Red Mountains",
    "The Silver Sea",
    "Heron Row"
  ]
}
""".utf8))

    private func names(seed: UInt64, style: NamingStyle) -> [String] {
        var random = SeededRandom(seed: seed)
        var bank = NameBank(style: style)
        var names: [String] = []
        for _ in 0..<6 { names.append(bank.street(using: &random)) }
        for _ in 0..<3 { names.append(bank.quarter(using: &random)) }
        for _ in 0..<3 { names.append(bank.inn(using: &random)) }
        names.append(bank.forge(using: &random))
        for _ in 0..<3 { let s = bank.shop(using: &random); names.append(s.name + "|" + s.summary) }
        for _ in 0..<2 { names.append(bank.chapel(using: &random)) }
        for _ in 0..<2 { names.append(bank.river(using: &random)) }
        names.append(bank.manor(using: &random))
        for kind in Landmark.allCases { names.append(bank.landmark(kind, using: &random)) }
        for _ in 0..<5 { names.append(bank.settlement(using: &random)) }
        for _ in 0..<3 { names.append(bank.realm(using: &random)) }
        names.append(bank.forest(using: &random)); names.append(bank.mountains(using: &random)); names.append(bank.sea(using: &random))
        names.append(bank.street(using: &random))
        return names
    }

    @Test func englishNamesAreExactlyWhatTheyWere() {
        for seed in UInt64(1)...4 {
            #expect(names(seed: seed, style: NamingStyles.english) == Self.golden["seed\(seed)"], "seed \(seed)")
        }
    }

    @Test func theShippedStylesAreAllValidAndEnglishComesFirst() {
        let all = NamingStyles.all
        #expect(all.map(\.id) == ["english", "italian", "german", "norse", "welsh"])
        for style in all {
            #expect(style.problems.isEmpty, "\(style.problems)")
            #expect(!style.title.isEmpty && !style.summary.isEmpty && style.trades.count >= 8)
            for (name, words) in style.lists { #expect(words.count >= 3 && Set(words).count == words.count, "\(style.id) \(name)") }
        }
        #expect(NamingStyles.style("nonsense").id == "english")
    }

    @Test func aStyleWithAGapIsReported() {
        var style = NamingStyles.english
        style.patterns["street"] = nil
        style.patterns["inn"] = ["The {missingWords} Inn"]
        style.trades = []
        #expect(style.problems.count == 3)
    }

    @Test func everyStyleGivesDeterministicUniqueNames() {
        for style in NamingStyles.all {
            #expect(names(seed: 9, style: style) == names(seed: 9, style: style), Comment(rawValue: style.id))
            #expect(names(seed: 9, style: style) != names(seed: 10, style: style), Comment(rawValue: style.id))
            // A big city's worth of streets and settlements are all different.
            var random = SeededRandom(seed: 5)
            var bank = NameBank(style: style)
            let streets = (0..<120).map { _ in bank.street(using: &random) }
            #expect(Set(streets).count == 120 && streets.allSatisfy { !$0.isEmpty }, Comment(rawValue: style.id))
            let towns = (0..<60).map { _ in bank.settlement(using: &random) }
            #expect(Set(towns).count == 60, Comment(rawValue: style.id))
            #expect(!bank.marketSquare().isEmpty)
        }
    }

    @Test func eachStyleSoundsLikeItself() {
        func many(_ style: String, _ make: (inout NameBank, inout SeededRandom) -> String) -> [String] {
            var random = SeededRandom(seed: 21)
            var bank = NameBank(style: NamingStyles.style(style))
            return (0..<40).map { _ in make(&bank, &random) }
        }
        #expect(many("italian") { $0.street(using: &$1) }.allSatisfy { $0.startsWithAny(["Via ", "Vicolo ", "Strada ", "Corso "]) })
        #expect(many("italian") { $0.inn(using: &$1) }.allSatisfy { $0.startsWithAny(["Osteria ", "Locanda ", "Taverna "]) })
        #expect(many("german") { $0.street(using: &$1) }.allSatisfy { $0.containsAny(["straße", "gasse", "weg", "pfad"]) && !$0.contains(" ") })
        #expect(many("german") { $0.inn(using: &$1) }.allSatisfy { $0.hasPrefix("Zum ") })
        #expect(many("norse") { $0.street(using: &$1) }.allSatisfy { $0.containsAny(["gata", "veien", "smuget"]) })
        #expect(many("norse") { $0.inn(using: &$1) }.allSatisfy { $0.hasPrefix("Den ") })
        #expect(many("welsh") { $0.street(using: &$1) }.allSatisfy { $0.startsWithAny(["Heol ", "Lôn ", "Stryd "]) })
        #expect(many("welsh") { $0.inn(using: &$1) }.allSatisfy { $0.hasPrefix("Y ") || $0.hasPrefix("Yr ") })
        #expect(many("welsh") { $0.settlement(using: &$1) }.allSatisfy { $0.startsWithAny(["Aber", "Llan", "Pen"]) })
        // And none of them is the English one.
        for style in ["italian", "german", "norse", "welsh"] {
            var random = SeededRandom(seed: 3)
            var english = NameBank(), other = NameBank(style: NamingStyles.style(style))
            #expect(english.shop(using: &random).name != other.shop(using: &random).name)
            #expect(other.marketSquare() != "Market Square", Comment(rawValue: style))
        }
    }

    @Test func theGatesAndRoadsAreNamedForTheirDirectionInEachStyle() {
        for (style, expected) in [("english", "North Gate"), ("italian", "Porta Nord"), ("german", "Nordtor"), ("norse", "Nordporten"), ("welsh", "Porth y Gogledd")] {
            var bank = NameBank(style: NamingStyles.style(style))
            #expect(bank.gate(direction: 2) == expected, Comment(rawValue: style))
            #expect(bank.road(direction: 2) != bank.gateRoad(direction: 2), Comment(rawValue: style))
        }
        // Directions wrap round, so any whole number names one of the eight.
        var a = NameBank(), b = NameBank(), c = NameBank()
        #expect(a.road(direction: 0) == "East Road" && b.road(direction: 15) == "South-East Road" && c.road(direction: -1) == "South-East Road")
    }

    @Test func aShopsSummaryIsTheTradeInPlainEnglish() {
        var random = SeededRandom(seed: 2)
        var bank = NameBank(style: NamingStyles.style("italian"))
        let summaries = Set(NamingStyles.english.trades.map(\.summary))
        for _ in 0..<20 { #expect(summaries.contains(bank.shop(using: &random).summary)) }
    }
}

private extension String {
    func startsWithAny(_ prefixes: [String]) -> Bool { prefixes.contains { hasPrefix($0) } }
    func containsAny(_ parts: [String]) -> Bool { parts.contains { contains($0) } }
}

struct NamingStyleGenerationTests {
    @Test func aSettlementTakesItsNamesFromTheChosenStyle() {
        var options = SettlementOptions(size: .town, layout: .organic, hasWalls: false, hasRiver: true, seed: 7)
        options.landmarks = [.cathedral, .castle]
        let english = SettlementGenerator.generate(options)
        options.namingStyle = "italian"
        let italian = SettlementGenerator.generate(options)
        let streets = italian.features.filter { $0.placeType == "Street" }.map(\.name)
        #expect(!streets.isEmpty && streets.contains { $0.hasPrefix("Via ") || $0.hasPrefix("Vicolo ") || $0.hasPrefix("Strada ") || $0.hasPrefix("Corso ") })
        #expect(italian.features.contains { $0.name == "Piazza del Mercato" })
        #expect(italian.features.contains { $0.name.hasPrefix("Cattedrale di ") } && italian.features.contains { $0.name.hasPrefix("Castello ") })
        #expect(italian.features.contains { $0.placeType == "River" && $0.name.hasPrefix("Fiume ") })
        #expect(italian.features.contains { $0.name.hasPrefix("Via della Porta ") } && !italian.features.contains { $0.name.contains("Gate Road") })
        #expect(english.features.contains { $0.name.hasSuffix(" Gate Road") })
        #expect(english.features.contains { $0.name == "Market Square" } && !english.features.contains { $0.name.hasPrefix("Via ") })
        // The shape of the settlement is the same: only the words change.
        #expect(english.features.map(\.placeType) == italian.features.map(\.placeType))
    }

    @Test func aWorldTakesItsRealmsAndTownsFromTheChosenStyle() {
        var options = WorldOptions()
        options.seed = 4
        options.width = 200_000
        options.namingStyle = "norse"
        let world = WorldGenerator.generate(options)
        let realms = world.features(of: "Region").map(\.name)
        #expect(!realms.isEmpty && realms.allSatisfy { $0.hasPrefix("Kongeriket ") || $0.hasPrefix("Hertugdømmet ") || $0.hasPrefix("Jarledømmet ") || $0.hasPrefix("Fylket ") || $0.hasPrefix("Riket ") || $0 == "The Land" })
        #expect(world.features(of: "Mountains").allSatisfy { $0.name.hasPrefix("De ") })
    }

    @Test func aSceneNamesItsInnsAndShopsInTheChosenStyle() {
        var options = SceneOptions()
        options.kind = .marketSquare
        options.seed = 3
        options.namingStyle = "german"
        let scene = SceneGenerator.generate(options)
        #expect(scene.features.contains { $0.name == "Marktplatz" })
        #expect(scene.features.contains { $0.name.hasPrefix("Zum ") || $0.name.contains("Bäckerei") || $0.name.contains("Gerberei") || $0.name.contains("erei ") || $0.name.contains("Apotheke") || $0.name.contains("Steinmetz") })
        options.namingStyle = "english"
        #expect(SceneGenerator.generate(options).features.contains { $0.name == "The Market Square" })
    }

    @Test func olderOptionsWithoutAStyleAreEnglishAndAStyleSurvivesSaving() throws {
        let old = try JSONDecoder().decode(SettlementOptions.self, from: Data(#"{"size":"town","seed":5}"#.utf8))
        #expect(old.namingStyle == "english")
        #expect(try JSONDecoder().decode(WorldOptions.self, from: Data(#"{"seed":5}"#.utf8)).namingStyle == "english")
        #expect(try JSONDecoder().decode(SceneOptions.self, from: Data(#"{"seed":5}"#.utf8)).namingStyle == "english")
        var options = SettlementOptions()
        options.namingStyle = "welsh"
        let back = try JSONDecoder().decode(SettlementOptions.self, from: JSONEncoder().encode(options))
        #expect(back.namingStyle == "welsh")
    }
}
