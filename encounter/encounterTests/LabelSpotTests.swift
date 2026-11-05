//
//  LabelSpotTests.swift
//  encounterTests
//

import Testing
@testable import encounter

struct LabelSpotTests {
    private func square(_ x: Double, _ y: Double, _ side: Double) -> [GridPoint] {
        [GridPoint(easting: x, northing: y), GridPoint(easting: x + side, northing: y), GridPoint(easting: x + side, northing: y + side), GridPoint(easting: x, northing: y + side)]
    }

    @Test func aNameInsideAnAreaIsInsideAndFromTheEdge() {
        let outline = square(0, 0, 1000)
        let spot = LabelSpot.inside(outline)
        #expect(PlaceGeometry.polygon(outline).contains(spot))
        #expect(abs(spot.easting - 500) < 100 && abs(spot.northing - 500) < 100)
    }

    @Test func aBentAreaIsNamedInsideItNotInTheBendsMiddle() {
        // An L: the middle of its bounding box is outside it.
        let l = [
            GridPoint(easting: 0, northing: 0), GridPoint(easting: 1000, northing: 0), GridPoint(easting: 1000, northing: 200),
            GridPoint(easting: 200, northing: 200), GridPoint(easting: 200, northing: 1000), GridPoint(easting: 0, northing: 1000),
        ]
        let spot = LabelSpot.inside(l)
        #expect(PlaceGeometry.polygon(l).contains(spot))
    }

    @Test func aNameKeepsOffAPinWhenThereIsRoom() {
        let outline = square(0, 0, 1000)
        let pin = GridPoint(easting: 500, northing: 500)
        let spot = LabelSpot.inside(outline, avoiding: [pin])
        #expect(spot.distance(to: pin) > 200)
        #expect(PlaceGeometry.polygon(outline).contains(spot))
    }

    @Test func theSeaIsNamedOnOpenWaterAwayFromTheLand() {
        // Land fills the middle and the left of the map, so open water is on the right.
        let land = [square(100, 100, 600)]
        let spot = LabelSpot.openWater(from: GridPoint(easting: 0, northing: 0), to: GridPoint(easting: 1000, northing: 1000), land: land)
        #expect(!PlaceGeometry.polygon(land[0]).contains(spot))
        #expect(spot.easting > 700 || spot.northing > 700)
    }

    @Test func aRealmAndTheSeaAreNamedBeforeAnythingElse() {
        #expect(PlaceLabelKind.priority(type: "Region") > PlaceLabelKind.priority(type: "Water"))
        #expect(PlaceLabelKind.priority(type: "Water") > PlaceLabelKind.priority(type: "Mountains"))
        #expect(PlaceLabelKind.priority(type: "Region") == 1000)
    }
}
