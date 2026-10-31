//
//  PlaceHierarchySection.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Where a place sits: breadcrumbs up to the top, a picker for what it is inside, and the places inside it.
struct PlaceHierarchySection: View {
    @Bindable var page: Page

    @Environment(\.modelContext) private var modelContext
    @Environment(WorldNavigation.self) private var navigation
    @Query private var places: [Page]

    init(page: Page) {
        self.page = page
        let worldID = page.world?.id
        let kindRaw = PageKind.place.rawValue
        _places = Query(
            filter: #Predicate<Page> { $0.world?.id == worldID && $0.kindRaw == kindRaw },
            sort: \Page.title
        )
    }

    var body: some View {
        Section("Location") {
            if !page.ancestors.isEmpty {
                breadcrumbs
            }
            if !page.isWorldRoot {
                Picker("Located In", selection: parentBinding) {
                    // A place with no root place above it (an older world) can still be left at the top.
                    if page.world?.rootPlaceID == nil { Text("Nowhere (Top Level)").tag(Page?.none) }
                    ForEach(candidates) { place in
                        Text(place.isWorldRoot ? worldName(of: place) : place.pathTitle).tag(Optional(place))
                    }
                }
            }
            if page.parentSource == .automatic && !page.isWorldRoot {
                Text("Worked out from where this place is. Choose a place to override it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(page.childPages) { child in
                Button {
                    navigation.open(child)
                } label: {
                    Label(child.title.isEmpty ? String(localized: "Untitled") : child.title, systemImage: child.kind.systemImage)
                }
                .buttonStyle(.plain)
            }
            Button("Add Place Here", systemImage: "plus", action: addChild)
        }
        mapsSection
    }

    /// The maps of this place, and a way to add one. The world has a single map, and other places can have several,
    /// such as a building with a map for each floor.
    private var mapsSection: some View {
        Section(page.isWorldRoot ? "World Map" : "Maps") {
            ForEach(page.sortedMaps) { map in
                Button {
                    navigation.openMap(map)
                } label: {
                    Label(map.name.isEmpty ? String(localized: "Untitled Map") : map.name, systemImage: map.kind.systemImage)
                }
                .buttonStyle(.plain)
            }
            if !(page.isWorldRoot && !page.sortedMaps.isEmpty) {
                AddMapControls(place: page)
            }
        }
    }

    private func worldName(of root: Page) -> String {
        root.title.isEmpty ? String(localized: "The World") : root.title
    }

    /// The path from the top, each part opening that place. The last part is this page, so it isn't a button.
    private var breadcrumbs: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(page.ancestors.reversed()), id: \.id) { ancestor in
                    Button(ancestor.title.isEmpty ? String(localized: "Untitled") : ancestor.title) {
                        navigation.open(ancestor)
                    }
                    .buttonStyle(.borderless)
                    Image(systemName: "chevron.right")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(page.title.isEmpty ? String(localized: "Untitled") : page.title)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Places this one may sit inside: anything but itself and the places inside it.
    private var candidates: [Page] {
        places
            .filter { page.canHaveParent($0) }
            .sorted { $0.pathTitle.localizedStandardCompare($1.pathTitle) == .orderedAscending }
    }

    private var parentBinding: Binding<Page?> {
        Binding(
            get: { page.parent },
            set: { page.setParent($0) }
        )
    }

    private func addChild() {
        guard let world = page.world else { return }
        let child = world.addPage(kind: .place, in: modelContext)
        child.parent = page
        navigation.open(child)
    }
}
