//
//  JourneySection.swift
//  encounter
//

import SwiftUI

/// A character's journey: the events they took part in, in date order, with where each happened. Choosing a row
/// opens the event.
struct JourneySection: View {
    let page: Page

    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        let calendar = page.world?.calendar
        let stops = JourneyBuilder.stops(of: page, calendar: calendar)
        if !stops.isEmpty {
            ThemedSection("Journey") {
                ForEach(stops) { stop in
                    Button {
                        navigation.open(stop.event)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(stop.event.title.isEmpty ? String(localized: "Untitled") : stop.event.title)
                            } icon: {
                                Image(systemName: stop.event.kind.systemImage)
                            }
                            if let line = detail(of: stop, calendar: calendar) {
                                Text(line)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    /// The date and the place, such as "Year 12, Day 3 · Waterdeep, Sword Coast".
    private func detail(of stop: JourneyStop, calendar: CalendarDefinition?) -> String? {
        var parts: [String] = []
        if let start = stop.event.startDate, let calendar { parts.append(calendar.format(start)) }
        if let place = stop.place {
            let names = ([place] + place.ancestors.filter { !$0.isWorldRoot }.prefix(1)).map {
                $0.title.isEmpty ? String(localized: "Untitled") : $0.title
            }
            parts.append(names.joined(separator: ", "))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
