//
//  PagePickerSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Chooses a page of some kinds from a world, with a search field. Used to add an event's participants.
struct PagePickerSheet: View {
    let title: LocalizedStringResource
    let world: World
    let kinds: [PageKind]
    let excluding: Set<UUID>
    let onPick: (Page) -> Void
    let onCancel: () -> Void

    @Query private var pages: [Page]
    @State private var search = ""

    init(
        title: LocalizedStringResource, world: World, kinds: [PageKind], excluding: Set<UUID> = [],
        onPick: @escaping (Page) -> Void, onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.world = world
        self.kinds = kinds
        self.excluding = excluding
        self.onPick = onPick
        self.onCancel = onCancel
        let worldID = world.id
        let kindRaws = kinds.map(\.rawValue)
        _pages = Query(
            filter: #Predicate<Page> { $0.world?.id == worldID && kindRaws.contains($0.kindRaw) },
            sort: \Page.title
        )
    }

    private var matches: [Page] {
        pages.filter { !excluding.contains($0.id) && (search.isEmpty || $0.title.localizedStandardContains(search)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(title)
                .font(.headline)
                .padding()
            TextField("Search", text: $search)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal)
            if matches.isEmpty {
                ContentUnavailableView(search.isEmpty ? "Nothing to Add" : "No Matches", systemImage: "person.crop.circle.badge.questionmark")
            } else {
                List(matches) { page in
                    Button {
                        onPick(page)
                    } label: {
                        Label {
                            Text(page.title.isEmpty ? String(localized: "Untitled") : page.title)
                        } icon: {
                            Image(systemName: page.kind.systemImage)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                    .keyboardShortcut(.cancelAction)
            }
            .padding()
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}
