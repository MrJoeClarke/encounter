//
//  MentionResults.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Pages in a world that match a search, to choose one to mention. Used for the suggestions that appear
/// while typing `@` and for the Mention Page picker.
struct MentionResults: View {
    let showsWhenEmpty: Bool
    let onSelect: (Page) -> Void

    @Query private var pages: [Page]

    /// - Parameters:
    ///   - excluding: The page being edited, which can't mention itself.
    ///   - search: Matched against titles. Empty matches every page.
    ///   - showsWhenEmpty: Whether to say so when nothing matches, or show nothing at all.
    init(world: World, excluding pageID: UUID, search: String, limit: Int = 8, showsWhenEmpty: Bool, onSelect: @escaping (Page) -> Void) {
        self.showsWhenEmpty = showsWhenEmpty
        self.onSelect = onSelect

        let worldID = world.id
        let predicate: Predicate<Page>
        if search.isEmpty {
            predicate = #Predicate<Page> { $0.world?.id == worldID && $0.id != pageID }
        } else {
            predicate = #Predicate<Page> { $0.world?.id == worldID && $0.id != pageID && $0.title.localizedStandardContains(search) }
        }
        var descriptor = FetchDescriptor<Page>(predicate: predicate, sortBy: [SortDescriptor(\.title)])
        descriptor.fetchLimit = limit
        _pages = Query(descriptor)
    }

    var body: some View {
        if pages.isEmpty {
            if showsWhenEmpty {
                Text("No matching pages.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(pages) { page in
                    Button {
                        onSelect(page)
                    } label: {
                        MentionResultRow(page: page)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if page.id != pages.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct MentionResultRow: View {
    let page: Page

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(Mention.displayTitle(of: page.title))
                Text(page.kind.singularTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let data = page.defaultImage?.thumbnailData {
            DataImage(data: data)
                .frame(width: 28, height: 28)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: page.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
        }
    }
}

/// The Mention Page picker: search the world's pages and choose one.
struct MentionPickerSheet: View {
    let world: World
    let pageID: UUID
    let onSelect: (Page) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search pages", text: $search)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    MentionResults(world: world, excluding: pageID, search: search, limit: 30, showsWhenEmpty: true) { page in
                        onSelect(page)
                        dismiss()
                    }
                }
            }
            .padding()
            .navigationTitle("Mention Page")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 420)
        #endif
    }
}
