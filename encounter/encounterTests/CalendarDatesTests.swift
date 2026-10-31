//
//  CalendarDatesTests.swift
//  encounterTests
//

import Testing
import Foundation
import SwiftData
@testable import encounter

@MainActor
struct CalendarDatesTests {
    private func moonCalendar() -> CalendarDefinition {
        CalendarDefinition(
            hoursPerDay: 10,
            months: [CalendarMonth(name: "Frost", dayCount: 20), CalendarMonth(name: "Bloom", dayCount: 30)]
        )
    }

    @Test func datesReadWithMonthNamesAndWeekdays() {
        let calendar = moonCalendar()
        calendar.weekdays = ["Moonday", "Sunday", "Starday"]
        let date = InWorldDate(year: 1203, month: 2, day: 14, hour: 6)

        #expect(calendar.format(date) == "14 Bloom 1203")
        #expect(calendar.format(date, style: .long).hasSuffix("14 Bloom 1203, hour 6"))
        #expect(calendar.format(InWorldDate(year: 1, month: 3, day: 1, hour: 0)) == "Invalid date")
    }

    @Test func aBlankMonthNameReadsAsItsNumber() {
        let calendar = moonCalendar()
        calendar.months[1].name = "  "
        #expect(calendar.format(InWorldDate(year: 5, month: 2, day: 3, hour: 0)) == "3 Month 2 5")
    }

    @Test func weekdaysRepeatFromYearZeroAndCountBackBeforeIt() {
        let calendar = moonCalendar()   // 50 days a year, 10 hours a day
        calendar.weekdays = ["A", "B", "C"]

        #expect(calendar.weekday(of: InWorldDate(year: 0, month: 1, day: 1, hour: 0)) == "A")
        #expect(calendar.weekday(of: InWorldDate(year: 0, month: 1, day: 1, hour: 9)) == "A")
        #expect(calendar.weekday(of: InWorldDate(year: 0, month: 1, day: 2, hour: 0)) == "B")
        #expect(calendar.weekday(of: InWorldDate(year: 0, month: 1, day: 4, hour: 0)) == "A")
        // The day before year 0 is year -1's last day: day 49 of 50, so 49 % 3 counts forward from the start.
        // Counting back from A, the day before is C.
        #expect(calendar.weekday(of: InWorldDate(year: -1, month: 2, day: 30, hour: 0)) == "C")
        #expect(calendar.weekday(of: InWorldDate(year: -1, month: 2, day: 29, hour: 0)) == "B")

        calendar.weekdays = []
        #expect(calendar.weekday(of: InWorldDate()) == nil)
    }

    @Test func yearsBeforeZeroOrderBeforeYearZero() throws {
        let calendar = moonCalendar()
        let before = try #require(calendar.absoluteHour(of: InWorldDate(year: -1, month: 2, day: 30, hour: 9)))
        let origin = try #require(calendar.absoluteHour(of: InWorldDate(year: 0, month: 1, day: 1, hour: 0)))
        let earlier = try #require(calendar.absoluteHour(of: InWorldDate(year: -3, month: 1, day: 1, hour: 0)))
        #expect(before == -1)
        #expect(origin == 0)
        #expect(earlier < before)
    }

    @Test func theGregorianPresetIsTheEarthCalendar() {
        let calendar = CalendarDefinition()
        calendar.apply(.gregorian)
        #expect(calendar.months.count == 12)
        #expect(calendar.daysPerYear == 365)
        #expect(calendar.hoursPerDay == 24)
        #expect(calendar.weekdays.count == 7)
        #expect(calendar.format(InWorldDate(year: 2026, month: 10, day: 31, hour: 0)) == "31 October 2026")
    }

    @Test func everyPresetIsAUsableCalendar() {
        for preset in CalendarPreset.allCases {
            let calendar = CalendarDefinition()
            calendar.apply(preset)
            #expect(!calendar.months.isEmpty)
            #expect(calendar.months.allSatisfy { $0.dayCount > 0 && !$0.name.isEmpty })
            #expect(calendar.hoursPerDay > 0)
            #expect(calendar.isValid(InWorldDate()))
        }
    }

    @Test func aDateIsMovedToTheNearestOneThatExists() {
        let calendar = moonCalendar()
        #expect(calendar.clamped(InWorldDate(year: 4, month: 2, day: 30, hour: 9)) == InWorldDate(year: 4, month: 2, day: 30, hour: 9))
        // Moving to the shorter month keeps the day only if it fits.
        #expect(calendar.clamped(InWorldDate(year: 4, month: 1, day: 30, hour: 0)) == InWorldDate(year: 4, month: 1, day: 20, hour: 0))
        #expect(calendar.clamped(InWorldDate(year: 4, month: 9, day: 1, hour: 99)) == InWorldDate(year: 4, month: 2, day: 1, hour: 9))
        #expect(calendar.clamped(InWorldDate(year: 4, month: 0, day: 0, hour: -3)) == InWorldDate(year: 4, month: 1, day: 1, hour: 0))
    }

    @Test func editingTheCalendarCountsDatesThatNoLongerFit() throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        let calendar = try #require(world.calendar)
        calendar.months = [CalendarMonth(name: "Frost", dayCount: 30), CalendarMonth(name: "Bloom", dayCount: 30)]
        let event = world.addPage(kind: .event, in: context)
        event.startDate = InWorldDate(year: 1, month: 2, day: 30, hour: 0)
        event.endDate = InWorldDate(year: 1, month: 1, day: 30, hour: 0)
        #expect(world.datesOutsideCalendar == 0)

        calendar.months[1].dayCount = 20       // the start date's day 30 is gone
        #expect(world.datesOutsideCalendar == 1)
        calendar.months.removeLast()           // and now its month is gone too
        #expect(world.datesOutsideCalendar == 1)
        calendar.months[0].dayCount = 10
        #expect(world.datesOutsideCalendar == 2)
        // Nothing was changed.
        #expect(event.startDate == InWorldDate(year: 1, month: 2, day: 30, hour: 0))
    }

    @Test func aCustomCalendarSurvivesExportAndImport() async throws {
        let context = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let world = World(name: "Test")
        context.insert(world)
        let calendar = try #require(world.calendar)
        calendar.apply(.gregorian)
        calendar.hoursPerDay = 20
        calendar.months[0].name = "Frostmoon"
        calendar.weekdays.append("Restday")

        let contents = WorldExporter.makeContents(of: world)
        let target = ModelContext(try AppSchema.makeContainer(inMemory: true))
        let (imported, _) = await WorldImporter.importWorld(contents, into: target)
        let copy = try #require(imported.calendar)
        #expect(copy.hoursPerDay == 20)
        #expect(copy.months.map(\.name) == calendar.months.map(\.name))
        #expect(copy.months.map(\.dayCount) == calendar.months.map(\.dayCount))
        #expect(copy.weekdays == calendar.weekdays)
        #expect(copy.format(InWorldDate(year: 1, month: 1, day: 2, hour: 0), style: .long) == calendar.format(InWorldDate(year: 1, month: 1, day: 2, hour: 0), style: .long))
    }
}
