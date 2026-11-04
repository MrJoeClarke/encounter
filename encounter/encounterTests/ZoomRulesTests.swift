//
//  ZoomRulesTests.swift
//  encounterTests
//

import Testing
@testable import encounter

struct ZoomRulesTests {
    private let rules = ZoomRules.standard

    @Test func biggerPlacesShowFurtherOut() {
        #expect(rules.pin(.capital) >= rules.pin(.city))
        #expect(rules.pin(.city) > rules.pin(.town))
        #expect(rules.pin(.town) > rules.pin(.village))
        #expect(rules.name(ofType: "Region") == 1)
        #expect(rules.name(ofType: "Water") == 1)
        #expect(rules.name(ofType: "Region") > rules.name(ofType: "Road"))
        #expect(rules.name(ofType: "Road") > rules.name(ofType: "Street"))
        #expect(rules.name(ofType: "Street") > rules.name(ofType: "Building"))
    }

    @Test func aNameShowsNoFurtherOutThanItsPin() {
        for kind in [PlacePinKind.capital, .city, .town, .village, .castle, .landmark, .place] {
            #expect(rules.pinName(kind) <= rules.pin(kind), Comment(rawValue: kind.rawValue))
        }
    }

    @Test func everyKindOfPinHasARule() {
        for kind in [PlacePinKind.capital, .city, .town, .village, .cathedral, .castle, .university, .library, .guildhall, .arena, .infirmary, .wizardsTower, .prison, .landmark, .place] {
            #expect(rules.pins[kind.rawValue] != nil, Comment(rawValue: kind.rawValue))
            #expect(rules.pinNames[kind.rawValue] != nil, Comment(rawValue: kind.rawValue))
        }
    }

    @Test func aTownMapCountsAsCloserThanTheWholeWorld() {
        #expect(ZoomRules.view(share: 1, on: .world) == 1)
        #expect(ZoomRules.view(share: 1, on: .settlement) < 1)
        // The whole of a town shows its landmarks and its streets' names, but not the buildings' names.
        let whole = ZoomRules.view(share: 1, on: .settlement)
        #expect(rules.pin(.landmark) >= whole)
        #expect(rules.name(ofType: "District") >= whole)
        #expect(rules.name(ofType: "Building") < whole)
        // Close in, they are named.
        #expect(rules.name(ofType: "Building") >= ZoomRules.view(share: 0.15, on: .settlement))
    }

    @Test func aWholeWorldShowsRealmsAndCitiesButNotVillagesOrRoads() {
        #expect(rules.pin(.city) >= 1)
        #expect(rules.pin(.village) < 1)
        #expect(rules.name(ofType: "Road") < 1)
        #expect(rules.name(ofType: "Street") < 1)
    }

    @Test func everyStyleHasRules() {
        for style in MapStyle.all { #expect(style.zoom == ZoomRules.standard, Comment(rawValue: style.id)) }
    }

    @Test func buildingsAreNamedOnceZoomedIn() {
        #expect(PlaceLabelKind.of(type: "Building") == .area)
    }
}
