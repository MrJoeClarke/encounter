//
//  WorldTimelineView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A world's events in the order they happened, grouped by year, with filters.
struct WorldTimelineView: View {
    let world: World

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation
    @State private var filter = TimelineFilter()

    /// The world's pages and campaigns come from the world itself, which updates this screen as they change. Queries
    /// were used first, but on a phone they made this screen update itself without end.
    private var pages: [Page] {
        (world.pages ?? []).filter { !$0.isDeleted }.sorted { $0.title.localizedLowercase < $1.title.localizedLowercase }
    }

    private var campaigns: [Campaign] {
        (world.campaigns ?? []).filter { !$0.isDeleted }.sorted { $0.createdAt < $1.createdAt }
    }

    private var events: [Page] { pages.filter { $0.kind == .event } }
    private var characters: [Page] { pages.filter { $0.kind == .character } }
    private var organisations: [Page] { pages.filter { $0.kind == .organisation } }
    private var places: [Page] { pages.filter { $0.kind == .place } }

    var body: some View {
        let groups = TimelineBuilder.groups(of: events, calendar: world.calendar, filter: filter)
        VStack(spacing: 0) {
            filterBar
            Divider()
            if events.isEmpty {
                ContentUnavailableView {
                    Label("No Events Yet", systemImage: "clock")
                } description: {
                    Text("Events are things that happened in your world. Give them dates and they will appear here in order.")
                } actions: {
                    Button("New Event", action: addEvent)
                        .buttonStyle(.borderedProminent)
                }
            } else if groups.isEmpty {
                ContentUnavailableView {
                    Label("No Events Match", systemImage: "line.3.horizontal.decrease.circle")
                } actions: {
                    Button("Clear Filters") { filter = TimelineFilter() }
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups) { group in
                            Section {
                                ForEach(group.events) { event in
                                    TimelineRow(event: event, calendar: world.calendar)
                                        .padding(.horizontal)
                                        .padding(.vertical, 8)
                                    Divider().padding(.leading)
                                }
                            } header: {
                                Text(Self.title(of: group))
                                    .font(.headline)
                                    .padding(.horizontal)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.bar)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Timeline")
        .toolbar {
            ToolbarItem {
                Button("New Event", systemImage: "plus", action: addEvent)
            }
        }
    }

    /// "Year 1492", or "No Date" for the events that have none.
    private static func title(of group: TimelineGroup) -> String {
        group.year.map { String(localized: "Year \(String($0))") } ?? String(localized: "No Date")
    }

    // MARK: Filters

    /// The filters. A Mac has them side by side. A phone is too narrow, so they are in one menu.
    @ViewBuilder
    private var filterBar: some View {
        #if os(macOS)
        HStack {
            originPicker.fixedSize()
            characterPicker.fixedSize()
            organisationPicker.fixedSize()
            placePicker.fixedSize()
            Spacer()
            if filter.isActive {
                Button("Clear Filters") { filter = TimelineFilter() }
            }
        }
        .padding()
        #else
        HStack {
            Menu {
                originPicker
                characterPicker
                organisationPicker
                placePicker
                if filter.isActive {
                    Button("Clear Filters", systemImage: "xmark.circle") { filter = TimelineFilter() }
                }
            } label: {
                Label(filter.isActive ? "Filtered" : "Filters", systemImage: filter.isActive ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
            }
            Spacer()
        }
        .padding()
        #endif
    }

    private var originPicker: some View {
        Picker("Show", selection: $filter.origin) {
            Text("Everything").tag(TimelineFilter.Origin.any)
            Text("Backstory").tag(TimelineFilter.Origin.backstory)
            ForEach(campaigns) { campaign in
                Text(campaign.name.isEmpty ? String(localized: "Untitled Campaign") : campaign.name)
                    .tag(TimelineFilter.Origin.campaign(campaign))
            }
        }
    }

    private var characterPicker: some View {
        pagePicker("Character", "Anyone", pages: characters, selection: $filter.character)
    }

    private var organisationPicker: some View {
        pagePicker("Organisation", "Any", pages: organisations, selection: $filter.organisation)
    }

    private var placePicker: some View {
        Picker("Place", selection: $filter.place) {
            Text("Anywhere").tag(Page?.none)
            ForEach(places.sorted { $0.pathTitle.localizedStandardCompare($1.pathTitle) == .orderedAscending }) { place in
                Text(place.isWorldRoot ? (place.title.isEmpty ? String(localized: "The World") : place.title) : place.pathTitle)
                    .tag(Optional(place))
            }
        }
    }

    private func pagePicker(_ title: LocalizedStringResource, _ none: LocalizedStringResource, pages: [Page], selection: Binding<Page?>) -> some View {
        Picker(selection: selection) {
            Text(none).tag(Page?.none)
            ForEach(pages) { page in
                Text(page.title.isEmpty ? String(localized: "Untitled") : page.title).tag(Optional(page))
            }
        } label: {
            Text(title)
        }
    }

    private func addEvent() {
        let event = world.addPage(kind: .event, in: modelContext)
        // Under a filter, the new event starts out matching it, so it doesn't vanish from the list.
        if case .campaign(let campaign) = filter.origin { event.setCampaign(campaign) }
        if let place = filter.place { event.setLinkedPage(place, role: LinkRole.location, in: modelContext) }
        if let character = filter.character { event.addLink(to: character, role: LinkRole.participant, in: modelContext) }
        if let organisation = filter.organisation { event.addLink(to: organisation, role: LinkRole.participant, in: modelContext) }
        navigation.open(event)
    }
}

/// One event in the timeline: when, what, where and who.
private struct TimelineRow: View {
    let event: Page
    let calendar: CalendarDefinition?

    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.open(event)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(whenText)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 220, alignment: .leading)
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title.isEmpty ? String(localized: "Untitled") : event.title)
                    if !details.isEmpty {
                        Text(details)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// "14 Frost 1203", or "14 Frost – 16 Frost 1203" for an event that spans dates.
    private var whenText: String {
        guard let calendar, let start = event.startDate, calendar.isValid(start) else { return String(localized: "No date") }
        guard let end = event.endDate, end != start, calendar.isValid(end) else { return calendar.format(start) }
        return calendar.format(start) + " – " + calendar.format(end)
    }

    /// Where it happened, who took part and which campaign it belongs to.
    private var details: String {
        var parts: [String] = []
        if let location = event.linkedPage(role: LinkRole.location), !location.title.isEmpty { parts.append(location.title) }
        let names = event.linkedPages(role: LinkRole.participant).map(\.title).filter { !$0.isEmpty }
        if !names.isEmpty {
            parts.append(names.count > 3 ? names.prefix(3).joined(separator: ", ") + " " + String(localized: "and \(names.count - 3) more") : names.joined(separator: ", "))
        }
        if let campaign = event.campaign, !campaign.name.isEmpty { parts.append(campaign.name) }
        return parts.joined(separator: " · ")
    }
}

#Preview("Timeline") {
    let container = SampleData.makePreviewContainer()
    let context = container.mainContext
    let world = (try? context.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    let calendar = world!.calendar
    let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
    let campaign = world!.addCampaign(named: "Tides of the Coast", in: context)
    func event(_ title: String, _ date: InWorldDate?, end: InWorldDate? = nil, place: String? = nil, who: [String] = [], campaign: Campaign? = nil) {
        let page = world!.addPage(kind: .event, in: context)
        page.title = title
        page.setStartDate(date, in: calendar)
        page.setEndDate(end, in: calendar)
        if let campaign { page.setCampaign(campaign) }
        if let place, let target = pages.first(where: { $0.title == place }) { page.setLinkedPage(target, role: LinkRole.location, in: context) }
        for name in who { if let target = pages.first(where: { $0.title == name }) { page.addLink(to: target, role: LinkRole.participant, in: context) } }
    }
    event("The Founding", InWorldDate(year: -300, month: 2, day: 14))
    event("The Great Drowning", InWorldDate(year: 1300, month: 9, day: 1), end: InWorldDate(year: 1300, month: 9, day: 4), place: "Neverwinter")
    event("Arrival at Neverwinter", InWorldDate(year: 1492, month: 3, day: 14, hour: 6), place: "Neverwinter", who: ["Aria Vale", "The Harpers"], campaign: campaign)
    event("A rumour reaches the docks", nil)
    return WorldTimelineView(world: world!)
        .environment(WorldNavigation())
        .frame(width: 900, height: 560)
        .modelContainer(container)
}
