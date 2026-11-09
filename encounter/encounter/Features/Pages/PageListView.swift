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
    /// Places that are open in the outline.
    @State private var expanded: Set<UUID> = []

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
                    ThemedEmptyLabel(kind.title, systemImage: kind.systemImage)
                } description: {
                    Text(kind.emptyDescription)
                } actions: {
                    Group {
                        Button("New \(String(localized: kind.singularTitle))", action: addPage)
                            .buttonStyle(.borderedProminent)
                        if canBuildCharacter {
                            Button("Build Character…") { isBuildingCharacter = true }
                        }
                    }
                    .emptyStateButtons()
                }
            } else {
                ChoosableList(choice: $selection) {
                    ForEach(rows) { row in
                        let page = row.page
                        HStack(spacing: 4) {
                            if kind == .place { disclosure(for: row) }
                            PageRow(page: page)
                        }
                            .choosable(page, in: $selection)
                            .contextMenu {
                                OpenInNewWindowButtons(
                                    route: WindowRoute.page(page),
                                    sheetRoute: page.kind == .character && page.world?.rules.contains(.sheet) == true ? WindowRoute.page(page, showsSheet: true) : nil
                                )
                                if !page.isWorldRoot {
                                    Button("Delete…", systemImage: "trash", role: .destructive) { pageToDelete = page }
                                }
                            }
                            .swipeActions {
                                if !page.isWorldRoot {
                                    Button("Delete", systemImage: "trash", role: .destructive) { pageToDelete = page }
                                }
                            }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        .navigationTitle(Text(kind.title))
        .toolbar { toolbarItems }
        .onChange(of: selection, initial: true) { _, page in
            // Open the outline down to the selected place, so a place opened from elsewhere is visible.
            guard kind == .place else { return }
            // The root place is always open, so the places directly inside the world show.
            if let root = world.rootPlace { expanded.insert(root.id) }
            guard let page else { return }
            expanded.formUnion(page.ancestors.map(\.id))
        }
        .sheet(isPresented: $isBuildingCharacter) {
            if RuleSystems.system(forKey: world.systemRaw).usesGenericScreens {
                GenericCharacterBuilderView(world: world) { selection = $0 }
            } else {
                CharacterBuilderView(world: world) { selection = $0 }
            }
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
        kind == .character && world.rules.contains(.characterCreation)
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

    /// One line of the list. Places are an outline: top-level places first, with the contents of open places
    /// under them. Other kinds are flat.
    private struct OutlineRow: Identifiable {
        let page: Page
        let depth: Int
        let hasChildren: Bool
        var id: UUID { page.id }
    }

    private var rows: [OutlineRow] {
        guard kind == .place else {
            return pages.map { OutlineRow(page: $0, depth: 0, hasChildren: false) }
        }
        var result: [OutlineRow] = []
        func add(_ page: Page, depth: Int, visited: inout Set<UUID>) {
            guard visited.insert(page.id).inserted else { return }
            let children = page.childPages
            result.append(OutlineRow(page: page, depth: depth, hasChildren: !children.isEmpty))
            if expanded.contains(page.id) {
                for child in children { add(child, depth: depth + 1, visited: &visited) }
            }
        }
        var visited: Set<UUID> = []
        // A place whose parent isn't a place (or is missing from this world) is shown at the top level too.
        for page in pages where page.parent == nil || page.parent?.kindRaw != kind.rawValue {
            add(page, depth: 0, visited: &visited)
        }
        return result
    }

    private func disclosure(for row: OutlineRow) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: CGFloat(row.depth) * 16, height: 1)
            if row.hasChildren {
                Button {
                    if !expanded.insert(row.page.id).inserted { expanded.remove(row.page.id) }
                } label: {
                    Image(systemName: expanded.contains(row.page.id) ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .frame(width: 16, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded.contains(row.page.id) ? "Collapse" : "Expand")
            } else {
                Color.clear.frame(width: 16, height: 1)
            }
        }
    }

    private func addPage() {
        selection = world.addPage(kind: kind, in: modelContext)
    }

    private func delete(_ page: Page) {
        // The root place holds the whole world, so it can't be deleted on its own.
        guard !page.isWorldRoot else { return }
        // Clear the selection first so the detail pane never shows a deleted page.
        if selection == page { selection = nil }
        // Places inside a deleted place move up a level rather than being lost.
        page.liftChildrenToParent()
        modelContext.delete(page)
    }
}

struct PageRow: View {
    let page: Page

    private let thumbnailSize: CGFloat = 40

    var body: some View {
        HStack(spacing: 10) {
            ThemedThumbnail(data: page.defaultImage?.thumbnailData, systemName: page.kind.systemImage, size: thumbnailSize)
            VStack(alignment: .leading, spacing: 2) {
                if page.title.isEmpty {
                    Text("Untitled")
                        .foregroundStyle(.secondary)
                } else {
                    Text(page.title)
                        .themedTitle(.body)
                }
                if !page.summary.isEmpty {
                    Text(page.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            PublishMark(page: page)
        }
    }
}
