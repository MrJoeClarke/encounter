//
//  MentionResults.swift
//  encounter
//

import SwiftUI
import SwiftData

/// What can be mentioned: a page in the world, or an entry in the content library.
enum MentionChoice: Identifiable {
    case page(Page)
    case library(LibraryEntry)

    var id: String {
        switch self {
        case .page(let page): "page/\(page.id.uuidString)"
        case .library(let entry): "library/\(entry.key)"
        }
    }
}

/// Pages in a world, and library entries where its rule system has a library, that match a search, to choose
/// one to mention. Used for the suggestions that appear while typing `@` and for the Mention picker.
struct MentionResults: View {
    let showsWhenEmpty: Bool
    let libraryEntries: [LibraryEntry]
    let onSelect: (MentionChoice) -> Void

    @Query private var pages: [Page]

    /// - Parameters:
    ///   - excluding: The page being edited, which can't mention itself.
    ///   - search: Matched against titles and library names. Empty matches every page, and every library
    ///     entry too if `showsWhenEmpty` (the picker), so typing a bare `@` suggests pages only.
    ///   - showsWhenEmpty: Whether to say so when nothing matches, or show nothing at all.
    init(world: World, excluding pageID: UUID, search: String, limit: Int = 8, showsWhenEmpty: Bool, onSelect: @escaping (MentionChoice) -> Void) {
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

        if RuleSystems.system(for: world.system).hasContentLibrary, !search.isEmpty || showsWhenEmpty {
            libraryEntries = Library.shared.mentionableEntries(matching: search, in: world.edition, limit: limit)
        } else {
            libraryEntries = []
        }
    }

    private var choices: [MentionChoice] {
        pages.map(MentionChoice.page) + libraryEntries.map(MentionChoice.library)
    }

    var body: some View {
        let choices = choices
        if choices.isEmpty {
            if showsWhenEmpty {
                Text("No matching pages.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(choices) { choice in
                    Button {
                        onSelect(choice)
                    } label: {
                        MentionResultRow(choice: choice)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if choice.id != choices.last?.id {
                        Divider()
                    }
                }
            }
        }
    }
}

private struct MentionResultRow: View {
    let choice: MentionChoice

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var title: String {
        switch choice {
        case .page(let page): Mention.displayTitle(of: page.title)
        case .library(let entry): entry.name
        }
    }

    private var subtitle: LocalizedStringResource {
        switch choice {
        case .page(let page): page.kind.singularTitle
        case .library(let entry): "Library · \(String(localized: entry.kindTitle))"
        }
    }

    @ViewBuilder
    private var thumbnail: some View {
        switch choice {
        case .page(let page):
            if let data = page.defaultImage?.thumbnailData {
                DataImage(data: data)
                    .frame(width: 28, height: 28)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
            } else {
                icon(page.kind.systemImage)
            }
        case .library(let entry):
            icon(entry.kind.systemImage)
        }
    }

    private func icon(_ name: String) -> some View {
        Image(systemName: name)
            .foregroundStyle(.secondary)
            .frame(width: 28, height: 28)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
    }
}

/// The Mention Page picker: search the world's pages and choose one.
struct MentionPickerSheet: View {
    let world: World
    let pageID: UUID
    let onSelect: (MentionChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Search pages and library", text: $search)
                    .textFieldStyle(.roundedBorder)
                ScrollView {
                    MentionResults(world: world, excluding: pageID, search: search, limit: 30, showsWhenEmpty: true) { choice in
                        onSelect(choice)
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
