//
//  PagesBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// One kind of page in a world: the list of pages beside the editor for the selected page.
///
/// This sits in the detail area of the world's sidebar split, so that screens such as the home page can
/// use the whole width instead of being squeezed into a middle column. The caller should give it `.id(kind)`
/// so its views are rebuilt when the kind changes. The open page lives in `WorldNavigation`, so a mention
/// or a "Referenced by" row can open a page from anywhere.
struct PagesBrowser: View {
    let world: World
    let kind: PageKind

    @Environment(WorldNavigation.self) private var navigation

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if showsSideBySide(sizeClass) {
            ListDetailSplit {
                PageListView(world: world, kind: kind, selection: selectedPage)
            } detail: {
                detail
            }
        } else {
            // The page opens on top of the list, in the navigation stack the world is already in.
            PageListView(world: world, kind: kind, selection: selectedPage)
                .navigationDestination(item: selectedPage) { page in
                    PageEditorView(page: page)
                        .id(page.id)
                        .environment(navigation)
                }
        }
    }

    private var selectedPage: Binding<Page?> {
        Binding(
            get: { navigation.selectedPage },
            set: { navigation.selectedPage = $0 }
        )
    }

    @ViewBuilder
    private var detail: some View {
        if let page = navigation.selectedPage {
            PageEditorView(page: page)
                .id(page.id)
        } else {
            ContentUnavailableView("No Page Selected", systemImage: "doc.text")
        }
    }
}

#Preview("Characters") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world {
            PagesBrowser(world: world, kind: .character)
        }
    }
    .environment(WorldNavigation())
    .frame(width: 900, height: 600)
    .modelContainer(container)
}
