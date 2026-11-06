//
//  EventSection.swift
//  encounter
//

import SwiftUI
import SwiftData

/// What makes an event an event: whether it is backstory or part of a campaign, when it happened, where, and who
/// took part.
struct EventSection: View {
    @Bindable var page: Page

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation
    @Query private var campaigns: [Campaign]
    @Query private var places: [Page]
    @State private var isAddingParticipant = false
    @State private var isNamingCampaign = false
    @State private var newCampaignName = ""

    init(page: Page) {
        self.page = page
        let worldID = page.world?.id
        let kindRaw = PageKind.place.rawValue
        _campaigns = Query(filter: #Predicate<Campaign> { $0.world?.id == worldID }, sort: \Campaign.name)
        _places = Query(filter: #Predicate<Page> { $0.world?.id == worldID && $0.kindRaw == kindRaw })
    }

    private var calendar: CalendarDefinition? { page.world?.calendar }

    var body: some View {
        ThemedSection("When") {
            originControls
            dateControls
        }
        ThemedSection("Where") {
            Picker("Location", selection: locationBinding) {
                Text("Not Set").tag(Page?.none)
                ForEach(sortedPlaces) { place in
                    Text(place.isWorldRoot ? worldTitle(of: place) : place.pathTitle).tag(Optional(place))
                }
            }
            if let location = page.linkedPage(role: LinkRole.location) {
                Button("Open \(location.title.isEmpty ? String(localized: "Place") : location.title)", systemImage: "arrow.up.right.square") {
                    navigation.open(location)
                }
                .buttonStyle(.plain)
            }
        }
        participantsSection
    }

    // MARK: Origin and campaign

    @ViewBuilder
    private var originControls: some View {
        Picker("Part Of", selection: originBinding) {
            ForEach(EventOrigin.allCases) { origin in
                Text(origin.title).tag(origin)
            }
        }
        if page.effectiveOrigin == .campaign {
            Picker("Campaign", selection: campaignBinding) {
                Text("None Chosen").tag(Campaign?.none)
                ForEach(campaigns) { campaign in
                    Text(campaign.name.isEmpty ? String(localized: "Untitled Campaign") : campaign.name).tag(Optional(campaign))
                }
            }
            Button("New Campaign…", systemImage: "plus") {
                newCampaignName = ""
                isNamingCampaign = true
            }
            if let campaign = page.campaign {
                Button("Open Campaign", systemImage: "flag") { navigation.openCampaign(campaign) }
                    .buttonStyle(.plain)
            }
        }
    }

    private var originBinding: Binding<EventOrigin> {
        Binding(get: { page.effectiveOrigin }, set: { page.setOrigin($0) })
    }

    private var campaignBinding: Binding<Campaign?> {
        Binding(get: { page.campaign }, set: { page.setCampaign($0) })
    }

    // MARK: Dates

    @ViewBuilder
    private var dateControls: some View {
        if let calendar {
            Toggle("Has a Date", isOn: Binding(
                get: { page.startDate != nil },
                set: { page.setStartDate($0 ? calendar.clamped(InWorldDate()) : nil, in: calendar) }
            ))
            if let start = page.startDate {
                InWorldDateField(calendar: calendar, date: Binding(
                    get: { start },
                    set: { page.setStartDate(calendar.clamped($0), in: calendar) }
                ))
                Toggle("Lasts Until Another Date", isOn: Binding(
                    get: { page.endDate != nil },
                    set: { page.setEndDate($0 ? start : nil, in: calendar) }
                ))
                if let end = page.endDate {
                    InWorldDateField(calendar: calendar, date: Binding(
                        get: { end },
                        set: { page.setEndDate(calendar.clamped($0), in: calendar) }
                    ))
                }
                LabeledContent("Reads As") {
                    Text(readableDates(start: start, end: page.endDate, in: calendar))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("This world has no calendar, so the event can’t be given a date.")
                .foregroundStyle(.secondary)
        }
    }

    private func readableDates(start: InWorldDate, end: InWorldDate?, in calendar: CalendarDefinition) -> String {
        guard let end, end != start else { return calendar.format(start, style: .long) }
        return calendar.format(start, style: .long) + " – " + calendar.format(end, style: .long)
    }

    // MARK: Location

    private var sortedPlaces: [Page] {
        places.sorted { $0.pathTitle.localizedStandardCompare($1.pathTitle) == .orderedAscending }
    }

    private func worldTitle(of root: Page) -> String {
        root.title.isEmpty ? String(localized: "The World") : root.title
    }

    private var locationBinding: Binding<Page?> {
        Binding(
            get: { page.linkedPage(role: LinkRole.location) },
            set: { page.setLinkedPage($0, role: LinkRole.location, in: modelContext) }
        )
    }

    // MARK: Participants

    private var participantsSection: some View {
        ThemedSection("Who Took Part") {
            let participants = page.linkedPages(role: LinkRole.participant)
            ForEach(participants) { participant in
                HStack {
                    Button {
                        navigation.open(participant)
                    } label: {
                        Label {
                            Text(participant.title.isEmpty ? String(localized: "Untitled") : participant.title)
                        } icon: {
                            Image(systemName: participant.kind.systemImage)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") {
                        page.removeLinks(to: participant, role: LinkRole.participant, in: modelContext)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
            }
            Button("Add Participant…", systemImage: "plus") { isAddingParticipant = true }
        }
        .sheet(isPresented: $isAddingParticipant) {
            if let world = page.world {
                PagePickerSheet(
                    title: "Add Participant",
                    world: world,
                    kinds: [.character, .organisation],
                    excluding: Set(page.linkedPages(role: LinkRole.participant).map(\.id)),
                    onPick: { picked in
                        page.addLink(to: picked, role: LinkRole.participant, in: modelContext)
                        isAddingParticipant = false
                    },
                    onCancel: { isAddingParticipant = false }
                )
            }
        }
        .alert("New Campaign", isPresented: $isNamingCampaign) {
            TextField("Name", text: $newCampaignName)
            Button("Create") {
                let name = newCampaignName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, let world = page.world else { return }
                page.setCampaign(world.addCampaign(named: name, in: modelContext))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The event will be part of it.")
        }
    }
}

#Preview("Event") {
    let container = SampleData.makePreviewContainer()
    let context = container.mainContext
    let world = (try? context.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    let event = world!.addPage(kind: .event, in: context)
    event.title = "Arrival at Neverwinter"
    let campaign = world!.addCampaign(named: "Tides of the Coast", in: context)
    event.setCampaign(campaign)
    event.setStartDate(InWorldDate(year: 1492, month: 3, day: 14, hour: 6), in: world!.calendar)
    event.setEndDate(InWorldDate(year: 1492, month: 3, day: 16, hour: 0), in: world!.calendar)
    let pages = (try? context.fetch(FetchDescriptor<Page>())) ?? []
    if let place = pages.first(where: { $0.title == "Neverwinter" }) { event.setLinkedPage(place, role: LinkRole.location, in: context) }
    for name in ["Aria Vale", "The Harpers"] {
        if let who = pages.first(where: { $0.title == name }) { event.addLink(to: who, role: LinkRole.participant, in: context) }
    }
    return Form { EventSection(page: event) }
        .formStyle(.grouped)
        .themedScreen()
        .themedRow()
        .environment(WorldNavigation())
        .frame(width: 560, height: 900)
        .modelContainer(container)
}
