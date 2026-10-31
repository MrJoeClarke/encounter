//
//  PlaceHierarchyTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct PlaceHierarchyTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        return (world, context)
    }

    private func place(_ title: String, in world: World, _ context: ModelContext, parent: Page? = nil) -> Page {
        let page = world.addPage(kind: .place, in: context)
        page.title = title
        page.parent = parent
        return page
    }

    @Test func ancestorsRunNearestFirstAndDescendantsCoverEveryDepth() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", in: world, context)
        let town = place("Saltmarch", in: world, context, parent: region)
        let harbour = place("Harbour", in: world, context, parent: town)
        let hill = place("Hill", in: world, context, parent: region)

        #expect(harbour.ancestors.map(\.title) == ["Saltmarch", "Coast"])
        #expect(Set(region.descendants.map(\.title)) == ["Saltmarch", "Harbour", "Hill"])
        #expect(region.childPages.map(\.title) == ["Hill", "Saltmarch"])
        #expect(hill.descendants.isEmpty)
        #expect(harbour.pathTitle == "Coast › Saltmarch › Harbour")
    }

    @Test func aPlaceCannotBeInsideItselfOrItsOwnContents() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", in: world, context)
        let town = place("Saltmarch", in: world, context, parent: region)
        let harbour = place("Harbour", in: world, context, parent: town)

        #expect(!region.canHaveParent(region))
        #expect(!region.canHaveParent(harbour))
        #expect(!region.setParent(town))
        #expect(region.parent == nil)
        #expect(harbour.setParent(region))
        #expect(harbour.parent === region)
        #expect(harbour.setParent(nil))
        #expect(harbour.parent == nil)
    }

    @Test func aParentMustBeAPlaceInTheSameWorld() throws {
        let (world, context) = try makeWorld()
        let other = World(name: "Other")
        context.insert(other)
        let town = place("Saltmarch", in: world, context)
        let stranger = place("Elsewhere", in: other, context)
        let person = world.addPage(kind: .character, in: context)

        #expect(!town.canHaveParent(stranger))
        #expect(!town.canHaveParent(person))
    }

    @Test func deletingAPlaceMovesItsContentsUp() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", in: world, context)
        let town = place("Saltmarch", in: world, context, parent: region)
        let harbour = place("Harbour", in: world, context, parent: town)

        town.liftChildrenToParent()
        context.delete(town)
        try context.save()

        #expect(harbour.parent === region)
        #expect(region.childPages.map(\.title) == ["Harbour"])
    }

    @Test func deletingATopLevelPlaceMakesItsContentsTopLevel() throws {
        let (world, context) = try makeWorld()
        let region = place("Coast", in: world, context)
        let town = place("Saltmarch", in: world, context, parent: region)

        region.liftChildrenToParent()
        context.delete(region)
        try context.save()

        #expect(town.parent == nil)
    }
}
