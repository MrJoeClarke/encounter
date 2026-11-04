//
//  MapStyleTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

struct MapStyleTests {
    @Test func thereAreFourStylesAndDarkIsTheDefault() {
        #expect(MapStyle.all.map(\.id) == ["dark", "parchment", "survey", "watercolour"])
        #expect(MapStyle.defaultID == "dark" && MapStyle.style(id: "").id == "dark" && MapStyle.style(id: "nonsense").id == "dark")
        #expect(MapStyle.style(id: "watercolour").title == "Watercolour")
    }

    @Test func darkIsTheLookMapsHaveAlwaysHad() {
        for type in PlaceStyle.types + ["Unknown", ""] {
            #expect(MapStyle.dark.style(forPlaceType: type) == PlaceStyle.style(forPlaceType: type), Comment(rawValue: type))
        }
    }

    @Test func everyStyleDrawsEveryTypeInTheSameLayerAsDark() {
        for style in MapStyle.all {
            for type in PlaceStyle.types {
                #expect(style.style(forPlaceType: type).drawOrder == PlaceStyle.style(forPlaceType: type).drawOrder, Comment(rawValue: "\(style.id) \(type)"))
            }
        }
    }

    @Test func eachStyleLooksDifferent() {
        for style in MapStyle.all.dropFirst() {
            #expect(style.background != MapStyle.dark.background, Comment(rawValue: style.id))
            // The main things on a map have a look of their own, not the dark one.
            for type in ["Water", "Forest", "Mountains", "River", "Road", "Building"] {
                #expect(style.style(forPlaceType: type) != PlaceStyle.style(forPlaceType: type), Comment(rawValue: "\(style.id) \(type)"))
            }
        }
        // The light styles are light, the dark one is dark.
        func brightness(_ c: StyleColor) -> Double { (c.red + c.green + c.blue) / 3 }
        #expect(brightness(MapStyle.dark.background) < 0.3)
        for id in ["parchment", "survey", "watercolour"] { #expect(brightness(MapStyle.style(id: id).background) > 0.7, Comment(rawValue: id)) }
    }
}

@MainActor
struct MapStyleChoiceTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Aldara")
        context.insert(world)
        world.ensureRootPlace(in: context)
        return (world, context)
    }

    @Test func aMapFollowsTheWorldUnlessItHasItsOwnStyle() throws {
        let (world, context) = try makeWorld()
        let root = try #require(world.rootPlace)
        let map = try #require(world.addVectorMap(named: "Map", for: root, extentMetres: 1_000, kind: .world, in: context))
        #expect(map.style.id == "dark")
        world.mapStyleID = "parchment"
        #expect(map.style.id == "parchment")
        map.styleID = "survey"
        #expect(map.style.id == "survey")
        map.styleID = ""
        #expect(map.style.id == "parchment")
        // A style this version doesn't know is the default.
        world.mapStyleID = "something-newer"
        #expect(map.style.id == "dark")
    }

    @Test func theChoicesAreKeptAndSurviveExportAndImport() async throws {
        let (world, context) = try makeWorld()
        world.mapStyleID = "watercolour"
        let root = try #require(world.rootPlace)
        let map = try #require(world.addVectorMap(named: "Map", for: root, extentMetres: 1_000, kind: .world, in: context))
        map.styleID = "survey"
        try context.save()
        let wrapper = try WorldPackage.fileWrapper(for: WorldExporter.makeContents(of: world))
        let contents = try WorldPackage.contents(of: wrapper)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        #expect(imported.mapStyleID == "watercolour")
        #expect((imported.maps ?? []).first?.styleID == "survey")
    }
}
