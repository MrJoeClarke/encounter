//
//  InWorldDateField.swift
//  encounter
//

import SwiftUI

/// Picks a date in a world's calendar: a year, then a month by name, a day that exists in that month, and an
/// hour if the calendar has more than one a day. Changing the month keeps the day if it fits.
struct InWorldDateField: View {
    let calendar: CalendarDefinition
    @Binding var date: InWorldDate

    var body: some View {
        LabeledContent("Year") {
            TextField("Year", value: yearBinding, format: .number.grouping(.never))
                .multilineTextAlignment(.trailing)
                .labelsHidden()
                .frame(maxWidth: 100)
        }
        Picker("Month", selection: monthBinding) {
            ForEach(Array(calendar.months.indices), id: \.self) { index in
                Text(calendar.monthName(index + 1)).tag(index + 1)
            }
        }
        Picker("Day", selection: dayBinding) {
            ForEach(1...max(dayCount, 1), id: \.self) { day in
                Text(String(day)).tag(day)
            }
        }
        if calendar.hoursPerDay > 1 {
            Picker("Hour", selection: hourBinding) {
                ForEach(0..<calendar.hoursPerDay, id: \.self) { hour in
                    Text(String(hour)).tag(hour)
                }
            }
        }
    }

    private var dayCount: Int {
        calendar.months.indices.contains(date.month - 1) ? calendar.months[date.month - 1].dayCount : 1
    }

    private var yearBinding: Binding<Int> {
        Binding(get: { date.year }, set: { date.year = $0 })
    }

    private var monthBinding: Binding<Int> {
        Binding(
            get: { min(max(date.month, 1), max(calendar.months.count, 1)) },
            set: { date.month = $0; date = calendar.clamped(date) }
        )
    }

    private var dayBinding: Binding<Int> {
        Binding(get: { min(max(date.day, 1), max(dayCount, 1)) }, set: { date.day = $0 })
    }

    private var hourBinding: Binding<Int> {
        Binding(get: { min(max(date.hour, 0), calendar.hoursPerDay - 1) }, set: { date.hour = $0 })
    }
}
