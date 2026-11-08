//
//  ContentBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A list of the world's own pages and the library's entries of one kind, with a filter between them. A row opens the page's editor or
/// the entry's screen across the whole detail area, and choosing the list in the sidebar again comes back to it.
struct ContentBrowser: View {
    let world: World
    let list: ContentList

    @Environment(WorldNavigation.self) private var navigation
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.appTheme) private var theme
    /// The filter chosen for this list in this world, kept between launches.
    @AppStorage private var filterRaw: String
    @State private var pageToDelete: Page?

    init(world: World, list: ContentList) {
        self.world = world
        self.list = list
        _filterRaw = AppStorage(wrappedValue: ContentFilter.all.rawValue, "contentFilter.\(world.id.uuidString).\(list.storageKey)")
    }

    var body: some View {
        if showsSideBySide(sizeClass) {
            if let page = navigation.selectedPage {
                PageEditorView(page: page)
                    .id(page.id)
            } else if let key = navigation.selectedLibraryKey, let entry = Library.shared.entry(forKey: key) {
                LibraryEntryView(entry: entry, world: world)
                    .id(entry.key)
            } else {
                listView
            }
        } else {
            // The page or entry opens on top of the list, in the navigation stack the world is already in.
            listView
                .navigationDestination(item: openPage) { page in
                    PageEditorView(page: page)
                        .id(page.id)
                        .environment(navigation)
                }
                .navigationDestination(item: openLibraryKey) { key in
                    if let entry = Library.shared.entry(forKey: key) {
                        LibraryEntryView(entry: entry, world: world)
                            .id(entry.key)
                            .environment(navigation)
                    }
                }
        }
    }

    // MARK: The filter

    private var filters: [ContentFilter] { list.filters(in: world) }

    /// The chosen filter, or all if the one kept isn't offered here any more.
    private var filter: ContentFilter {
        let kept = ContentFilter(rawValue: filterRaw) ?? .all
        return filters.contains(kept) || filters.isEmpty ? (filters.isEmpty ? .all : kept) : .all
    }

    private var filterBinding: Binding<ContentFilter> {
        Binding(get: { filter }, set: { filterRaw = $0.rawValue })
    }

    @ViewBuilder
    private var filterPicker: some View {
        if filters.count > 1 {
            Group {
                if typeSize.isAccessibilitySize {
                    Picker("Show", selection: filterBinding) { ForEach(filters) { Text($0.title).tag($0) } }
                        .pickerStyle(.menu)
                } else {
                    // Drawn here, not a system segmented control, whose labels take no colour from the theme and went pale on the paper.
                    HStack(spacing: 4) {
                        ForEach(filters) { option in
                            let isSelected = option == filter
                            Button { filterBinding.wrappedValue = option } label: {
                                Text(option.title)
                                    .font(.subheadline.weight(.medium))
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                                    .padding(.vertical, 6)
                                    .frame(maxWidth: .infinity)
                                    .foregroundStyle(isSelected ? (theme.background?.themeColor ?? Color.white) : (theme.ink?.themeColor ?? Color.primary))
                                    .background(isSelected ? (theme.accent?.themeColor ?? Color.accentColor) : Color.clear, in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(isSelected ? .isSelected : [])
                        }
                    }
                    .padding(3)
                    .background(theme.panel?.themeColor ?? Color.secondary.opacity(0.15), in: Capsule())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }

    // MARK: The list

    private var rows: [ContentRow] {
        ContentLists.rows(in: list, world: world, filter: filter)
    }

    @ViewBuilder
    private var listView: some View {
        let rows = rows
        Group {
            if rows.isEmpty {
                ContentUnavailableView {
                    ThemedEmptyLabel(list.title(in: world), systemImage: list.systemImage(in: world))
                } description: {
                    Text(emptyDescription)
                } actions: {
                    if filter != .library && filter != .active {
                        Button("New \(String(localized: list.pageKind.singularTitle))", action: addPage)
                            .buttonStyle(.borderedProminent)
                            .emptyStateButtons()
                    }
                }
            } else {
                ChoosableList(choice: selection) {
                    ForEach(rows) { row in
                        rowView(row)
                            .choosable(row.id, in: selection)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedBackground()
        .safeAreaInset(edge: .top, spacing: 0) { filterPicker }
        .navigationTitle(Text(list.title(in: world)))
        .toolbar {
            ToolbarItem {
                Button("New \(String(localized: list.pageKind.singularTitle))", systemImage: "plus", action: addPage)
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

    private var emptyDescription: LocalizedStringResource {
        switch filter {
        case .active: "Items appear here when a character’s equipment lists them or a character links to them."
        case .library: "The library has no entries of this kind."
        case .mine, .all: list.pageKind.emptyDescription
        }
    }

    @ViewBuilder
    private func rowView(_ row: ContentRow) -> some View {
        switch row {
        case .page(let page):
            PageRow(page: page)
                .contextMenu {
                    OpenInNewWindowButtons(route: WindowRoute.page(page), sheetRoute: nil)
                    Button("Delete…", systemImage: "trash", role: .destructive) { pageToDelete = page }
                }
                .swipeActions {
                    Button("Delete", systemImage: "trash", role: .destructive) { pageToDelete = page }
                }
        case .library(let entry):
            HStack {
                LibraryRow(entry: entry, system: RuleSystems.system(forKey: world.systemRaw))
                if filter != .library {
                    Spacer(minLength: 4)
                    // Where it comes from, so the library's rows can be told from the world's own in a list of both.
                    Image(systemName: "books.vertical")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Library")
                }
            }
        }
    }

    // MARK: Selection

    /// The row that is open, as the list highlights it. A subrace or subclass is opened from its parent, so the parent is highlighted.
    private var selection: Binding<String?> {
        Binding(
            get: {
                if let page = navigation.selectedPage { return ContentRow.id(page: page) }
                guard let key = navigation.selectedLibraryKey else { return nil }
                return ContentRow.id(libraryKey: Library.shared.entry(forKey: key)?.parent ?? key)
            },
            set: { id in
                guard let id else {
                    navigation.selectedPage = nil
                    navigation.selectedLibraryKey = nil
                    return
                }
                if id.hasPrefix("page-"), let page = (world.pages ?? []).first(where: { ContentRow.id(page: $0) == id }) {
                    navigation.selectedLibraryKey = nil
                    navigation.selectedPage = page
                } else if id.hasPrefix("library-") {
                    navigation.selectedPage = nil
                    navigation.selectedLibraryKey = String(id.dropFirst("library-".count))
                }
            }
        )
    }

    private var openPage: Binding<Page?> {
        Binding(get: { navigation.selectedPage }, set: { navigation.selectedPage = $0 })
    }

    private var openLibraryKey: Binding<String?> {
        Binding(get: { navigation.selectedLibraryKey }, set: { navigation.selectedLibraryKey = $0 })
    }

    // MARK: Making and deleting pages

    private func addPage() {
        let page = world.addPage(kind: list.pageKind, in: modelContext)
        if list.pageKind == .contentEntry, let subKind = list.libraryList.subKind {
            page.setAttributeText(CoreAttributes.entryKindKey, subKind)
        }
        navigation.selectedLibraryKey = nil
        navigation.selectedPage = page
    }

    private func delete(_ page: Page) {
        // Clear the selection first so the detail area never shows a deleted page.
        if navigation.selectedPage == page { navigation.selectedPage = nil }
        modelContext.delete(page)
    }
}

#Preview("Races") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world, let list = ContentList(.kind(.race)) {
            ContentBrowser(world: world, list: list)
        }
    }
    .environment(WorldNavigation())
    .frame(width: 700, height: 600)
    .modelContainer(container)
    .inTheme(.parchment())
}

#Preview("Items") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world, let list = ContentList(.kind(.item)) {
            ContentBrowser(world: world, list: list)
        }
    }
    .environment(WorldNavigation())
    .frame(width: 700, height: 600)
    .modelContainer(container)
    .inTheme(.parchment())
}
