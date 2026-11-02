//
//  NavigationHistoryTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

/// Back and Forward move through what was open in a world, like a browser, and never leave the world.
@MainActor
struct NavigationHistoryTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        return (world, context)
    }

    /// Does what the user does, and notes the change as the world's screen does when the place changes.
    private func go(_ navigation: WorldNavigation, _ action: () -> Void) {
        let old = navigation.place
        action()
        navigation.record(from: old, to: navigation.place)
    }

    /// Goes back or forward, and notes the change as the screen does.
    private func step(_ navigation: WorldNavigation, back: Bool) {
        let old = navigation.place
        if back { navigation.goBack() } else { navigation.goForward() }
        navigation.record(from: old, to: navigation.place)
    }

    @Test func backReturnsToWhatWasOpenBeforeAndForwardGoesAgain() throws {
        let (world, context) = try makeWorld()
        let place = world.addPage(kind: .place, in: context)
        let hero = world.addPage(kind: .character, in: context)
        let navigation = WorldNavigation()
        #expect(!navigation.canGoBack && !navigation.canGoForward)

        go(navigation) { navigation.open(place) }
        go(navigation) { navigation.open(hero) }
        #expect(navigation.canGoBack && !navigation.canGoForward)

        step(navigation, back: true)
        #expect(navigation.selectedPage === place && navigation.selection == .kind(.place))
        step(navigation, back: true)
        #expect(navigation.selection == .home && navigation.selectedPage == nil && !navigation.canGoBack)
        #expect(navigation.canGoForward)

        step(navigation, back: false)
        step(navigation, back: false)
        #expect(navigation.selectedPage === hero && !navigation.canGoForward)
    }

    @Test func goingBackIsNotRecordedAsANewJourney() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .place, in: context)
        let navigation = WorldNavigation()
        go(navigation) { navigation.open(page) }
        step(navigation, back: true)
        // Back then forward then back again lands in the same places, with nothing extra left behind.
        step(navigation, back: false)
        step(navigation, back: true)
        #expect(navigation.selection == .home && navigation.backStack.isEmpty && navigation.forwardStack.count == 1)
    }

    @Test func aNewJourneyForgetsWhatWasGoneBackFrom() throws {
        let (world, context) = try makeWorld()
        let first = world.addPage(kind: .place, in: context)
        let second = world.addPage(kind: .place, in: context)
        let navigation = WorldNavigation()
        go(navigation) { navigation.open(first) }
        step(navigation, back: true)
        #expect(navigation.canGoForward)
        go(navigation) { navigation.open(second) }
        #expect(!navigation.canGoForward)
        step(navigation, back: true)
        #expect(navigation.selection == .home)
    }

    @Test func aMapOpenedFromAPageGoesBackToThePage() throws {
        let (world, context) = try makeWorld()
        let town = world.addPage(kind: .place, in: context)
        let map = WorldMap(name: "Town")
        context.insert(map)
        map.world = world
        let navigation = WorldNavigation()
        go(navigation) { navigation.open(town) }
        go(navigation) { navigation.openMap(map) }
        #expect(navigation.selection == .worldMap && navigation.selectedMap === map)
        step(navigation, back: true)
        #expect(navigation.selection == .kind(.place) && navigation.selectedPage === town && navigation.selectedMap == nil)
    }

    @Test func choosingTheSameThingAgainOrSearchingAddsNothing() throws {
        let navigation = WorldNavigation()
        go(navigation) { navigation.choose(.home) }
        go(navigation) { navigation.searchText = "dragon" }
        #expect(!navigation.canGoBack)
        go(navigation) { navigation.choose(.timeline) }
        go(navigation) { navigation.choose(.timeline) }
        #expect(navigation.backStack.count == 1)
    }

    @Test func aDeletedPageIsSkippedAndHistoryIsCapped() throws {
        let (world, context) = try makeWorld()
        let gone = world.addPage(kind: .place, in: context)
        let kept = world.addPage(kind: .place, in: context)
        let navigation = WorldNavigation()
        go(navigation) { navigation.open(kept) }
        go(navigation) { navigation.open(gone) }
        go(navigation) { navigation.choose(.timeline) }
        context.delete(gone)
        try context.save()
        step(navigation, back: true)
        // The deleted page is passed over, landing on the one before it.
        #expect(navigation.selectedPage === kept)

        let busy = WorldNavigation()
        for index in 0..<150 { go(busy) { busy.choose(index.isMultiple(of: 2) ? .timeline : .campaigns) } }
        #expect(busy.backStack.count <= 100)
    }
}
