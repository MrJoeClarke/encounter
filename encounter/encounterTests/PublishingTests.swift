//
//  PublishingTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct PublishingTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "W")
        context.insert(world)
        world.ensureRootPlace(in: context)
        return (world, context)
    }

    @Test func aNewPageIsHiddenFromPlayers() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        #expect(page.publishState == .hidden)
        #expect(!page.isVisibleToPlayers)
        #expect(page.versionForPlayers == nil)
    }

    @Test func publishingMakesTheDraftWhatPlayersSee() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        page.summary = "Harbour master"
        page.body = AttributedString("Dour, and nobody's fool.")
        page.attributes["core.age"] = .text("52")
        page.tags = ["port"]
        page.publish()

        #expect(page.publishState == .published)
        let seen = try #require(page.versionForPlayers)
        #expect(seen.title == "Odric" && seen.summary == "Harbour master")
        #expect(String(seen.body.characters) == "Dour, and nobody's fool.")
        #expect(seen.attributes["core.age"] == .text("52") && seen.tags == ["port"])
    }

    @Test func editingAfterPublishingChangesTheDraftNotWhatPlayersSee() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        page.publish()

        page.title = "Captain Odric Vane"
        page.body = AttributedString("A secret.")
        #expect(page.publishState == .publishedWithChanges)
        #expect(page.versionForPlayers?.title == "Odric")
        #expect(page.versionForPlayers.map { String($0.body.characters) } == "")

        page.publish()
        #expect(page.publishState == .published)
        #expect(page.versionForPlayers?.title == "Captain Odric Vane")
    }

    @Test func revertingPutsTheDraftBackAsPublished() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .place, in: context)
        page.title = "Brackwater"
        page.body = AttributedString("A harbour town.")
        page.publish()

        page.title = "Brackwater (rebuilt)"
        page.body = AttributedString("Burned down.")
        page.tags = ["ruin"]
        page.revertToPublished()

        #expect(page.title == "Brackwater" && page.tags.isEmpty)
        #expect(String(page.body.characters) == "A harbour town.")
        #expect(page.publishState == .published)
    }

    @Test func revertingDoesNothingToAPageThatWasNeverPublished() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        page.revertToPublished()
        #expect(page.title == "Odric" && page.publishState == .hidden)
    }

    @Test func unpublishingHidesThePageAndKeepsTheVersion() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        page.publish()
        page.unpublish()
        #expect(page.publishState == .hidden && !page.isVisibleToPlayers)
        #expect(page.publishedVersion?.title == "Odric")
    }

    @Test func dmNotesAreNeverInThePublishedVersion() throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        page.dmNotes = "Is the smuggler."
        page.publish()
        let data = try #require(page.publishedData)
        #expect(String(decoding: data, as: UTF8.self).contains("smuggler") == false)
        // Editing them is not a change to what players see.
        page.dmNotes = "Is the smuggler, and the king's cousin."
        #expect(page.publishState == .published)
    }

    @Test func theWorldsOwnPlaceIsAlwaysShownAsItIs() throws {
        let (world, _) = try makeWorld()
        let root = try #require(world.rootPlace)
        #expect(root.isVisibleToPlayers)
        root.title = "The Known World"
        #expect(root.versionForPlayers?.title == "The Known World")
    }

    @Test func publishAllPublishesOnlyHiddenPagesAndNotTheWorldsPlace() throws {
        let (world, context) = try makeWorld()
        let first = world.addPage(kind: .character, in: context)
        first.title = "One"
        let second = world.addPage(kind: .item, in: context)
        second.title = "Two"
        second.publish()
        second.title = "Two, edited"
        let count = world.publishAllHiddenPages()
        #expect(count == 1)
        #expect(first.publishState == .published)
        // A page that was already published keeps its published version, even though it has changes.
        #expect(second.publishState == .publishedWithChanges)
        #expect(world.rootPlace?.isPublished == false)
    }

    @Test func publishingSurvivesExportAndImport() async throws {
        let (world, context) = try makeWorld()
        let page = world.addPage(kind: .character, in: context)
        page.title = "Odric"
        page.dmNotes = "Smuggler."
        page.publish()
        page.title = "Odric, edited"

        let contents = WorldExporter.makeContents(of: world)
        let (imported, _) = await WorldImporter.importWorld(contents, into: context)
        let copy = try #require((imported.pages ?? []).first { $0.title == "Odric, edited" })
        #expect(copy.publishState == .publishedWithChanges)
        #expect(copy.publishedVersion?.title == "Odric")
        #expect(copy.dmNotes == "Smuggler.")
    }
}
