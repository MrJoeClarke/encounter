//
//  Page+Events.swift
//  encounter
//

import Foundation
import SwiftData

extension Page {
    /// Whether the event is backstory or part of a campaign. An event with nothing recorded counts as backstory.
    var effectiveOrigin: EventOrigin { eventOrigin ?? .backstory }

    /// Sets whether the event is backstory or in a campaign. Backstory belongs to no campaign.
    func setOrigin(_ origin: EventOrigin) {
        eventOrigin = origin
        if origin == .backstory { campaign = nil }
    }

    /// Puts the event in a campaign, which makes it a campaign event, or takes it out of any (making it backstory).
    func setCampaign(_ newCampaign: Campaign?) {
        campaign = newCampaign
        eventOrigin = newCampaign == nil ? .backstory : .campaign
    }

    // MARK: Dates

    /// Sets when the event starts, or removes the date (and so the end too). An end that would now be before the
    /// start is moved up to it.
    func setStartDate(_ date: InWorldDate?, in calendar: CalendarDefinition?) {
        startDate = date
        guard let date else {
            endDate = nil
            return
        }
        if let end = endDate, Self.isBefore(end, date, in: calendar) { endDate = date }
    }

    /// Sets when the event ends, or removes the end. An event with no start can't end, and an end before the start
    /// is moved up to the start.
    func setEndDate(_ date: InWorldDate?, in calendar: CalendarDefinition?) {
        guard let start = startDate, let date else {
            endDate = nil
            return
        }
        endDate = Self.isBefore(date, start, in: calendar) ? start : date
    }

    private static func isBefore(_ a: InWorldDate, _ b: InWorldDate, in calendar: CalendarDefinition?) -> Bool {
        guard let calendar, let x = calendar.absoluteHour(of: a), let y = calendar.absoluteHour(of: b) else { return false }
        return x < y
    }

    // MARK: Linked pages

    /// Every page this one links to with a role, such as an event's participants, sorted by title.
    func linkedPages(role: String) -> [Page] {
        (outgoingLinks ?? [])
            .filter { $0.role == role && !$0.isDeleted }
            .compactMap(\.target)
            .sorted { ($0.title.localizedLowercase, $0.id.uuidString) < ($1.title.localizedLowercase, $1.id.uuidString) }
    }

    /// Links to a page with a role, unless it already does or the target is this page. Returns whether it was added.
    @discardableResult
    func addLink(to target: Page, role: String, in context: ModelContext) -> Bool {
        guard target !== self, target.world?.id == world?.id,
              !(outgoingLinks ?? []).contains(where: { $0.role == role && $0.target === target && !$0.isDeleted })
        else { return false }
        context.insert(PageLink(source: self, target: target, role: role))
        return true
    }

    func removeLinks(to target: Page, role: String, in context: ModelContext) {
        for link in outgoingLinks ?? [] where link.role == role && link.target === target {
            context.delete(link)
        }
    }
}

extension World {
    @discardableResult
    func addCampaign(named name: String, in context: ModelContext) -> Campaign {
        let campaign = Campaign(name: name)
        context.insert(campaign)
        campaign.world = self
        return campaign
    }

    /// Deletes a campaign. Its events are kept, and become backstory.
    func deleteCampaign(_ campaign: Campaign, in context: ModelContext) {
        for event in campaign.events ?? [] {
            event.setCampaign(nil)
        }
        context.delete(campaign)
    }
}
