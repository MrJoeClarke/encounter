//
//  HighlightTests.swift
//  encounterTests
//

import Testing
import Foundation
import MapKit
import SwiftData
@testable import encounter

@MainActor
struct HighlightTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        return (world, context)
    }

    @Test func aPlaceIsShownOnTheMapOfThePlaceAboveItAndChosenThere() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let map = try #require(world.addVectorMap(named: "World", for: root, extentMetres: 1_000_000, in: context))
        let realm = world.addPage(kind: .place, in: context)
        _ = realm.setGeometry(.polygon([GridPoint(easting: 1000, northing: 1000), GridPoint(easting: 5000, northing: 1000), GridPoint(easting: 5000, northing: 5000)]))
        #expect(realm.mapShowingIt === map)
        let navigation = WorldNavigation()
        navigation.showOnMap(realm)
        #expect(navigation.selectedMap === map)
        #expect(navigation.highlightedPlace === realm)
        #expect(navigation.selection == .worldMap)
    }

    @Test func aPlaceWithNoPositionOrNoMapIsNotShown() throws {
        let (world, context) = try makeWorld()
        let root = world.ensureRootPlace(in: context)
        let nowhere = world.addPage(kind: .place, in: context)
        #expect(nowhere.mapShowingIt == nil)
        // A position, but nothing above it has a map.
        let placed = world.addPage(kind: .place, in: context)
        _ = placed.setGeometry(.point(GridPoint(easting: 10, northing: 10)))
        _ = root
        #expect(placed.mapShowingIt == nil)
        let navigation = WorldNavigation()
        navigation.showOnMap(placed)
        #expect(navigation.highlightedPlace == nil && navigation.selectedMap == nil)
    }

    @Test func everyStyleHasItsOwnAccentThatIsNotItsGround() {
        for style in MapStyle.all {
            #expect(style.accent != style.background, Comment(rawValue: style.id))
        }
        #expect(Set(MapStyle.all.map { "\($0.accent.red),\($0.accent.green),\($0.accent.blue)" }).count == MapStyle.all.count)
    }

    @Test func aHighlightedPlaceIsDrawnInEveryStyleEvenOneWithNoPen() {
        var area = [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 0, longitude: 1), CLLocationCoordinate2D(latitude: 1, longitude: 1)]
        let polygon = MKPolygon(coordinates: &area, count: area.count)
        var path = [CLLocationCoordinate2D(latitude: 0, longitude: 0), CLLocationCoordinate2D(latitude: 1, longitude: 1)]
        let line = MKPolyline(coordinates: &path, count: path.count)
        // Dark has no hand-drawn look, and is drawn with MapKit's own renderers until a place in it is chosen.
        #expect(InkRenderer.make(polygon: polygon, type: "Region", style: .dark) == nil)
        #expect(InkRenderer.make(line: line, type: "River", style: .dark) == nil)
        #expect(InkRenderer.make(polygon: polygon, type: "Region", style: .dark, highlighted: true) != nil)
        #expect(InkRenderer.make(line: line, type: "River", style: .dark, highlighted: true) != nil)
        // Even a type that is kept crisp in a hand-drawn style is highlighted.
        #expect(InkRenderer.make(polygon: polygon, type: "Building", style: .parchment) == nil)
        #expect(InkRenderer.make(polygon: polygon, type: "Building", style: .parchment, highlighted: true) != nil)
    }
}
