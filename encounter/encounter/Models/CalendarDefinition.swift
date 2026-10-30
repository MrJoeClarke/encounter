//
//  CalendarDefinition.swift
//  encounter
//

import Foundation
import SwiftData

struct CalendarMonth: Codable, Hashable, Identifiable {
    var id: UUID = UUID()
    var name: String
    var dayCount: Int
}

/// A world's custom calendar. Years are a fixed length (the sum of the month lengths).
@Model
final class CalendarDefinition {
    var id: UUID = UUID()
    var hoursPerDay: Int = 24
    var months: [CalendarMonth] = []
    var weekdays: [String] = []
    var world: World?

    init(hoursPerDay: Int = 24, months: [CalendarMonth] = CalendarDefinition.makeMonths(count: 12, daysPerMonth: 30)) {
        self.hoursPerDay = hoursPerDay
        self.months = months
    }

    /// Builds evenly sized months with placeholder names for the creator to rename.
    static func makeMonths(count: Int, daysPerMonth: Int) -> [CalendarMonth] {
        (1...max(count, 1)).map { CalendarMonth(name: "Month \($0)", dayCount: daysPerMonth) }
    }

    var daysPerYear: Int {
        months.reduce(0) { $0 + $1.dayCount }
    }

    var hoursPerYear: Int {
        daysPerYear * hoursPerDay
    }

    func isValid(_ date: InWorldDate) -> Bool {
        guard months.indices.contains(date.month - 1) else { return false }
        return (1...months[date.month - 1].dayCount).contains(date.day)
            && (0..<hoursPerDay).contains(date.hour)
    }

    /// Hours elapsed since year 0, month 1, day 1, hour 0. Used to sort and compare dates.
    /// Returns nil if the date doesn't fit this calendar.
    func absoluteHour(of date: InWorldDate) -> Int? {
        guard isValid(date) else { return nil }
        let daysBeforeMonth = months.prefix(date.month - 1).reduce(0) { $0 + $1.dayCount }
        let days = date.year * daysPerYear + daysBeforeMonth + (date.day - 1)
        return days * hoursPerDay + date.hour
    }
}
