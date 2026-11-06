//
//  MapLetteringTests.swift
//  encounterTests
//

import Foundation
import CoreGraphics
import ImageIO
import SwiftData
import Testing
@testable import encounter

struct MapLetteringTests {
    private func line(_ text: String, _ x: Double, _ y: Double, width: Double = 200, height: Double = 30) -> MapLettering.Line {
        MapLettering.Line(text: text, x: x, y: y, width: width, height: height)
    }

    @Test func wordsSaySWhatSortOfAreaANameIs() {
        #expect(MapLettering.type(of: "The Bare Mountains") == .mountains)
        #expect(MapLettering.type(of: "The Dark Forest") == .forest)
        #expect(MapLettering.type(of: "The Great Sea") == .water)
        #expect(MapLettering.type(of: "The Marshes") == .wilderness)
        #expect(MapLettering.type(of: "Danus Gorge") == .wilderness)
        #expect(MapLettering.type(of: "Smyrna") == nil)
        // A word that only contains one of these is not one of them.
        #expect(MapLettering.type(of: "Seaford") == nil)
    }

    @Test func capitalsAreTidiedAndMarksRemoved() {
        #expect(MapLettering.tidy("ARDEN") == "Arden")
        #expect(MapLettering.tidy("PAN'DONIA") == "Pan'donia")
        #expect(MapLettering.tidy("Smyrna.") == "Smyrna")
        #expect(MapLettering.tidy("Hendu") == "Hendu")
    }

    @Test func lettersReadInPiecesAreJoinedButSmallWordsOfANameAreNot() {
        #expect(MapLettering.mended("Moel fan") == "Moelfan")
        #expect(MapLettering.mended("Danus Gor ge") == "Danus Gorge")
        #expect(MapLettering.mended("Isle of Mist") == "Isle of Mist")
        #expect(MapLettering.mended("Port de la Mer") == "Port de la Mer")
        let labels = MapLettering.labels(from: [line("Danus Gor ge", 100, 100)])
        #expect(labels.first?.name == "Danus Gorge")
        #expect(labels.first?.type == .wilderness)
    }

    @Test func nameInCapitalsAreMarkedAsSuch() {
        let labels = MapLettering.labels(from: [line("SCUTAR", 100, 100), line("Smyrna", 100, 400)])
        #expect(labels.first { $0.name == "Scutar" }?.isCapitals == true)
        #expect(labels.first { $0.name == "Smyrna" }?.isCapitals == false)
    }

    @Test func aSecondLineStartingWithTheIsWhatTheFirstMeans() {
        let labels = MapLettering.labels(from: [line("Moelfan", 200, 190), line("The Bare Mountains", 210, 228)])
        #expect(labels.count == 1)
        #expect(labels.first?.name == "Moelfan")
        #expect(labels.first?.description == "The Bare Mountains")
        #expect(labels.first?.type == .mountains)
    }

    @Test func twoLinesOfOneNameAreJoinedAndFarApartLinesAreNot() {
        let joined = MapLettering.labels(from: [line("Danus", 1100, 610, width: 90), line("Gorge", 1120, 640, width: 90)])
        #expect(joined.map(\.name) == ["Danus Gorge"])
        let apart = MapLettering.labels(from: [line("Smyrna", 1000, 400), line("Ragusa", 1600, 710)])
        #expect(apart.count == 2)
    }

    @Test func marksAndSpecklesAreNotNames() {
        #expect(MapLettering.labels(from: [line("..:", 10, 10), line("12", 50, 50), line("~~|", 80, 80)]).isEmpty)
    }

    // MARK: Giving the names to the areas

    private func square(_ x: Double, _ y: Double, _ side: Double) -> [GridPoint] {
        [GridPoint(easting: x, northing: y), GridPoint(easting: x + side, northing: y), GridPoint(easting: x + side, northing: y + side), GridPoint(easting: x, northing: y + side)]
    }

    /// A picture 1000 by 500 pixels at a metre a pixel with two colours: mountains-coloured on the left (two pieces) and land on the right.
    private func trace() -> (MapTrace, MapCalibration) {
        let calibration = MapCalibration(anchoringPixel: (0, 500), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 1)!
        var labels = [Int16](repeating: 1, count: 100 * 50)
        // Working picture 100 by 50: colour 0 is the left 40 columns, in the top half (piece one), and a block lower down (piece two).
        for row in 0..<50 { for column in 0..<40 { if row >= 25 && row < 50 { labels[row * 100 + column] = 0 } } }
        for row in 0..<10 { for column in 0..<10 { labels[row * 100 + column] = 0 } }
        let mountains = TracedColour(
            id: 0, red: 0.5, green: 0.4, blue: 0.3, share: 0.2, isThin: false, type: .mountains, name: "Mountains 1",
            outlines: [square(0, 250, 400), square(0, 0, 100)]
        )
        let land = TracedColour(
            id: 1, red: 0.8, green: 0.7, blue: 0.4, share: 0.8, isThin: false, type: .region, name: "Realm 1",
            outlines: [square(400, 0, 600)]
        )
        return (MapTrace(colours: [mountains, land], width: 1000, height: 500, labels: labels, workingWidth: 100, workingHeight: 50), calibration)
    }

    @Test func aNameWithItsWordsNamesThePieceItIsOnAndSaysWhatItIs() {
        let (trace, calibration) = trace()
        // "The Dark Forest" is on the top-left piece (pixel y 100 is north 400), a forest by its words in a colour guessed as mountains.
        let labels = [MapLabel(name: "Hendu", description: "The Dark Forest", x: 200, y: 100, height: 30, type: .forest)]
        let named = MapTracer.attach(labels, to: trace, calibration: calibration)
        #expect(named.colours[0].named[0]?.name == "Hendu")
        #expect(named.colours[0].named[0]?.summary == "The Dark Forest")
        // The biggest piece says what the colour is.
        #expect(named.colours[0].type == .forest)
        #expect(named.colours[0].named[1] == nil)
    }

    @Test func plainLetteringNamesLandOnlyWhenItIsBiggerThanMostOfTheLettering() {
        let (trace, calibration) = trace()
        let small = MapLabel(name: "Smyrna", description: "", x: 700, y: 250, height: 20, type: nil)
        let realm = MapLabel(name: "Arden", description: "", x: 650, y: 300, height: 40, type: nil)
        let other = MapLabel(name: "Ragusa", description: "", x: 800, y: 200, height: 20, type: nil)
        let named = MapTracer.attach([small, other, realm], to: trace, calibration: calibration)
        #expect(named.colours[1].named[0]?.name == "Arden")
        let none = MapTracer.attach([small, other], to: trace, calibration: calibration)
        #expect(none.colours[1].named.isEmpty)
    }

    @Test func aPieceWithAnotherTypeKeepsItsOwn() {
        let (trace, calibration) = trace()
        // The small piece is a gorge (wilderness), in the mountains' colour.
        let labels = [
            MapLabel(name: "Moelfan", description: "The Bare Mountains", x: 200, y: 100, height: 30, type: .mountains),
            MapLabel(name: "Danus Gorge", description: "", x: 50, y: 450, height: 30, type: .wilderness),
        ]
        let named = MapTracer.attach(labels, to: trace, calibration: calibration)
        #expect(named.colours[0].type == .mountains)
        #expect(named.colours[0].named[1]?.type == .wilderness)
        #expect(named.colours[0].named[0]?.type == nil)
    }
}

@MainActor
struct NamedPlacesTests {
    private func square(_ x: Double, _ y: Double, _ side: Double = 1000) -> [GridPoint] {
        [GridPoint(easting: x, northing: y), GridPoint(easting: x + side, northing: y), GridPoint(easting: x + side, northing: y + side), GridPoint(easting: x, northing: y + side)]
    }

    private func setUp() throws -> (World, WorldMap, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        let map = WorldMap(name: "Picture", imageData: Data(), kind: .world)
        map.world = world
        map.place = world.ensureRootPlace(in: context)
        context.insert(map)
        return (world, map, context)
    }

    @Test func namedPiecesBecomePlacesWithTheirNamesTypesAndDescriptions() throws {
        let (world, map, context) = try setUp()
        let colour = TracedColour(
            id: 0, red: 0.5, green: 0.4, blue: 0.3, share: 0.2, isThin: false, type: .mountains, name: "Mountains 1",
            outlines: [square(0, 0), square(3000, 0), square(6000, 0), square(9000, 0)],
            named: [
                0: TracedName(name: "Moelfan", summary: "The Bare Mountains", type: nil),
                1: TracedName(name: "Beligora", summary: "The White Mountains", type: nil),
                2: TracedName(name: "Danus Gorge", summary: "", type: .wilderness),
            ]
        )
        world.addTracedPlaces(from: [colour], for: map, in: context)
        let made = (world.pages ?? []).filter { $0.wasTraced }
        // Three named places, and the unnamed piece goes with the colour's own name since there is more than one name.
        #expect(Set(made.map(\.title)) == ["Moelfan", "Beligora", "Danus Gorge", "Mountains 1"])
        let gorge = try #require(made.first { $0.title == "Danus Gorge" })
        #expect(gorge.attributeText("core.placeType") == "Wilderness")
        #expect(made.first { $0.title == "Moelfan" }?.summary == "The Bare Mountains")
    }

    @Test func aColourWithOneNameGivesItsOtherPiecesToThatPlace() throws {
        let (world, map, context) = try setUp()
        let colour = TracedColour(
            id: 0, red: 0.8, green: 0.5, blue: 0.5, share: 0.2, isThin: false, type: .region, name: "Realm 1",
            outlines: [square(0, 0, 5000), square(8000, 0, 500)], named: [0: TracedName(name: "Arden", summary: "", type: nil)]
        )
        world.addTracedPlaces(from: [colour], for: map, in: context)
        let made = (world.pages ?? []).filter { $0.wasTraced }
        #expect(made.map(\.title) == ["Arden"])
        if case .multiPolygon(let pieces)? = made.first?.geometry { #expect(pieces.count == 2) } else { Issue.record("expected an island with the realm") }
    }
}

/// What the lettering of the sample picture gives, if the picture is there. Text recognition is the system's, so the numbers are loose.
struct MapLetteringSampleTests {
    @Test func theSampleContinentsLetteringIsReadAndNamesTheLand() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/KnownContinent.png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let calibration = MapCalibration(anchoringPixel: (0, Double(image.height)), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 100)!
        var settings = MapTracer.Settings()
        settings.workingSize = 800
        let areas = try #require(MapTracer.trace(image: image, calibration: calibration, settings: settings))
        let started = Date()
        let lines = MapLettering.read(image)
        let labels = MapLettering.labels(from: lines)
        print("LETTERS read \(lines.count) lines in \(Date().timeIntervalSince(started)) s")
        for label in labels { print("LETTERS label '\(label.name)' / '\(label.description)' type \(String(describing: label.type)) height \(Int(label.height)) at \(Int(label.x)),\(Int(label.y))") }
        let named = MapTracer.attach(labels, to: areas, calibration: calibration)
        for colour in named.colours where !colour.outlines.isEmpty {
            print("LETTERS colour \(Int(colour.red * 255)),\(Int(colour.green * 255)),\(Int(colour.blue * 255)) is \(colour.type) pieces \(colour.outlines.count) names \(colour.named.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value.name) [\(String(describing: $0.value.type))]" })")
        }
        let withLines = MapLines.add(to: named, lettering: lines, labels: labels, calibration: calibration)
        for line in withLines.lines {
            let length = zip(line.points, line.points.dropFirst()).reduce(0.0) { $0 + hypot($1.1.easting - $1.0.easting, $1.1.northing - $1.0.northing) }
            print("LETTERS line \(line.kind) '\(line.name)' named \(line.isNamed) points \(line.points.count) length \(Int(length / 100)) px")
        }
        #expect(!lines.isEmpty)
    }
}
