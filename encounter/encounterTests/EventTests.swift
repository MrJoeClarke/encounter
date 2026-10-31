//
//  EventTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct EventTests {
    private func makeWorld() throws -> (World, ModelContext) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        // Months of 30 days, 24 hours a day.
        return (world, context)
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0) -> InWorldDate {
        InWorldDate(year: year, month: month, day: day, hour: hour)
    }

    // MARK: Origin and campaign

    @Test func aNewEventIsBackstoryUntilItIsPutInACampaign() throws {
        let (world, context) = try makeWorld()
        let event = world.addPage(kind: .event, in: context)
        #expect(event.eventOrigin == .backstory && event.effectiveOrigin == .backstory)

        let campaign = world.addCampaign(named: "Tides", in: context)
        event.setCampaign(campaign)
        #expect(event.effectiveOrigin == .campaign && event.campaign === campaign)
        #expect(campaign.events?.contains { $0 === event } == true)

        event.setOrigin(.backstory)
        #expect(event.campaign == nil && event.effectiveOrigin == .backstory)
        #expect(campaign.events?.isEmpty != false)
    }

    @Test func anEventWithNothingRecordedCountsAsBackstory() throws {
        let (world, context) = try makeWorld()
        let event = world.addPage(kind: .event, in: context)
        event.eventOriginRaw = nil
        #expect(event.effectiveOrigin == .backstory)
    }

    @Test func takingAnEventOutOfItsCampaignMakesItBackstory() throws {
        let (world, context) = try makeWorld()
        let event = world.addPage(kind: .event, in: context)
        event.setCampaign(world.addCampaign(named: "Tides", in: context))
        event.setCampaign(nil)
        #expect(event.effectiveOrigin == .backstory && event.campaign == nil)
    }

    @Test func deletingACampaignKeepsItsEventsAsBackstory() throws {
        let (world, context) = try makeWorld()
        let campaign = world.addCampaign(named: "Tides", in: context)
        let first = world.addPage(kind: .event, in: context)
        let second = world.addPage(kind: .event, in: context)
        first.setCampaign(campaign)
        second.setCampaign(campaign)
        try context.save()

        world.deleteCampaign(campaign, in: context)
        try context.save()
        #expect((world.campaigns ?? []).isEmpty)
        #expect(first.campaign == nil && first.effectiveOrigin == .backstory)
        #expect(second.campaign == nil && second.effectiveOrigin == .backstory)
        #expect((world.pages ?? []).filter { $0.kind == .event }.count == 2)
    }

    // MARK: Dates

    @Test func anEventsEndNeverComesBeforeItsStart() throws {
        let (world, context) = try makeWorld()
        let calendar = try #require(world.calendar)
        let event = world.addPage(kind: .event, in: context)

        event.setStartDate(date(1492, 3, 14), in: calendar)
        event.setEndDate(date(1492, 3, 16), in: calendar)
        #expect(event.endDate == date(1492, 3, 16))

        // An end before the start is moved up to it.
        event.setEndDate(date(1491, 1, 1), in: calendar)
        #expect(event.endDate == date(1492, 3, 14))

        // Moving the start past the end brings the end with it.
        event.setEndDate(date(1492, 3, 20), in: calendar)
        event.setStartDate(date(1492, 4, 1), in: calendar)
        #expect(event.endDate == date(1492, 4, 1))

        // Moving the start earlier leaves the end alone.
        event.setStartDate(date(1492, 3, 1), in: calendar)
        #expect(event.endDate == date(1492, 4, 1))
    }

    @Test func anEventWithNoStartHasNoEnd() throws {
        let (world, context) = try makeWorld()
        let calendar = try #require(world.calendar)
        let event = world.addPage(kind: .event, in: context)

        event.setEndDate(date(1492, 3, 16), in: calendar)
        #expect(event.endDate == nil)

        event.setStartDate(date(1492, 3, 14), in: calendar)
        event.setEndDate(date(1492, 3, 16), in: calendar)
        event.setStartDate(nil, in: calendar)
        #expect(event.startDate == nil && event.endDate == nil)

        event.setStartDate(date(1492, 3, 14), in: calendar)
        event.setEndDate(date(1492, 3, 16), in: calendar)
        event.setEndDate(nil, in: calendar)
        #expect(event.startDate == date(1492, 3, 14) && event.endDate == nil)
    }

    @Test func yearsBeforeZeroOrderCorrectly() throws {
        let (world, context) = try makeWorld()
        let calendar = try #require(world.calendar)
        let event = world.addPage(kind: .event, in: context)
        event.setStartDate(date(-50, 2, 1), in: calendar)
        event.setEndDate(date(-60, 1, 1), in: calendar)       // before the start
        #expect(event.endDate == date(-50, 2, 1))
        event.setEndDate(date(-10, 1, 1), in: calendar)
        #expect(event.endDate == date(-10, 1, 1))
    }

    // MARK: Location and participants

    @Test func anEventsLocationIsAPlaceThatNeedNotBeOnAMap() throws {
        let (world, context) = try makeWorld()
        let event = world.addPage(kind: .event, in: context)
        let tavern = world.addPage(kind: .place, in: context)
        let harbour = world.addPage(kind: .place, in: context)
        #expect(tavern.geometry == nil)

        event.setLinkedPage(tavern, role: LinkRole.location, in: context)
        #expect(event.linkedPage(role: LinkRole.location) === tavern)
        event.setLinkedPage(harbour, role: LinkRole.location, in: context)
        #expect(event.linkedPage(role: LinkRole.location) === harbour)
        event.setLinkedPage(nil, role: LinkRole.location, in: context)
        #expect(event.linkedPage(role: LinkRole.location) == nil)
    }

    @Test func participantsAreAddedOnceAndRemoved() throws {
        let (world, context) = try makeWorld()
        let event = world.addPage(kind: .event, in: context)
        let aria = world.addPage(kind: .character, in: context)
        aria.title = "Aria"
        let harpers = world.addPage(kind: .organisation, in: context)
        harpers.title = "Harpers"

        #expect(event.addLink(to: harpers, role: LinkRole.participant, in: context))
        #expect(event.addLink(to: aria, role: LinkRole.participant, in: context))
        #expect(!event.addLink(to: aria, role: LinkRole.participant, in: context))     // already there
        #expect(!event.addLink(to: event, role: LinkRole.participant, in: context))    // not itself
        #expect(event.linkedPages(role: LinkRole.participant).map(\.title) == ["Aria", "Harpers"])
        #expect(aria.backlinks.map(\.role) == [LinkRole.participant])

        event.removeLinks(to: aria, role: LinkRole.participant, in: context)
        #expect(event.linkedPages(role: LinkRole.participant).map(\.title) == ["Harpers"])
        #expect(aria.backlinks.isEmpty)
    }

    @Test func aPageFromAnotherWorldCantTakePart() throws {
        let (world, context) = try makeWorld()
        let other = World(name: "Other")
        context.insert(other)
        let event = world.addPage(kind: .event, in: context)
        let stranger = other.addPage(kind: .character, in: context)
        #expect(!event.addLink(to: stranger, role: LinkRole.participant, in: context))
        #expect(event.linkedPages(role: LinkRole.participant).isEmpty)
    }

    @Test func deletingAParticipantLeavesTheEventWithoutThem() throws {
        let (world, context) = try makeWorld()
        let event = world.addPage(kind: .event, in: context)
        let aria = world.addPage(kind: .character, in: context)
        event.addLink(to: aria, role: LinkRole.participant, in: context)
        try context.save()

        MentionSync.delete(aria, in: context)
        try context.save()
        #expect(event.linkedPages(role: LinkRole.participant).isEmpty)
    }

    // MARK: Navigation, export and import

    @Test func openingACampaignShowsItInTheCampaignsList() throws {
        let (world, context) = try makeWorld()
        let campaign = world.addCampaign(named: "Tides", in: context)
        let navigation = WorldNavigation()
        navigation.searchText = "x"
        navigation.openCampaign(campaign)
        #expect(navigation.selection == .campaigns)
        #expect(navigation.selectedCampaign === campaign)
        #expect(navigation.searchText.isEmpty)

        navigation.choose(.home)
        #expect(navigation.selectedCampaign == nil)
    }

    @Test func anEventsDetailsSurviveExportAndImport() async throws {
        let (world, context) = try makeWorld()
        let calendar = try #require(world.calendar)
        let campaign = world.addCampaign(named: "Tides", in: context)
        let event = world.addPage(kind: .event, in: context)
        event.title = "Arrival"
        event.setCampaign(campaign)
        event.setStartDate(date(1492, 3, 14, 6), in: calendar)
        event.setEndDate(date(1492, 3, 16), in: calendar)
        let place = world.addPage(kind: .place, in: context)
        place.title = "Harbour"
        event.setLinkedPage(place, role: LinkRole.location, in: context)
        let aria = world.addPage(kind: .character, in: context)
        aria.title = "Aria"
        event.addLink(to: aria, role: LinkRole.participant, in: context)

        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(WorldExporter.makeContents(of: world), into: target)
        let copy = try #require((imported.pages ?? []).first { $0.title == "Arrival" })
        #expect(copy.effectiveOrigin == .campaign && copy.campaign?.name == "Tides")
        #expect(copy.startDate == date(1492, 3, 14, 6) && copy.endDate == date(1492, 3, 16))
        #expect(copy.linkedPage(role: LinkRole.location)?.title == "Harbour")
        #expect(copy.linkedPages(role: LinkRole.participant).map(\.title) == ["Aria"])
    }
}
