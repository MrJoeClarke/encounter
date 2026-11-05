//
//  PaperSpeedTests.swift
//  encounterTests
//

import Foundation
import CoreGraphics
import Testing
@testable import encounter

struct PaperSpeedTests {
    private let map: PaperTexture.Area = (0, 0, 100_000, 100_000)
    private let ground = (red: 0.93, green: 0.87, blue: 0.73)

    private func pixels(_ image: CGImage) -> [UInt8] {
        guard let data = image.dataProvider?.data else { return [] }
        return Array(data as Data)
    }

    @Test func aTileIsQuickOnceThePaperHasBeenMade() throws {
        let paper = PaperTexture()
        let area: PaperTexture.Area = (10_000, 10_000, 10_000 + 6_000, 10_000 + 6_000)
        // The first tile makes the picture of the fine look; the next ones only use it.
        _ = paper.tile(ground: ground, area: area, map: map, size: 512)
        let started = Date()
        for k in 1...6 { _ = paper.tile(ground: ground, area: (area.minEasting + Double(k) * 6_000, area.minNorthing, area.maxEasting + Double(k) * 6_000, area.maxNorthing), map: map, size: 512) }
        let each = Date().timeIntervalSince(started) / 6
        #expect(each < 0.5, "a tile took \(each) seconds")
    }

    @Test func tilesSideBySideJoinWithoutASeam() throws {
        let paper = PaperTexture()
        let size = 128
        let left = try #require(paper.tile(ground: ground, area: (20_000, 20_000, 26_000, 26_000), map: map, size: size))
        let right = try #require(paper.tile(ground: ground, area: (26_000, 20_000, 32_000, 26_000), map: map, size: size))
        let a = pixels(left), b = pixels(right)
        // The last column of one and the first of the next are a pixel apart, so they should be as alike as neighbours in a tile are.
        var seam = 0.0, inside = 0.0
        for row in 0..<size {
            for channel in 0..<3 {
                seam += abs(Double(a[(row * size + size - 1) * 4 + channel]) - Double(b[row * size * 4 + channel]))
                inside += abs(Double(a[(row * size + size - 2) * 4 + channel]) - Double(a[(row * size + size - 1) * 4 + channel]))
            }
        }
        #expect(seam < inside * 2.5 + 50, "seam \(seam) against \(inside) inside a tile")
    }
}
