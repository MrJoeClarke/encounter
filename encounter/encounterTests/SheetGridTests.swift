//
//  SheetGridTests.swift
//  encounterTests
//

import Foundation
import Testing
@testable import encounter

struct SheetGridTests {
    @Test func theGridIsARoundNumberOfMetresApartAndFarEnoughApartToRead() {
        for metresPerPoint in [0.05, 0.4, 3.0, 25.0, 700.0, 12_000.0] {
            let gap = SheetGridRenderer.spacing(metresPerPoint: metresPerPoint)
            let digit = gap / pow(10, floor(log10(gap)))
            #expect([1.0, 2.0, 5.0, 10.0].contains { abs($0 - digit) < 1e-9 }, Comment(rawValue: "\(metresPerPoint)"))
            #expect(gap / metresPerPoint >= 70 - 1e-6, Comment(rawValue: "\(metresPerPoint)"))
            #expect(gap / metresPerPoint < 70 * 2.6, Comment(rawValue: "\(metresPerPoint)"))
        }
    }

    @Test func onlyTheSurveyHasAGridAndTheWatercolourAWash() {
        #expect(MapStyle.survey.gridInk != nil)
        for style in [MapStyle.dark, .parchment, .watercolour] { #expect(style.gridInk == nil, Comment(rawValue: style.id)) }
        #expect(MapStyle.watercolour.wash != nil)
        for style in [MapStyle.dark, .parchment, .survey] { #expect(style.wash == nil, Comment(rawValue: style.id)) }
    }

    @Test func aWatercolourRealmBorderIsNotTakenForARoad() {
        let border = MapStyle.watercolour.style(forPlaceType: "Region")
        let road = MapStyle.watercolour.style(forPlaceType: "Road")
        #expect(border.isDashed && !road.isDashed)
        #expect(border.stroke != road.stroke)
    }
}
