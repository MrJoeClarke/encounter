//
//  CampaignsBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A world's campaigns: the list beside the selected campaign.
struct CampaignsBrowser: View {
    let world: World

    @Environment(WorldNavigation.self) private var navigation

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if showsSideBySide(sizeClass) {
            ListDetailSplit {
                CampaignsListView(world: world, selection: selectedCampaign)
            } detail: {
                detail
            }
        } else {
            // The campaign opens on top of the list, in the navigation stack the world is already in.
            CampaignsListView(world: world, selection: selectedCampaign)
                .navigationDestination(item: selectedCampaign) { campaign in
                    CampaignDetailView(campaign: campaign)
                        .id(campaign.id)
                        .environment(navigation)
                }
        }
    }

    private var selectedCampaign: Binding<Campaign?> {
        Binding(get: { navigation.selectedCampaign }, set: { navigation.selectedCampaign = $0 })
    }

    @ViewBuilder
    private var detail: some View {
        if let campaign = navigation.selectedCampaign {
            CampaignDetailView(campaign: campaign)
                .id(campaign.id)
        } else {
            ContentUnavailableView("No Campaign Selected", systemImage: "flag")
        }
    }
}

/// The world's campaigns, with create and delete.
struct CampaignsListView: View {
    let world: World
    @Binding var selection: Campaign?

    @Environment(\.modelContext) private var modelContext
    @Query private var campaigns: [Campaign]
    @State private var campaignToDelete: Campaign?

    init(world: World, selection: Binding<Campaign?>) {
        self.world = world
        _selection = selection
        let worldID = world.id
        _campaigns = Query(filter: #Predicate<Campaign> { $0.world?.id == worldID }, sort: \Campaign.createdAt)
    }

    var body: some View {
        Group {
            if campaigns.isEmpty {
                ContentUnavailableView {
                    Label("Campaigns", systemImage: "flag")
                } description: {
                    Text("A campaign groups the events of one game you run in this world. Events that aren’t part of one are backstory.")
                } actions: {
                    Button("New Campaign", action: addCampaign)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ChoosableList(choice: $selection) {
                    ForEach(campaigns) { campaign in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(campaign.name.isEmpty ? String(localized: "Untitled Campaign") : campaign.name)
                                Text("^[\((campaign.events ?? []).count) event](inflect: true)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "flag.fill")
                        }
                        .choosable(campaign, in: $selection)
                        .contextMenu {
                            Button("Delete…", systemImage: "trash", role: .destructive) { campaignToDelete = campaign }
                        }
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { campaignToDelete = campaign }
                        }
                    }
                }
            }
        }
        .navigationTitle("Campaigns")
        .toolbar {
            ToolbarItem {
                Button("New Campaign", systemImage: "plus", action: addCampaign)
            }
        }
        .alert(
            "Delete Campaign?",
            isPresented: Binding(get: { campaignToDelete != nil }, set: { if !$0 { campaignToDelete = nil } }),
            presenting: campaignToDelete
        ) { campaign in
            Button("Delete", role: .destructive) { delete(campaign) }
            Button("Cancel", role: .cancel) {}
        } message: { campaign in
            Text("“\(campaign.name.isEmpty ? String(localized: "Untitled Campaign") : campaign.name)” will be deleted. Its events are kept, and become backstory.")
        }
    }

    private func addCampaign() {
        selection = world.addCampaign(named: "", in: modelContext)
    }

    private func delete(_ campaign: Campaign) {
        // Clear the selection first so the detail pane never shows a deleted campaign.
        if selection == campaign { selection = nil }
        world.deleteCampaign(campaign, in: modelContext)
    }
}

/// One campaign: its name and summary, and its events.
struct CampaignDetailView: View {
    @Bindable var campaign: Campaign

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $campaign.name, prompt: Text("Untitled Campaign"))
                    .font(.title2.weight(.semibold))
            }
            Section("Summary") {
                TextEditor(text: $campaign.summary)
                    .frame(minHeight: 120)
            }
            Section("Events") {
                let events = sortedEvents
                ForEach(events) { event in
                    Button {
                        navigation.open(event)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Label {
                                Text(event.title.isEmpty ? String(localized: "Untitled") : event.title)
                            } icon: {
                                Image(systemName: event.kind.systemImage)
                            }
                            if let start = event.startDate, let calendar = campaign.world?.calendar {
                                Text(calendar.format(start))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                if events.isEmpty {
                    Text("No events yet.")
                        .foregroundStyle(.secondary)
                }
                Button("New Event in This Campaign", systemImage: "plus", action: addEvent)
            }
        }
        .formStyle(.grouped)
        .navigationTitle(campaign.name.isEmpty ? String(localized: "Untitled Campaign") : campaign.name)
    }

    /// The campaign's events by date, with undated events last.
    private var sortedEvents: [Page] {
        let calendar = campaign.world?.calendar
        func hour(_ event: Page) -> Int? { event.startDate.flatMap { calendar?.absoluteHour(of: $0) } }
        return (campaign.events ?? []).filter { !$0.isDeleted }.sorted { a, b in
            switch (hour(a), hour(b)) {
            case let (x?, y?): x != y ? x < y : a.title < b.title
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): a.title < b.title
            }
        }
    }

    private func addEvent() {
        guard let world = campaign.world else { return }
        let event = world.addPage(kind: .event, in: modelContext)
        event.setCampaign(campaign)
        navigation.open(event)
    }
}
