//
//  PageReferenceField.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Picks another page of a given kind from the same world, such as a character's race.
struct PageReferenceField: View {
    let label: LocalizedStringResource
    let kind: PageKind
    let role: String
    @Bindable var page: Page

    @Environment(\.modelContext) private var modelContext
    @Query private var candidates: [Page]

    init(label: LocalizedStringResource, kind: PageKind, role: String, page: Page) {
        self.label = label
        self.kind = kind
        self.role = role
        self.page = page
        let worldID = page.world?.id
        let kindRaw = kind.rawValue
        _candidates = Query(
            filter: #Predicate<Page> { $0.world?.id == worldID && $0.kindRaw == kindRaw },
            sort: \Page.title
        )
    }

    var body: some View {
        if candidates.isEmpty {
            LabeledContent {
                Text("None yet. Add one under \(String(localized: kind.title)).")
                    .foregroundStyle(.secondary)
            } label: {
                Text(label)
            }
        } else {
            Picker(selection: selection) {
                Text("None").tag(Page?.none)
                ForEach(candidates) { candidate in
                    Text(candidate.title.isEmpty ? String(localized: "Untitled") : candidate.title)
                        .tag(Page?.some(candidate))
                }
            } label: {
                Text(label)
            }
        }
    }

    private var selection: Binding<Page?> {
        Binding(
            get: { page.linkedPage(role: role) },
            set: { page.setLinkedPage($0, role: role, in: modelContext) }
        )
    }
}
