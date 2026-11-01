//
//  TimelineTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct TimelineTests {
    private func makeWorld() throws -> (World, ModelContext, CalendarDefinition) {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        return (world, context, world.calendar!)
    }

    @discardableResult
    private func event(_ title: String, _ date: InWorldDate?, in world: World, _ context: ModelContext) -> Page {
        let page = world.addPage(kind: .event, in: context)
        page.title = title
        page.setStartDate(date, in: world.calendar)
        return page
    }

    private func date(_ year: Int, _ month: Int = 1, _ day: Int = 1, _ hour: Int = 0) -> InWorldDate {
        InWorldDate(year: year, month: month, day: day, hour: hour)
    }

    private func titles(_ groups: [TimelineGroup]) -> [[String]] {
        groups.map { $0.events.map(\.title) }
    }

    // MARK: Ordering and grouping

    @Test func eventsAreOrderedByWhenTheyStartedAndGroupedByYear() throws {
        let (world, context, calendar) = try makeWorld()
        let events = [
            event("Coronation", date(1492, 6, 1), in: world, context),
            event("Founding", date(-300, 2, 14), in: world, context),
            event("Feast", date(1492, 6, 1, 9), in: world, context),
            event("Storm", date(1492, 1, 20), in: world, context),
            event("War", date(1300), in: world, context),
        ]
        let groups = TimelineBuilder.groups(of: events, calendar: calendar)
        #expect(groups.map(\.year) == [-300, 1300, 1492])
        #expect(titles(groups) == [["Founding"], ["War"], ["Storm", "Coronation", "Feast"]])
    }

    @Test func eventsAtTheSameTimeAreOrderedByTitleAndUndatedOnesComeLast() throws {
        let (world, context, calendar) = try makeWorld()
        let events = [
            event("Zebra", nil, in: world, context),
            event("Beta", date(10), in: world, context),
            event("Alpha", date(10), in: world, context),
            event("Mystery", nil, in: world, context),
        ]
        let groups = TimelineBuilder.groups(of: events, calendar: calendar)
        #expect(titles(groups) == [["Alpha", "Beta"], ["Mystery", "Zebra"]])
        #expect(groups.last?.year == nil)
    }

    @Test func aDateTheCalendarNoLongerHoldsCountsAsUndated() throws {
        let (world, context, calendar) = try makeWorld()
        let fine = event("Fine", date(5, 12, 30), in: world, context)
        let lost = event("Lost", date(5, 12, 30), in: world, context)
        calendar.months.removeLast()                // month 12 is gone
        let groups = TimelineBuilder.groups(of: [fine, lost], calendar: calendar)
        #expect(groups.count == 1 && groups[0].year == nil)
        #expect(Set(groups[0].events.map(\.title)) == ["Fine", "Lost"])
    }

    @Test func aWorldWithNoEventsHasNoGroups() throws {
        let (_, _, calendar) = try makeWorld()
        #expect(TimelineBuilder.groups(of: [], calendar: calendar).isEmpty)
    }

    // MARK: Filters

    @Test func aTimelineCanBeNarrowedToBackstoryOrACampaign() throws {
        let (world, context, calendar) = try makeWorld()
        let tides = world.addCampaign(named: "Tides", in: context)
        let storms = world.addCampaign(named: "Storms", in: context)
        let old = event("Old", date(1), in: world, context)
        let first = event("First", date(2), in: world, context)
        first.setCampaign(tides)
        let second = event("Second", date(3), in: world, context)
        second.setCampaign(storms)
        let all = [old, first, second]

        #expect(titles(TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(origin: .backstory))) == [["Old"]])
        #expect(titles(TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(origin: .campaign(tides)))) == [["First"]])
        #expect(TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(origin: .campaign(storms))).flatMap(\.events).map(\.title) == ["Second"])
    }

    @Test func aTimelineCanBeNarrowedToACharacterOrAnOrganisation() throws {
        let (world, context, calendar) = try makeWorld()
        let aria = world.addPage(kind: .character, in: context)
        let harpers = world.addPage(kind: .organisation, in: context)
        let one = event("One", date(1), in: world, context)
        let two = event("Two", date(2), in: world, context)
        let three = event("Three", date(3), in: world, context)
        one.addLink(to: aria, role: LinkRole.participant, in: context)
        two.addLink(to: aria, role: LinkRole.participant, in: context)
        two.addLink(to: harpers, role: LinkRole.participant, in: context)
        three.addLink(to: harpers, role: LinkRole.participant, in: context)
        let all = [one, two, three]

        #expect(TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(character: aria)).flatMap(\.events).map(\.title) == ["One", "Two"])
        #expect(TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(organisation: harpers)).flatMap(\.events).map(\.title) == ["Two", "Three"])
        // Both have to match.
        #expect(TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(character: aria, organisation: harpers)).flatMap(\.events).map(\.title) == ["Two"])
    }

    @Test func aPlaceFilterIncludesEverythingInsideThePlace() throws {
        let (world, context, calendar) = try makeWorld()
        let coast = world.addPage(kind: .place, in: context)
        let town = world.addPage(kind: .place, in: context)
        town.setParent(coast)
        let tavern = world.addPage(kind: .place, in: context)
        tavern.setParent(town)
        let elsewhere = world.addPage(kind: .place, in: context)

        let inTavern = event("In the tavern", date(1), in: world, context)
        inTavern.setLinkedPage(tavern, role: LinkRole.location, in: context)
        let inTown = event("In town", date(2), in: world, context)
        inTown.setLinkedPage(town, role: LinkRole.location, in: context)
        let far = event("Far away", date(3), in: world, context)
        far.setLinkedPage(elsewhere, role: LinkRole.location, in: context)
        let nowhere = event("Nowhere", date(4), in: world, context)
        let all = [inTavern, inTown, far, nowhere]

        func result(_ place: Page) -> [String] {
            TimelineBuilder.groups(of: all, calendar: calendar, filter: .init(place: place)).flatMap(\.events).map(\.title)
        }
        #expect(result(coast) == ["In the tavern", "In town"])
        #expect(result(town) == ["In the tavern", "In town"])
        #expect(result(tavern) == ["In the tavern"])
        #expect(result(elsewhere) == ["Far away"])
    }

    @Test func aFilterIsActiveOnlyWhenSomethingIsSet() throws {
        let (world, context, _) = try makeWorld()
        #expect(!TimelineFilter().isActive)
        #expect(TimelineFilter(origin: .backstory).isActive)
        #expect(TimelineFilter(character: world.addPage(kind: .character, in: context)).isActive)
    }

    @Test func openingTheTimelineKeepsTheSearchAndSelectionTidy() throws {
        let navigation = WorldNavigation()
        navigation.searchText = "x"
        navigation.choose(.timeline)
        #expect(navigation.selection == .timeline && navigation.searchText.isEmpty)
    }
}
