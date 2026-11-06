//
//  SearchResultsView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The results of the world's search field, with a filter for what to search. Choosing one opens it.
struct SearchResultsView: View {
    let world: World

    @Environment(WorldNavigation.self) private var navigation
    @Environment(\.modelContext) private var modelContext
    /// Re-runs the search when a page changes, which a `@Query` on pages makes happen.
    @Query private var pages: [Page]

    init(world: World) {
        self.world = world
        let worldID = world.id
        _pages = Query(filter: #Predicate<Page> { $0.world?.id == worldID })
    }

    var body: some View {
        @Bindable var navigation = navigation
        let hits = WorldSearch.search(navigation.searchText, in: world, scope: navigation.searchScope, context: modelContext)
        VStack(spacing: 0) {
            Picker("Search In", selection: $navigation.searchScope) {
                Text("Everything").tag(SearchScope.all)
                ForEach(world.visibleKinds) { kind in
                    Text(kind.title).tag(SearchScope.kind(kind))
                }
                if world.rules.contains(.library) {
                    Text("Library").tag(SearchScope.library)
                }
            }
            .padding()

            if hits.isEmpty {
                ContentUnavailableView.search(text: navigation.searchText)
            } else {
                List(hits) { hit in
                    Button { open(hit) } label: {
                        SearchHitRow(hit: hit)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .themedListRow()
                }
                .themedScreen()
            }
        }
        .navigationTitle("Search")
    }

    private func open(_ hit: SearchHit) {
        switch hit.target {
        case .page(let page): navigation.open(page)
        case .library(let entry): navigation.openLibraryEntry(entry)
        }
    }
}

private struct SearchHitRow: View {
    let hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Label {
                Text(hit.title.isEmpty ? String(localized: "Untitled") : hit.title)
            } icon: {
                Image(systemName: icon)
            }
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }

    private var icon: String {
        switch hit.target {
        case .page(let page): page.kind.systemImage
        case .library(let entry): entry.kind.systemImage
        }
    }

    /// What kind of thing it is, and the text that matched if the title didn't.
    private var detail: String {
        let kind: String = switch hit.target {
        case .page(let page): String(localized: page.kind.singularTitle)
        case .library(let entry): String(localized: "Library") + " · " + String(localized: entry.kindTitle)
        }
        guard let snippet = hit.snippet, !snippet.isEmpty else { return kind }
        let place: String = switch hit.field {
        case .tag: String(localized: "Tag")
        case .summary: String(localized: "Summary")
        case .notes: String(localized: "Notes")
        case .title: ""
        }
        return "\(kind) · \(place): \(snippet)"
    }
}
