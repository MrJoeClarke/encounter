//
//  ContentReferenceField.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Picks what a page refers to for a role, such as a character's race or class: a page in the same world,
/// or, where the world's rule system has a content library, an entry from the library.
/// A page refers to one or the other, never both.
struct ContentReferenceField: View {
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
        let libraryEntries = availableLibraryEntries
        let currentKey = page.libraryKey(role: role)
        // A reference to an entry that isn't in this edition's list: another edition's, or one this app doesn't have.
        let strayKey = currentKey.flatMap { key in libraryEntries.contains { $0.key == key } ? nil : key }

        if candidates.isEmpty && libraryEntries.isEmpty && strayKey == nil {
            LabeledContent {
                Text("None yet. Add one under \(String(localized: kind.title)).")
                    .foregroundStyle(.secondary)
            } label: {
                Text(label)
            }
        } else {
            Picker(selection: selection) {
                Text("None").tag(ContentReference.none)

                if !candidates.isEmpty {
                    Section("This World") {
                        ForEach(candidates) { candidate in
                            Text(Mention.displayTitle(of: candidate.title))
                                .tag(ContentReference.page(candidate))
                        }
                    }
                }

                if !libraryEntries.isEmpty || strayKey != nil {
                    Section("Library") {
                        ForEach(libraryEntries) { entry in
                            Text(entry.name).tag(ContentReference.library(entry.key))
                        }
                        if let strayKey {
                            Text(strayLabel(for: strayKey)).tag(ContentReference.library(strayKey))
                        }
                    }
                }
            } label: {
                Text(label)
            }
        }
    }

    private var libraryKind: LibraryKind? {
        switch kind {
        case .race: .race
        case .characterClass: .class
        default: nil
        }
    }

    /// Library entries to offer: only for worlds whose rule system has a library, in the world's edition.
    private var availableLibraryEntries: [LibraryEntry] {
        guard let libraryKind, let world = page.world, RuleSystems.system(for: world.system).hasContentLibrary else {
            return []
        }
        // Races and classes only: a subclass is picked in a field of its own, once the class is chosen.
        return Library.shared.topLevelEntries(libraryKind, in: world.edition)
    }

    private func strayLabel(for key: String) -> String {
        guard let entry = Library.shared.entry(forKey: key) else {
            return String(localized: "Unavailable library entry")
        }
        return String(localized: "\(entry.name) (other edition)")
    }

    private var selection: Binding<ContentReference> {
        Binding(
            get: { page.reference(role: role) },
            set: { page.setReference($0, role: role, in: modelContext) }
        )
    }
}
