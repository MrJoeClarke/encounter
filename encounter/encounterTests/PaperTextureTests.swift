//
//  PaperTextureTests.swift
//  encounterTests
//

import CoreGraphics
import Testing
@testable import encounter

struct PaperTextureTests {
    private let paper = PaperTexture()
    private let map: PaperTexture.Area = (0, 0, 10_000, 10_000)

    @Test func theSamePlaceHasTheSamePaperWhateverTileItIsIn() {
        // Two tiles side by side: the last column of the left one and the first of the right one are a pixel apart, so are alike.
        let a = paper.tint(easting: 4_999, northing: 5_000, in: map)
        let b = paper.tint(easting: 5_001, northing: 5_000, in: map)
        #expect(abs(a.red - b.red) < 0.01)
        #expect(paper.grain(atPixelX: 40, y: 12) == paper.grain(atPixelX: 40, y: 12))
        let first = paper.tint(easting: 3_210, northing: 7_654, in: map), second = paper.tint(easting: 3_210, northing: 7_654, in: map)
        #expect(first.red == second.red && first.blue == second.blue)
    }

    @Test func theEdgeAndBeyondItAreDarkerThanTheMiddle() {
        let middle = paper.tint(easting: 5_000, northing: 5_000, in: map)
        let nearEdge = paper.tint(easting: 100, northing: 5_000, in: map)
        let beyond = paper.tint(easting: -3_000, northing: 5_000, in: map)
        #expect(nearEdge.red < middle.red)
        #expect(beyond.red < middle.red)
        // It burns brown: blue goes further than red.
        #expect(beyond.blue < beyond.red)
    }

    @Test func thePaperStaysCloseToTheGroundInTheMiddle() {
        var total = 0.0, count = 0.0
        for i in 0..<20 { for j in 0..<20 {
            total += paper.tint(easting: 2_000 + Double(i) * 300, northing: 2_000 + Double(j) * 300, in: map).red
            count += 1
        } }
        #expect(abs(total / count - 1) < 0.1)
    }

    @Test func grainIsSmallAndAlwaysThere() {
        let values = (0..<200).map { paper.grain(atPixelX: $0, y: $0 * 3) }
        #expect(values.allSatisfy { abs($0 - 1) <= paper.grain + 0.0001 })
        #expect(Set(values).count > 50)
    }

    @Test func aTileIsMadeAtTheRightSize() throws {
        let image = try #require(paper.tile(ground: (0.9, 0.85, 0.7), area: (0, 0, 1_000, 1_000), map: map, size: 64))
        #expect(image.width == 64 && image.height == 64)
    }

    @Test func everyStyleButDarkHasPaperAndLettering() {
        for style in [MapStyle.parchment, .survey, .watercolour] {
            #expect(style.paper != nil && style.lettering != nil, Comment(rawValue: style.id))
        }
        #expect(MapStyle.dark.paper == nil && MapStyle.dark.lettering == nil)
    }

    @Test func eachStylesPaperIsItsOwn() {
        #expect(MapStyle.parchment.paper != MapStyle.survey.paper)
        #expect(MapStyle.survey.paper != MapStyle.watercolour.paper)
        // A survey's paper is plain: no stains, no burnt edge.
        #expect(MapStyle.survey.paper?.stain == 0 && MapStyle.survey.paper?.edge == 0)
    }
}
