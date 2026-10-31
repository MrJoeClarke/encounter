//
//  PageListView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The pages of one kind in a world, with create and delete.
struct PageListView: View {
    let world: World
    let kind: PageKind
    @Binding var selection: Page?

    @Environment(\.modelContext) private var modelContext
    @Query private var pages: [Page]
    @State private var pageToDelete: Page?
    @State private var isBuildingCharacter = false

    init(world: World, kind: PageKind, selection: Binding<Page?>) {
        self.world = world
        self.kind = kind
        _selection = selection
        let worldID = world.id
        let kindRaw = kind.rawValue
        _pages = Query(
            filter: #Predicate<Page> { $0.world?.id == worldID && $0.kindRaw == kindRaw },
            sort: \Page.title
        )
    }

    var body: some View {
        Group {
            if pages.isEmpty {
                ContentUnavailableView {
                    Label {
                        Text(kind.title)
                    } icon: {
                        Image(systemName: kind.systemImage)
                    }
                } description: {
                    Text("Nothing here yet.")
                } actions: {
                    Button("New \(String(localized: kind.singularTitle))", action: addPage)
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List(selection: $selection) {
                    ForEach(pages) { page in
                        PageRow(page: page)
                            .tag(page)
                            .contextMenu {
                                Button("Delete…", systemImage: "trash", role: .destructive) { pageToDelete = page }
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) { pageToDelete = page }
                            }
                    }
                }
            }
        }
        .navigationTitle(Text(kind.title))
        .toolbar { toolbarItems }
        .sheet(isPresented: $isBuildingCharacter) {
            CharacterBuilderView(world: world) { selection = $0 }
        }
        .alert(
            "Delete Page?",
            isPresented: Binding(get: { pageToDelete != nil }, set: { if !$0 { pageToDelete = nil } }),
            presenting: pageToDelete
        ) { page in
            Button("Delete", role: .destructive) { delete(page) }
            Button("Cancel", role: .cancel) {}
        } message: { page in
            Text("“\(page.title.isEmpty ? String(localized: "Untitled") : page.title)” and its links will be deleted. This can’t be undone.")
        }
    }

    /// A character list in a world with a content library can also build a character from it.
    private var canBuildCharacter: Bool {
        kind == .character && RuleSystems.system(for: world.system).hasContentLibrary
    }

    @ToolbarContentBuilder
    private var toolbarItems: some ToolbarContent {
        if canBuildCharacter {
            ToolbarItem {
                Button("Build Character…", systemImage: "wand.and.stars") { isBuildingCharacter = true }
            }
        }
        ToolbarItem {
            Button("New \(String(localized: kind.singularTitle))", systemImage: "plus", action: addPage)
        }
    }

    private func addPage() {
        selection = world.addPage(kind: kind, in: modelContext)
    }

    private func delete(_ page: Page) {
        // Clear the selection first so the detail pane never shows a deleted page.
        if selection == page { selection = nil }
        modelContext.delete(page)
    }
}

private struct PageRow: View {
    let page: Page

    private let thumbnailSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                if page.title.isEmpty {
                    Text("Untitled")
                        .foregroundStyle(.secondary)
                } else {
                    Text(page.title)
                }
                if !page.summary.isEmpty {
                    Text(page.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    /// The default image's thumbnail, or the kind's icon if the page has no image.
    @ViewBuilder
    private var thumbnail: some View {
        if let data = page.defaultImage?.thumbnailData {
            DataImage(data: data)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: page.kind.systemImage)
                .foregroundStyle(.secondary)
                .frame(width: thumbnailSize, height: thumbnailSize)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
        }
    }
}
