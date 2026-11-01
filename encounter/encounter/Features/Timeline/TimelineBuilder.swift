//
//  TimelineBuilder.swift
//  encounter
//

import Foundation

/// What a timeline shows. Every part that is set has to match, so filters narrow the timeline down.
struct TimelineFilter: Equatable {
    enum Origin: Hashable {
        case any
        case backstory
        case campaign(Campaign)

        static func == (lhs: Origin, rhs: Origin) -> Bool {
            switch (lhs, rhs) {
            case (.any, .any), (.backstory, .backstory): true
            case (.campaign(let a), .campaign(let b)): a === b
            default: false
            }
        }

        func hash(into hasher: inout Hasher) {
            switch self {
            case .any: hasher.combine(0)
            case .backstory: hasher.combine(1)
            case .campaign(let campaign): hasher.combine(2); hasher.combine(ObjectIdentifier(campaign))
            }
        }
    }

    var origin: Origin = .any
    /// Only events this character took part in.
    var character: Page?
    /// Only events this organisation took part in.
    var organisation: Page?
    /// Only events at this place, or at a place inside it.
    var place: Page?

    var isActive: Bool {
        origin != .any || character != nil || organisation != nil || place != nil
    }
}

/// Events that happened in one year, or the events that have no date.
struct TimelineGroup: Identifiable {
    /// Nil for events with no date, or with one the calendar can no longer place.
    let year: Int?
    let events: [Page]
    var id: String { year.map(String.init) ?? "undated" }
}

enum TimelineBuilder {
    /// Sorts events by when they started, grouped by year, with undated events last. Events at the same time are
    /// ordered by title.
    @MainActor
    static func groups(of events: [Page], calendar: CalendarDefinition?, filter: TimelineFilter = TimelineFilter()) -> [TimelineGroup] {
        let placeIDs = filter.place.map { Set(([$0] + $0.descendants).map(\.id)) }
        let wanted = events.filter { matches($0, filter: filter, placeIDs: placeIDs) }

        var dated: [(event: Page, hour: Int, year: Int)] = []
        var undated: [Page] = []
        for event in wanted {
            if let start = event.startDate, let hour = calendar?.absoluteHour(of: start) {
                dated.append((event, hour, start.year))
            } else {
                undated.append(event)
            }
        }
        dated.sort { ($0.hour, $0.event.title.localizedLowercase) < ($1.hour, $1.event.title.localizedLowercase) }

        var groups: [TimelineGroup] = []
        var index = 0
        while index < dated.count {
            let year = dated[index].year
            let end = dated[index...].firstIndex { $0.year != year } ?? dated.count
            groups.append(TimelineGroup(year: year, events: dated[index..<end].map(\.event)))
            index = end
        }
        if !undated.isEmpty {
            groups.append(TimelineGroup(year: nil, events: undated.sorted { $0.title.localizedLowercase < $1.title.localizedLowercase }))
        }
        return groups
    }

    @MainActor
    static func matches(_ event: Page, filter: TimelineFilter, placeIDs: Set<UUID>?) -> Bool {
        switch filter.origin {
        case .any: break
        case .backstory: if event.effectiveOrigin != .backstory { return false }
        case .campaign(let campaign): if event.campaign !== campaign { return false }
        }
        if let character = filter.character, !event.linkedPages(role: LinkRole.participant).contains(where: { $0 === character }) {
            return false
        }
        if let organisation = filter.organisation, !event.linkedPages(role: LinkRole.participant).contains(where: { $0 === organisation }) {
            return false
        }
        if let placeIDs {
            guard let location = event.linkedPage(role: LinkRole.location), placeIDs.contains(location.id) else { return false }
        }
        return true
    }
}
