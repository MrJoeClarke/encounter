//
//  MapTypeGuesserTests.swift
//  encounterTests
//

import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import encounter

struct MapTypeGuesserTests {
    @Test func coloursAreDescribedInWordsForTheModel() {
        #expect(MapTypeGuesser.describe(red: 0.2, green: 0.45, blue: 0.5).contains("blue"))
        #expect(MapTypeGuesser.describe(red: 0.2, green: 0.5, blue: 0.2).contains("green"))
        #expect(MapTypeGuesser.describe(red: 0.05, green: 0.05, blue: 0.05) == "black")
        #expect(MapTypeGuesser.describe(red: 0.93, green: 0.93, blue: 0.93).contains("white") || MapTypeGuesser.describe(red: 0.93, green: 0.93, blue: 0.93).contains("grey"))
    }

    @Test func theGuessIsNotUsedUntilItHasBeenShownToHelp() {
        // Switch this on only with the comparison below showing the model better than the rules.
        #expect(MapTypeGuesser.isUsed == false)
    }
}

/// Compares the model's guesses with the colour rules on the sample continent, where the answers are known from looking at it. Runs the
/// real model, so only where there is one and RUN_MODEL_TESTS is set (it takes a while), and prints what each said.
struct MapTypeGuesserModelTests {
    static let canRun = ProcessInfo.processInfo.environment["RUN_MODEL_TESTS"] != nil && RootLanguageDrafter.availability == .available

    @Test(.enabled(if: MapTypeGuesserModelTests.canRun), .timeLimit(.minutes(10)))
    func theModelAgainstTheRulesOnTheSampleContinent() async throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Samples/KnownContinent.png")
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return }
        let calibration = MapCalibration(anchoringPixel: (0, Double(image.height)), at: GridPoint(easting: 0, northing: 0), metresPerPixel: 100)!
        var settings = MapTracer.Settings()
        settings.workingSize = 1200
        let areas = try #require(MapTracer.trace(image: image, calibration: calibration, settings: settings))
        let read = MapLettering.read(image)
        let labels = MapLettering.labels(from: read)
        let named = MapTracer.attach(labels, to: areas, calibration: calibration)

        // What each main colour is, from looking at the picture.
        let truth: [(rgb: (Double, Double, Double), type: TracedType)] = [
            ((141, 114, 84), .mountains), ((190, 147, 111), .region), ((205, 178, 100), .region),
            ((127, 184, 126), .region), ((53, 117, 142), .water), ((49, 104, 114), .water), ((117, 135, 51), .forest),
        ]
        func answer(for colour: TracedColour) -> TracedType? {
            truth.min { distance($0.rgb, colour) < distance($1.rgb, colour) }.flatMap { distance($0.rgb, colour) < 60 ? $0.type : nil }
        }
        func distance(_ rgb: (Double, Double, Double), _ colour: TracedColour) -> Double {
            abs(rgb.0 - colour.red * 255) + abs(rgb.1 - colour.green * 255) + abs(rgb.2 - colour.blue * 255)
        }
        let colours = named.areaColours.filter { answer(for: $0) != nil }
        var bare = colours
        for i in bare.indices { bare[i].named = [:] }

        // The rules, from colour alone; and the model, from colour alone and with the names.
        var rulesRight = 0, modelBareRight = 0, modelNamedRight = 0, namedRulesRight = 0
        let modelBare = await MapTypeGuesser.guess(for: bare) ?? [:]
        let modelNamed = await MapTypeGuesser.guess(for: colours) ?? [:]
        for colour in colours {
            let truth = answer(for: colour)
            let lab = Lab.lab(red: colour.red, green: colour.green, blue: colour.blue)
            let rules = MapTracer.guess(l: Float(lab.l), a: Float(lab.a), b: Float(lab.b))
            if rules == truth { rulesRight += 1 }
            if colour.type == truth { namedRulesRight += 1 }
            if modelBare[colour.id] == truth { modelBareRight += 1 }
            if modelNamed[colour.id] == truth { modelNamedRight += 1 }
            print("GUESS colour \(Int(colour.red * 255)),\(Int(colour.green * 255)),\(Int(colour.blue * 255)) truth \(String(describing: truth)) rules \(rules) rules+names \(colour.type) model \(String(describing: modelBare[colour.id])) model+names \(String(describing: modelNamed[colour.id]))")
        }
        print("GUESS of \(colours.count): rules by colour \(rulesRight), rules with names \(namedRulesRight), model by colour \(modelBareRight), model with names \(modelNamedRight)")
    }
}
