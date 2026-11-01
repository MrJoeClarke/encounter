//
//  JourneyBuilder.swift
//  encounter
//

import Foundation
import CoreGraphics
import SwiftData

/// One step of a character's journey: an event they took part in, and where it happened.
struct JourneyStop: Identifiable {
    let event: Page
    /// The event's location, if it has one.
    let place: Page?
    /// Whether the event has a date the calendar can place. Undated events come last and aren't part of the route.
    let isDated: Bool
    var id: UUID { event.id }
}

/// A character's journey, derived from the events they took part in. Nothing about it is stored.
enum JourneyBuilder {
    /// The events the character took part in, by date, with undated events last.
    @MainActor
    static func stops(of character: Page, calendar: CalendarDefinition?) -> [JourneyStop] {
        var seen: Set<UUID> = []
        let events = character.backlinks
            .filter { $0.role == LinkRole.participant && $0.source.kind == .event && !$0.source.isDeleted }
            .map(\.source)
            .filter { seen.insert($0.id).inserted }
        return TimelineBuilder.groups(of: events, calendar: calendar).flatMap { group in
            group.events.map { JourneyStop(event: $0, place: $0.linkedPage(role: LinkRole.location), isDated: group.year != nil) }
        }
    }

    /// The places the journey passes through in order, as positions on a map in image pixels. Stops that are
    /// undated, have no place, or whose place isn't on the map are left out, and so is a stop at the same place
    /// as the one before it, since the character didn't go anywhere.
    @MainActor
    static func route(of stops: [JourneyStop], on map: WorldMap) -> [CGPoint] {
        var points: [CGPoint] = []
        var lastPlace: Page?
        for stop in stops where stop.isDated {
            guard let place = stop.place, let pixel = map.pixel(of: place) else { continue }
            if place === lastPlace { continue }
            lastPlace = place
            points.append(CGPoint(x: pixel.x, y: pixel.y))
        }
        return points
    }
}
