//
//  RootLanguageTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

struct RootLanguageTests {
    private func names(seed: UInt64, language: RootLanguage) -> [String] {
        var random = SeededRandom(seed: seed)
        var bank = NameBank(language: language)
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

    @Test func theSameSeedGivesTheSameNamesAndAnotherGivesOthers() {
        #expect(names(seed: 1, language: RootLanguages.english) == names(seed: 1, language: RootLanguages.english))
        #expect(names(seed: 1, language: RootLanguages.english) != names(seed: 2, language: RootLanguages.english))
    }

    @Test func aRealmsNameIsMadeOfAStartAndAnEndOfItsLanguage() {
        for language in RootLanguages.all {
            var bank = NameBank(language: language)
            var random = SeededRandom(seed: 21)
            let starts = language.names["realmStart"] ?? [], ends = language.names["realmEnd"] ?? []
            for _ in 0..<20 {
                let name = bank.realm(using: &random)
                #expect(starts.contains { start in name.contains(" of " + start) && ends.contains { name.hasSuffix($0) } }, Comment(rawValue: "\(language.id): \(name)"))
            }
        }
    }

    @Test func theListsAreLongEnoughToGiveVariety() {
        for language in RootLanguages.all {
            for key in ["shopOwner", "manorOwner", "landmarkOwner"] { #expect((language.names[key] ?? []).count >= 36, Comment(rawValue: "\(language.id) \(key)")) }
            #expect((language.names["riverName"] ?? []).count >= 20, Comment(rawValue: "\(language.id) riverName"))
            #expect((language.names["placeStart"] ?? []).count >= 25 && (language.names["placeEnd"] ?? []).count >= 15, Comment(rawValue: "\(language.id) place"))
            #expect((language.names["realmStart"] ?? []).count >= 15 && (language.names["realmEnd"] ?? []).count >= 12, Comment(rawValue: "\(language.id) realm"))
        }
    }

    @Test func theShippedLanguagesAreAllValidAndEnglishComesFirst() {
        let all = RootLanguages.all
        #expect(all.map(\.id) == ["english", "celtic", "slavic", "romance", "germanic", "norse", "greek", "finnic", "iberian", "arabic", "persian", "turkic", "chinese", "japanese", "korean", "indic"])
        for language in all {
            #expect(language.problems.isEmpty, Comment(rawValue: "\(language.problems)"))
            for (name, words) in language.names { #expect(Set(words).count == words.count, Comment(rawValue: "\(language.id) \(name) repeats a name")) }
            for group in RootLanguages.concepts.keys { #expect(!language.words(group).isEmpty, Comment(rawValue: "\(language.id) \(group)")) }
        }
        // English has every concept, so it is the model a new language is written against.
        for (group, concepts) in RootLanguages.concepts { #expect(RootLanguages.english.words(group).count == concepts.count, Comment(rawValue: group)) }
        #expect(RootLanguages.language("nonsense").id == "english")
        // Names an earlier version used still find their language.
        #expect(RootLanguages.language("italian").id == "romance" && RootLanguages.language("welsh").id == "celtic" && RootLanguages.language("german").id == "germanic")
    }

    @Test func aLanguageWithGapsIsReportedInWords() {
        var language = RootLanguages.english
        language.words["street"] = ["mill": "Mill", "bridge": "Bridge", "nonsense": "Nope"]
        language.words["compass"] = ["east": "East"]
        language.words["mystery"] = ["x": "y"]
        language.names["placeEnd"] = ["ford"]
        language.names["shopOwner"] = nil
        let problems = language.problems.joined(separator: "\n")
        #expect(problems.contains("nonsense") && problems.contains("street needs") && problems.contains("compass needs") && problems.contains("mystery"))
        #expect(problems.contains("placeEnd needs") && problems.contains("shopOwner needs"))
    }

    @Test func everyLanguageGivesDeterministicUniqueNames() {
        for language in RootLanguages.all {
            #expect(names(seed: 9, language: language) == names(seed: 9, language: language), Comment(rawValue: language.id))
            #expect(names(seed: 9, language: language) != names(seed: 10, language: language), Comment(rawValue: language.id))
            var random = SeededRandom(seed: 5)
            var bank = NameBank(language: language)
            let streets = (0..<120).map { _ in bank.street(using: &random) }
            #expect(Set(streets).count == 120 && streets.allSatisfy { !$0.isEmpty }, Comment(rawValue: language.id))
            let towns = (0..<60).map { _ in bank.settlement(using: &random) }
            #expect(Set(towns).count == 60, Comment(rawValue: language.id))
        }
    }

    @Test func theProperNameIsTheRootLanguagesAndThePlainWordIsTheUsers() {
        let kinds = ["Street", "Lane", "Row", "Way", "Walk", "Road", "Close"]
        for language in RootLanguages.all {
            var random = SeededRandom(seed: 21)
            var bank = NameBank(language: language)
            let streetWords = language.words("street")
            for _ in 0..<30 {
                let street = bank.street(using: &random)
                // The last word is a plain English term, and what is before it is a word of the language.
                #expect(kinds.contains { street.hasSuffix(" " + $0) || street.contains(" " + $0 + " ") }, Comment(rawValue: "\(language.id): \(street)"))
                #expect(streetWords.contains { street.hasPrefix($0 + " ") }, Comment(rawValue: "\(language.id): \(street)"))
            }
            #expect(bank.chapel(using: &random).hasPrefix("Chapel of "))
            #expect(bank.river(using: &random).hasPrefix("River "))
            #expect(bank.manor(using: &random).hasSuffix(" Manor"))
            #expect(bank.realm(using: &random).contains(" of "))
            #expect(bank.forest(using: &random).hasPrefix("The ") && bank.forest(using: &random).hasSuffix(" Forest"))
            #expect(bank.quarter(using: &random).hasSuffix(" Quarter"))
            #expect(bank.inn(using: &random).hasPrefix("The "))
            #expect(bank.marketSquare() == "Market Square")
            let shop = bank.shop(using: &random)
            #expect(shop.name.contains("’s ") && shop.summary.hasPrefix("A"))
        }
    }

    @Test func eachLanguageUsesItsOwnWordsNotEnglishOnes() {
        let english = Set(RootLanguages.english.words("street") + RootLanguages.english.words("innNoun"))
        for language in RootLanguages.all where language.id != "english" {
            let own = Set(language.words("street") + language.words("innNoun"))
            // Some words are the same in two languages (Lantern/Lanterna are not, but Port is), but most are not.
            #expect(own.intersection(english).count < own.count / 4, Comment(rawValue: language.id))
        }
        var random = SeededRandom(seed: 4)
        var englishBank = NameBank(), celticBank = NameBank(language: RootLanguages.language("celtic"))
        #expect(englishBank.settlement(using: &random) != celticBank.settlement(using: &random))
    }

    @Test func aQualifyingWordComesBeforeOrAfterAsTheLanguageHasIt() {
        var random = SeededRandom(seed: 2)
        for (id, adjectiveFirst) in [("english", true), ("germanic", true), ("romance", false), ("celtic", false)] {
            let language = RootLanguages.language(id)
            var bank = NameBank(language: language)
            for _ in 0..<12 {
                let inn = bank.inn(using: &random)
                let body = String(inn.dropFirst(4))
                let first = adjectiveFirst ? language.words("innAdjective") : language.words("innNoun")
                #expect(first.contains { body.hasPrefix($0 + " ") }, Comment(rawValue: "\(id): \(inn)"))
            }
        }
    }

    @Test func gatesAndRoadsKeepTheGateWordInTheProperName() {
        var random = SeededRandom(seed: 1)
        _ = random.next()
        for language in RootLanguages.all {
            let compass = language.words("compass")
            let gate = language.words("gate")[0]
            var bank = NameBank(language: language)
            // The gate itself is a proper direction and the plain word Gate; its road has the language's word for a gate in the name.
            #expect(bank.gate(direction: 2) == compass[2] + " Gate", Comment(rawValue: language.id))
            #expect(bank.road(direction: 2) == compass[2] + " Road", Comment(rawValue: language.id))
            let gateRoad = bank.gateRoad(direction: 2)
            let expected = language.modifierPosition == .before ? "\(compass[2]) \(gate) Road" : "\(gate) \(compass[2]) Road"
            #expect(gateRoad == expected, Comment(rawValue: language.id))
        }
        var a = NameBank(), b = NameBank(), c = NameBank()
        #expect(a.road(direction: 0) == "East Road" && b.road(direction: 15) == "South-East Road" && c.road(direction: -1) == "South-East Road")
        var d = NameBank()
        #expect(d.gateRoad(direction: 2) == "North Gate Road")
    }

    @Test func aShopsSummaryIsTheTradeInPlainEnglish() {
        var random = SeededRandom(seed: 2)
        var bank = NameBank(language: RootLanguages.language("romance"))
        let summaries = Set(NameTerms.trades.map(\.summary))
        for _ in 0..<20 { #expect(summaries.contains(bank.shop(using: &random).summary)) }
    }
}

struct RootLanguageGenerationTests {
    @Test func aSettlementTakesItsProperNamesFromTheChosenLanguage() {
        var options = SettlementOptions(size: .town, layout: .organic, hasWalls: true, hasRiver: true, seed: 7)
        options.landmarks = [.cathedral, .castle]
        let english = SettlementGenerator.generate(options)
        options.namingStyle = "romance"
        let romance = SettlementGenerator.generate(options)
        let language = RootLanguages.language("romance")
        let streets = romance.features.filter { $0.placeType == "Street" }.map(\.name)
        #expect(!streets.isEmpty && streets.allSatisfy { name in language.words("street").contains { name.hasPrefix($0 + " ") } })
        #expect(romance.features.contains { $0.name == "Market Square" })
        #expect(romance.features.contains { $0.name.hasPrefix("Cathedral of ") && language.words("landmarkVirtue").contains(String($0.name.dropFirst("Cathedral of ".count))) })
        #expect(romance.features.contains { $0.name.hasSuffix(" Keep") } && romance.features.contains { $0.placeType == "River" && $0.name.hasPrefix("River ") })
        #expect(romance.features.contains { $0.name == "Porta Nord Road" || $0.name.hasPrefix("Porta ") && $0.name.hasSuffix(" Road") })
        #expect(romance.features.contains { feature in feature.name.hasSuffix(" Gate") && language.words("compass").contains { feature.name.hasPrefix($0) } })
        // The shape of the settlement is the same: only the words change.
        #expect(english.features.map(\.placeType) == romance.features.map(\.placeType))
        #expect(english.features.contains { $0.name.hasSuffix(" Gate Road") })
    }

    @Test func aWorldTakesItsRealmsAndTownsFromTheChosenLanguage() {
        var options = WorldOptions()
        options.seed = 4
        options.width = 200_000
        options.namingStyle = "norse"
        let language = RootLanguages.language("norse")
        let world = WorldGenerator.generate(options)
        let realms = world.features(of: "Region").map(\.name)
        #expect(!realms.isEmpty && realms.allSatisfy { realm in realm == "The Land" || (realm.contains(" of ") && language.names["realmEnd"]!.contains { realm.hasSuffix($0) }) })
        #expect(world.features(of: "Mountains").allSatisfy { $0.name.hasPrefix("The ") && $0.name.hasSuffix(" Mountains") })
        #expect(world.features(of: "Mountains").allSatisfy { feature in language.words("peakAdjective").contains { feature.name == "The \($0) Mountains" } })
    }

    @Test func aSceneNamesItsInnsAndShopsFromTheChosenLanguage() {
        var options = SceneOptions()
        options.kind = .marketSquare
        options.seed = 3
        options.namingStyle = "germanic"
        let scene = SceneGenerator.generate(options)
        let language = RootLanguages.language("germanic")
        #expect(scene.features.contains { $0.name == "The Market Square" })
        let owners = language.names["shopOwner"] ?? []
        #expect(scene.features.contains { feature in owners.contains { feature.name.hasPrefix($0 + "’s ") } || feature.name.hasPrefix("The ") && language.words("innNoun").contains { feature.name.contains($0) } })
    }

    @Test func olderOptionsWithoutALanguageAreEnglishAndAnOldStyleNameStillWorks() throws {
        let old = try JSONDecoder().decode(SettlementOptions.self, from: Data(#"{"size":"town","seed":5}"#.utf8))
        #expect(old.namingStyle == "english")
        #expect(try JSONDecoder().decode(WorldOptions.self, from: Data(#"{"seed":5}"#.utf8)).namingStyle == "english")
        #expect(try JSONDecoder().decode(SceneOptions.self, from: Data(#"{"seed":5}"#.utf8)).namingStyle == "english")
        var options = SettlementOptions()
        options.namingStyle = "celtic"
        let back = try JSONDecoder().decode(SettlementOptions.self, from: JSONEncoder().encode(options))
        #expect(back.namingStyle == "celtic")
        // A map saved with a style the first version called "welsh" gets its language back.
        #expect(RootLanguages.language("welsh").id == "celtic")
    }
}

struct RealmLanguageTests {
    private func world(_ configure: (inout WorldOptions) -> Void = { _ in }) -> GeneratedWorld {
        var options = WorldOptions()
        options.seed = 11
        options.width = 300_000
        options.realms = 2
        configure(&options)
        return WorldGenerator.generate(options)
    }

    @Test func aRealmWithNoLanguagesChosenUsesTheWorldsAndTheNamesAreUnchanged() {
        let plain = world()
        let explicit = world { $0.realmLanguages = [[LanguageWeight(id: "english", weight: 50)], []] }
        #expect(plain.features.map(\.name) == explicit.features.map(\.name))
    }

    @Test func eachRealmNamesItselfAndItsSettlementsInItsOwnLanguage() {
        let made = world { $0.setLanguage("norse", on: true, forRealm: 1); $0.setLanguage("english", on: false, forRealm: 1)
                           $0.setLanguage("romance", on: true, forRealm: 0); $0.setLanguage("english", on: false, forRealm: 0) }
        let romance = RootLanguages.language("romance")
        let norse = RootLanguages.language("norse")
        func realmName(_ number: Int) -> String? { made.features(of: "Region").first { $0.kind == "realm \(number)" }?.name }
        #expect(realmName(0).map { name in romance.names["realmEnd"]!.contains { name.hasSuffix($0) } } == true)
        #expect(realmName(1).map { name in norse.names["realmEnd"]!.contains { name.hasSuffix($0) } } == true)
    }

    @Test func aMixedRealmUsesEachOfItsLanguages() {
        var options = WorldOptions()
        options.realms = 1
        options.setLanguage("norse", on: true, forRealm: 0)
        options.setLanguage("romance", on: true, forRealm: 0)
        options.setLanguage("english", on: false, forRealm: 0)
        var bank = NameBank(languages: options.languages(forRealm: 0))
        var random = SeededRandom(seed: 3)
        let names = (0..<60).map { _ in bank.chapel(using: &random) }
        let norse = RootLanguages.language("norse").words("chapelVirtue")
        let romance = RootLanguages.language("romance").words("chapelVirtue")
        #expect(names.contains { name in norse.contains { name.hasSuffix($0) } })
        #expect(names.contains { name in romance.contains { name.hasSuffix($0) } })
    }

    @Test func theWeightsDecideHowOftenEachIsUsed() {
        var options = WorldOptions()
        options.setLanguage("norse", on: true, forRealm: 0)
        options.setLanguage("romance", on: true, forRealm: 0)
        options.setLanguage("english", on: false, forRealm: 0)
        options.setWeight(100, of: "norse", forRealm: 0)
        options.setWeight(1, of: "romance", forRealm: 0)
        // A fresh bank each time, as a bank runs out of unused chapel names after a few.
        var random = SeededRandom(seed: 5)
        let norse = RootLanguages.language("norse").words("chapelVirtue")
        let names = (0..<80).map { _ -> String in
            var bank = NameBank(languages: options.languages(forRealm: 0))
            return bank.chapel(using: &random)
        }
        #expect(names.filter { name in norse.contains { name.hasSuffix($0) } }.count > 60)
    }

    @Test func theLastLanguageCannotBeTurnedOffAndTheChoicesSurviveSaving() throws {
        var options = WorldOptions()
        options.setLanguage("english", on: false, forRealm: 0)
        #expect(options.languages(forRealm: 0).count == 1)
        options.setLanguage("celtic", on: true, forRealm: 1)
        let back = try JSONDecoder().decode(WorldOptions.self, from: JSONEncoder().encode(options))
        #expect(back == options)
        let old = try JSONDecoder().decode(WorldOptions.self, from: Data("{}".utf8))
        #expect(old.realmLanguages.isEmpty)
    }
}

@MainActor
struct SettlementLanguageTests {
    @Test func aSettlementInARealmTakesTheLanguagesOfThatRealm() async throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Aldara")
        context.insert(world)
        world.ensureRootPlace(in: context)
        var options = WorldOptions()
        options.seed = 3
        options.realms = 2
        options.width = 300_000
        options.setLanguage("norse", on: true, forRealm: 0)
        options.setLanguage("english", on: false, forRealm: 0)
        options.setLanguage("romance", on: true, forRealm: 1)
        options.setLanguage("english", on: false, forRealm: 1)
        _ = try #require(await world.generateWorld(options: options, in: context))
        let towns = (world.pages ?? []).filter { $0.attributeText("core.placeType") == "Settlement" && !$0.isDeleted }
        #expect(!towns.isEmpty)
        for town in towns {
            let mix = try #require(town.realmLanguages)
            #expect(mix.count == 1 && ["norse", "romance"].contains(mix[0].id))
        }
        #expect(Set(towns.compactMap { $0.realmLanguages?.first?.id }).count == 2)
    }

    @Test func aPlaceOutsideAnyRealmHasNoRealmLanguages() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Aldara")
        context.insert(world)
        let place = world.addPage(kind: .place, in: context)
        place.geometry = .point(GridPoint(easting: 10, northing: 10))
        #expect(place.realmLanguages == nil)
    }

    @Test func aSettlementsNamesFollowItsLanguagesAndOlderOptionsStillOpen() throws {
        var options = SettlementOptions(size: .town, layout: .organic, seed: 5)
        #expect(options.nameLanguages.map(\.id) == ["english"] && options.inheritsRealm)
        options.languages = [LanguageWeight(id: "norse", weight: 50)]
        let norse = RootLanguages.language("norse")
        let streets = SettlementGenerator.generate(options).features.filter { $0.placeType == "Street" }.map(\.name)
        #expect(!streets.isEmpty && streets.allSatisfy { name in norse.words("street").contains { name.hasPrefix($0 + " ") } })
        let back = try JSONDecoder().decode(SettlementOptions.self, from: JSONEncoder().encode(options))
        #expect(back == options)
        let old = try JSONDecoder().decode(SettlementOptions.self, from: Data("{}".utf8))
        #expect(old.languages.isEmpty && old.inheritsRealm)
    }
}

struct BlendedNameTests {
    private func towns(_ chance: Double, count: Int = 150) -> [String] {
        var bank = NameBank(languages: [LanguageWeight(id: "celtic", weight: 50), LanguageWeight(id: "slavic", weight: 50)])
        bank.blendChance = chance
        var random = SeededRandom(seed: 9)
        return (0..<count).map { _ in bank.settlement(using: &random) }
    }

    /// Whether a name's start and end come from the two languages in the order given.
    private func isBlend(_ name: String, _ first: String, _ second: String) -> Bool {
        let a = RootLanguages.language(first).names["placeStart"] ?? []
        let b = RootLanguages.language(second).names["placeEnd"] ?? []
        return a.contains { start in name.hasPrefix(start) && b.contains { name.hasSuffix($0) } }
    }

    @Test func withNoChanceOfBlendingEveryNameIsInOneLanguage() {
        let names = towns(0)
        let own = names.filter { isBlend($0, "celtic", "celtic") || isBlend($0, "slavic", "slavic") }
        // A name that happens to read as both is still in one; every name must be whole in one language.
        #expect(own.count == names.count)
    }

    @Test func withACertainChanceMostNamesTakeTheirPartsFromBothLanguages() {
        let names = towns(1)
        let mixed = names.filter { isBlend($0, "celtic", "slavic") || isBlend($0, "slavic", "celtic") }
        #expect(mixed.count > names.count * 3 / 4)
    }

    @Test func theDefaultChanceGivesSomeButNotMostBlends() {
        let names = towns(NameBank.defaultBlendChance, count: 300)
        let whole = names.filter { isBlend($0, "celtic", "celtic") || isBlend($0, "slavic", "slavic") }.count
        #expect(whole > names.count / 2 && whole < names.count)
    }

    @Test func oneLanguageNeverBlendsAndEnglishNamesAreUnchanged() {
        var bank = NameBank(languages: [LanguageWeight(id: "english", weight: 50)])
        bank.blendChance = 1
        var random = SeededRandom(seed: 9)
        var plain = NameBank()
        var plainRandom = SeededRandom(seed: 9)
        #expect((0..<30).map { _ in bank.settlement(using: &random) } == (0..<30).map { _ in plain.settlement(using: &plainRandom) })
    }
}
