//
//  MapTracerTests.swift
//  encounterTests
//

import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import encounter

/// Pictures drawn here, with known answers, for the tracer to find the colours and areas of.
struct MapTracerTests {
    private typealias Colour = (UInt8, UInt8, UInt8)
    private let pink: Colour = (236, 190, 200)
    private let blue: Colour = (150, 190, 225)
    private let green: Colour = (60, 120, 70)
    private let ink: Colour = (30, 25, 25)
    private let width = 400, height = 300

    /// A picture: pink land with a blue sea on the left, a green forest in a corner of the land, a thin dark outline between sea and
    /// land, a dark surround, and a little noise over all of it, as paper has. Pixels run from the top.
    private func picture(river: Bool = false, roads: Bool = false) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        func set(_ x: Int, _ y: Int, _ c: Colour) {
            guard x >= 0, y >= 0, x < width, y < height else { return }
            let noise = Int((UInt64(x) &* 374761393 ^ UInt64(y) &* 668265263) % 9) - 4
            let i = (y * width + x) * 4
            bytes[i] = UInt8(min(255, max(0, Int(c.0) + noise)))
            bytes[i + 1] = UInt8(min(255, max(0, Int(c.1) + noise)))
            bytes[i + 2] = UInt8(min(255, max(0, Int(c.2) + noise)))
        }
        for y in 0..<height {
            for x in 0..<width {
                var c = pink
                if x < 140 { c = blue }
                if x >= 140 && x < 143 { c = ink }
                if x >= 260 && x < 360 && y >= 150 && y < 250 { c = green }
                if x < 12 || y < 12 || x >= width - 12 || y >= height - 12 { c = ink }
                if river && y >= 100 && y < 102 && x >= 143 && x < 388 { c = blue }
                if roads {
                    let brown: Colour = (110, 80, 50)
                    if y >= 200 && y < 203 && x >= 150 && x < 380 { c = brown }
                    if x >= 200 && x < 203 && y >= 203 && y < 280 { c = brown }
                }
                set(x, y, c)
            }
        }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        return try #require(CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
    }

    /// Ten metres to a pixel, with the bottom left of the picture at the origin.
    private var calibration: MapCalibration {
        MapCalibration(anchoringPixel: (0, Double(height)), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 10)!
    }

    private func area(_ outline: [GridPoint]) -> Double { Plane.signedArea(outline.map { V(x: $0.easting, y: $0.northing) }) }

    private func colour(near c: Colour, in trace: MapTrace) -> TracedColour? {
        trace.colours.min { distance($0, c) < distance($1, c) }.flatMap { distance($0, c) < 40 ? $0 : nil }
    }

    private func distance(_ t: TracedColour, _ c: Colour) -> Double {
        abs(t.red * 255 - Double(c.0)) + abs(t.green * 255 - Double(c.1)) + abs(t.blue * 255 - Double(c.2))
    }

    @Test func findsTheMainColoursAndGuessesWhatTheyAre() throws {
        let trace = try #require(MapTracer.trace(image: try picture(), calibration: calibration))
        let sea = try #require(colour(near: blue, in: trace))
        let land = try #require(colour(near: pink, in: trace))
        let forest = try #require(colour(near: green, in: trace))
        #expect(sea.type == .water)
        #expect(land.type == .region)
        #expect(forest.type == .forest)
        // The dark outline and surround are not areas to make places of.
        #expect(trace.areaColours.count == 3, "found \(trace.areaColours.map(\.type))")
    }

    @Test func tracesEachAreaWhereItIs() throws {
        let trace = try #require(MapTracer.trace(image: try picture(), calibration: calibration))
        let forest = try #require(colour(near: green, in: trace))
        let outline = try #require(forest.outlines.first)
        // 100 by 100 pixels, at 10 metres a pixel.
        #expect(abs(area(outline) - 100 * 100 * 100) < 100 * 100 * 100 * 0.08, "area \(area(outline))")
        #expect(forest.outlines.count == 1)
        // It is where the forest is: east 2,600 to 3,600 metres, north from 500 to 1,500 (the picture is 3,000 metres tall).
        let east = outline.map(\.easting), north = outline.map(\.northing)
        #expect(abs((east.min() ?? 0) - 2600) < 80 && abs((east.max() ?? 0) - 3600) < 80)
        #expect(abs((north.min() ?? 0) - 500) < 80 && abs((north.max() ?? 0) - 1500) < 80)
    }

    @Test func areasMeetAtTheirSharedBorder() throws {
        let trace = try #require(MapTracer.trace(image: try picture(), calibration: calibration))
        let sea = try #require(colour(near: blue, in: trace))
        let land = try #require(colour(near: pink, in: trace))
        // The sea and the land have the thin outline between them, which goes to both, so there is no gap.
        let seaEast = (sea.outlines.first ?? []).map(\.easting).max() ?? 0
        let landWest = (land.outlines.first ?? []).map(\.easting).min() ?? 0
        #expect(abs(seaEast - landWest) < 25, "sea ends at \(seaEast), land starts at \(landWest)")
    }

    @Test func aThinLineIsNotAnAreaAndDoesNotCutOneInTwo() throws {
        let trace = try #require(MapTracer.trace(image: try picture(river: true), calibration: calibration))
        let land = try #require(colour(near: pink, in: trace))
        #expect(land.outlines.count == 1, "the land was found in \(land.outlines.count) pieces")
        #expect(trace.areaColours.count == 3)
    }

    @Test func theDarkSurroundIsLeftOut() throws {
        let trace = try #require(MapTracer.trace(image: try picture(), calibration: calibration))
        // The land does not reach the edge of the picture: it stops at the surround, 12 pixels (120 metres) in.
        let land = try #require(colour(near: pink, in: trace))
        let outline = try #require(land.outlines.first)
        #expect((outline.map(\.northing).max() ?? 0) < 3000 - 80)
        #expect((outline.map(\.easting).max() ?? 0) < 4000 - 80)
    }

    @Test func aPlainPictureGivesOneArea() throws {
        var bytes = [UInt8](repeating: 200, count: 100 * 100 * 4)
        for i in stride(from: 3, to: bytes.count, by: 4) { bytes[i] = 255 }
        let provider = try #require(CGDataProvider(data: Data(bytes) as CFData))
        let image = try #require(CGImage(
            width: 100, height: 100, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 400, space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        ))
        let trace = try #require(MapTracer.trace(image: image, calibration: calibration))
        #expect(trace.areaColours.count == 1)
    }

    /// The picture of a sample map in `Samples/`, if it is there (it is kept out of some copies of the repository).
    private func sample(_ name: String) throws -> CGImage? {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/\(name)")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    @Test func theSampleContinentGivesItsSeaAndRealms() throws {
        guard let image = try sample("KnownContinent.png") else { return }
        let calibration = MapCalibration(anchoringPixel: (0, Double(image.height)), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 100)!
        let started = Date()
        // A smaller working size, so the test is quick in a debug build.
        var settings = MapTracer.Settings()
        settings.workingSize = 800
        let trace = try #require(MapTracer.trace(image: image, calibration: calibration, settings: settings))
        print("TRACE \(image.width)x\(image.height) in \(Date().timeIntervalSince(started)) s")
        for c in trace.colours {
            print("TRACE colour \(Int(c.red * 255)),\(Int(c.green * 255)),\(Int(c.blue * 255)) share \(String(format: "%.3f", c.share)) thin \(c.isThin) type \(c.type) pieces \(c.outlines.count) points \(c.outlines.map(\.count))")
        }
        #expect(trace.areaColours.contains { $0.type == .water })
        #expect(trace.areaColours.count >= 3)
    }

    @Test func aRiverAndRoadsAreFollowedAlongTheirCentres() throws {
        let image = try picture(river: true, roads: true)
        let trace = try #require(MapTracer.trace(image: image, calibration: calibration))
        let lines = MapLines.find(in: trace, lettering: [], calibration: calibration)
        let rivers = lines.filter { $0.kind == .river }, roads = lines.filter { $0.kind == .road }
        #expect(rivers.count == 1, "rivers \(rivers.count)")
        let river = try #require(rivers.first)
        // 2 pixels thick at 100 to 102 from the top, so its centre is north (300 - 101) pixels, of 10 metres each.
        #expect(river.points.allSatisfy { abs($0.northing - 1990) < 60 })
        #expect(abs((river.points.map(\.easting).min() ?? 0) - 1430) < 120 && abs((river.points.map(\.easting).max() ?? 0) - 3880) < 120)
        // The road with a branch from its middle: the main road goes through the junction as one line, and the branch is another.
        #expect(roads.count == 2, "roads \(roads.count)")
        let main = try #require(roads.max { $0.points.count < $1.points.count || (($0.points.map(\.easting).max() ?? 0) - ($0.points.map(\.easting).min() ?? 0)) < (($1.points.map(\.easting).max() ?? 0) - ($1.points.map(\.easting).min() ?? 0)) })
        #expect((main.points.map(\.easting).max() ?? 0) - (main.points.map(\.easting).min() ?? 0) > 2000)
    }

    @Test func lettersAreNotFollowedAsLinesAndNamesGoToTheLinesBesideThem() throws {
        let image = try picture(river: true)
        let trace = try #require(MapTracer.trace(image: image, calibration: calibration))
        // Lettering beside the river, which names it, and a name far from any line, which does not.
        let beside = MapLabel(name: "River Danus", description: "", x: 250, y: 95, height: 20, type: nil)
        let town = MapLabel(name: "Ragusa", description: "", x: 260, y: 96, height: 20, type: nil)
        let far = MapLabel(name: "Smyrna", description: "", x: 330, y: 270, height: 20, type: nil)
        let named = MapLines.add(to: trace, lettering: [], labels: [town, beside, far], calibration: calibration)
        #expect(named.lines.count == 1)
        #expect(named.lines.first?.name == "River Danus")
        #expect(named.lines.first?.isNamed == true)
        let unnamed = MapLines.add(to: trace, lettering: [], labels: [far], calibration: calibration)
        #expect(unnamed.lines.first?.name == "River 1")
    }
}
