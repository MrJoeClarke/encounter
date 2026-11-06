//
//  WindowRouteTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct WindowRouteTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        return (world, context)
    }

    @Test func aRouteSurvivesBeingSavedAndRead() throws {
        let route = WindowRoute(worldID: UUID(), screen: .kind("character"), pageID: UUID(), mapID: nil, campaignID: nil, libraryKey: "srd.spell.fireball", showsSheet: true)
        let data = try JSONEncoder().encode(route)
        #expect(try JSONDecoder().decode(WindowRoute.self, from: data) == route)
        for screen in [WindowRoute.Screen.home, .worldMap, .timeline, .campaigns, .library, .kind("place")] {
            let one = WindowRoute(worldID: UUID(), screen: screen)
            #expect(try JSONDecoder().decode(WindowRoute.self, from: JSONEncoder().encode(one)) == one)
        }
    }

    @Test func aPageOpenedInOneWindowIsTheSamePageInAnother() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        let first = WorldNavigation()
        first.open(page)
        first.showsSheet = true
        let route = first.route(in: world)
        #expect(route.pageID == page.id)
        #expect(route.showsSheet)

        let second = WorldNavigation()
        second.apply(route, in: world)
        #expect(second.selectedPage === page)
        #expect(second.selection == .kind(.character))
        #expect(second.showsSheet)
    }

    @Test func aRouteFromAPageAndFromAMapNameThem() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let page = world.addPage(kind: .place, in: context)
        let map = try #require(world.addVectorMap(named: "Town", for: page, extentMetres: 1_000, kind: .settlement, in: context))
        let pageRoute = try #require(WindowRoute.page(page, showsSheet: false))
        #expect(pageRoute.screen == .kind("place") && pageRoute.pageID == page.id)
        let mapRoute = try #require(WindowRoute.map(map))
        #expect(mapRoute.screen == .worldMap && mapRoute.mapID == map.id)

        let navigation = WorldNavigation()
        navigation.apply(mapRoute, in: world)
        #expect(navigation.selection == .worldMap)
        #expect(navigation.selectedMap === map)
        _ = root
    }

    @Test func whatHasBeenDeletedSinceIsLeftOutNotFailedOn() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        let navigation = WorldNavigation()
        navigation.open(page)
        let route = navigation.route(in: world)
        context.delete(page)
        try context.save()

        let restored = WorldNavigation()
        restored.apply(route, in: world)
        // The list of characters shows, with nothing open.
        #expect(restored.selection == .kind(.character))
        #expect(restored.selectedPage == nil)
    }

    @Test func homeAndTheWorldMapAreRestoredToo() throws {
        let (world, _) = try makeWorld()
        let navigation = WorldNavigation()
        navigation.choose(.timeline)
        let timeline = navigation.route(in: world)
        #expect(timeline.screen == .timeline)
        let other = WorldNavigation()
        other.apply(timeline, in: world)
        #expect(other.selection == .timeline)
        other.apply(WindowRoute(worldID: world.id), in: world)
        #expect(other.selection == .home)
    }
}
