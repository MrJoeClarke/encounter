//
//  ScaleBarTests.swift
//  encounterTests
//

import Foundation
import Testing
@testable import encounter

struct ScaleBarTests {
    @Test func theBarIsARoundLengthThatFits() throws {
        // 600 metres a point: 130 points is 78 km, which is 48 miles, so the bar is 20 miles.
        let bar = try #require(ScaleBar.length(metresPerPoint: 600, unit: .miles))
        #expect(bar.value == 20)
        #expect(bar.points <= 130 && bar.points > 130 / 2.5)
    }

    @Test func theBarIsAOneTwoOrFiveEverywhere() throws {
        for metres in [0.05, 0.3, 2.0, 17.0, 250.0, 4_000.0, 90_000.0] {
            for unit in [DistanceUnit.miles, .kilometres, .yards, .feet] {
                let bar = try #require(ScaleBar.length(metresPerPoint: metres, unit: unit))
                let digit = bar.value / pow(10, floor(log10(bar.value)))
                #expect([1.0, 2.0, 5.0].contains { abs($0 - digit) < 1e-9 }, Comment(rawValue: "\(metres) \(unit)"))
                #expect(bar.points <= 130.0001, Comment(rawValue: "\(metres) \(unit)"))
            }
        }
    }

    @Test func noReadingMeansNoBar() {
        #expect(ScaleBar.length(metresPerPoint: 0, unit: .miles) == nil)
        #expect(ScaleBar.length(metresPerPoint: .infinity, unit: .miles) == nil)
    }
}
