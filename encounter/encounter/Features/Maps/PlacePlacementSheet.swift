//
//  PlacePlacementSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Chooses what to put at a spot on a map: a new place, or a place that has no position yet.
struct PlacePlacementSheet: View {
    let world: World
    let onCancel: () -> Void
    /// Called with the place to put there, which is new if `isNew`. The place is created only when this runs.
    let onPlace: (_ title: String, _ placeType: String?, _ existing: Page?) -> Void

    private enum Mode: Hashable { case new, existing }

    @Query private var unplaced: [Page]
    @State private var mode: Mode = .new
    @State private var title = ""
    @State private var placeType: String = "Settlement"
    @State private var existing: Page?
    @FocusState private var titleIsFocused: Bool

    init(world: World, onCancel: @escaping () -> Void, onPlace: @escaping (String, String?, Page?) -> Void) {
        self.world = world
        self.onCancel = onCancel
        self.onPlace = onPlace
        let worldID = world.id
        let kindRaw = PageKind.place.rawValue
        _unplaced = Query(
            filter: #Predicate<Page> { $0.world?.id == worldID && $0.kindRaw == kindRaw && $0.geometryData == nil },
            sort: \Page.title
        )
    }

    /// The kinds of place offered, from the Place Type attribute.
    private static let placeTypes: [String] = {
        if case .choice(let options)? = CoreAttributes.all.first(where: { $0.key == "core.placeType" })?.type { return options }
        return []
    }()

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Picker("Put", selection: $mode) {
                    Text("A New Place").tag(Mode.new)
                    Text("An Existing Place").tag(Mode.existing)
                }
                .pickerStyle(.segmented)

                switch mode {
                case .new:
                    TextField("Name", text: $title)
                        .focused($titleIsFocused)
                    Picker("Type", selection: $placeType) {
                        ForEach(Self.placeTypes, id: \.self) { Text($0).tag($0) }
                    }
                case .existing:
                    if unplaced.isEmpty {
                        Text("Every place already has a position. To move one, drag it on the map.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Place", selection: $existing) {
                            Text("Choose…").tag(Page?.none)
                            ForEach(unplaced) { page in
                                Text(page.title.isEmpty ? String(localized: "Untitled") : page.title).tag(Optional(page))
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Add") {
                    switch mode {
                    case .new: onPlace(title.trimmingCharacters(in: .whitespacesAndNewlines), placeType, nil)
                    case .existing: onPlace("", nil, existing)
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdd)
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 240)
        #endif
        .onAppear { titleIsFocused = true }
    }

    private var canAdd: Bool {
        switch mode {
        case .new: !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .existing: existing != nil
        }
    }
}

#Preview("Place on map") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return Group {
        if let world {
            PlacePlacementSheet(world: world, onCancel: {}, onPlace: { _, _, _ in })
        }
    }
    .frame(width: 420, height: 280)
    .modelContainer(container)
}

#if DEBUG
#Preview("Place on map, Slide Over strip (320)") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return Group {
        if let world {
            PlacePlacementSheet(world: world, onCancel: {}, onPlace: { _, _, _ in })
        }
    }
    .modelContainer(container)
    .inWindow(.strip, height: 500)
}
#endif
