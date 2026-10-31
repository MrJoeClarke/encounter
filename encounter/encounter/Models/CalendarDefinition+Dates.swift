//
//  CalendarDefinition+Dates.swift
//  encounter
//

import Foundation

/// A calendar to start from, instead of typing every month.
enum CalendarPreset: String, CaseIterable, Identifiable {
    case simple
    case gregorian

    var id: String { rawValue }

    var title: LocalizedStringResource {
        switch self {
        case .simple: "Twelve Months of 30 Days"
        case .gregorian: "Gregorian (Earth)"
        }
    }

    var hoursPerDay: Int { 24 }

    var months: [CalendarMonth] {
        switch self {
        case .simple:
            CalendarDefinition.makeMonths(count: 12, daysPerMonth: 30)
        case .gregorian:
            [("January", 31), ("February", 28), ("March", 31), ("April", 30), ("May", 31), ("June", 30),
             ("July", 31), ("August", 31), ("September", 30), ("October", 31), ("November", 30), ("December", 31)]
                .map { CalendarMonth(name: $0.0, dayCount: $0.1) }
        }
    }

    var weekdays: [String] {
        switch self {
        case .simple: []
        case .gregorian: ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        }
    }
}

extension CalendarDefinition {
    /// Replaces the months, weekdays and day length with a preset's.
    func apply(_ preset: CalendarPreset) {
        hoursPerDay = preset.hoursPerDay
        months = preset.months
        weekdays = preset.weekdays
    }

    /// The name shown for a month, which falls back to its number if the creator left it blank.
    func monthName(_ month: Int) -> String {
        guard months.indices.contains(month - 1) else { return String(month) }
        let name = months[month - 1].name.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? String(localized: "Month \(month)") : name
    }

    /// The name of the day of the week a date falls on, counting from year 0, month 1, day 1 as the first
    /// weekday. Nil if the calendar has no weekdays or the date doesn't fit it. Years before 0 count back.
    func weekday(of date: InWorldDate) -> String? {
        guard !weekdays.isEmpty, let hour = absoluteHour(of: date) else { return nil }
        // Floor division, so hours before the start fall on the right day.
        let day = Int((Double(hour) / Double(hoursPerDay)).rounded(.down))
        let index = ((day % weekdays.count) + weekdays.count) % weekdays.count
        let name = weekdays[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    enum DateStyle {
        /// "14 Frost 1203"
        case short
        /// "Moonday 14 Frost 1203, hour 6"
        case long
    }

    func format(_ date: InWorldDate, style: DateStyle = .short) -> String {
        guard isValid(date) else { return String(localized: "Invalid date") }
        var text = "\(date.day) \(monthName(date.month)) \(date.year)"
        guard style == .long else { return text }
        if let weekday = weekday(of: date) { text = "\(weekday) \(text)" }
        if hoursPerDay > 1 { text += ", " + String(localized: "hour \(date.hour)") }
        return text
    }

    /// The nearest date that fits this calendar, so a change of month (or a calendar edit) can't leave a
    /// date with, say, a 31st in a 30 day month.
    func clamped(_ date: InWorldDate) -> InWorldDate {
        guard !months.isEmpty else { return date }
        let month = min(max(date.month, 1), months.count)
        return InWorldDate(
            year: date.year,
            month: month,
            day: min(max(date.day, 1), months[month - 1].dayCount),
            hour: min(max(date.hour, 0), max(hoursPerDay - 1, 0))
        )
    }
}

extension World {
    /// How many of the world's dates don't fit its calendar, for warning the creator after the calendar is
    /// edited. Dates are never changed or removed automatically.
    var datesOutsideCalendar: Int {
        guard let calendar else { return 0 }
        return (pages ?? []).reduce(0) { total, page in
            total + [page.startDate, page.endDate].compactMap { $0 }.filter { !calendar.isValid($0) }.count
        }
    }
}
