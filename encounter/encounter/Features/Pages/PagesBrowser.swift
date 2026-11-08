//
//  PagesBrowser.swift
//  encounter
//

import SwiftUI
import SwiftData

/// One kind of page in a world, with no library entries to mix in: the list of pages, which the selected page's editor takes the place of.
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
            // The detail area of a split view has no navigation stack of its own on the Mac, so the list and the page swap
            // places here. The window's back button, or choosing the kind in the sidebar again, returns to the list.
            if let page = navigation.selectedPage {
                PageEditorView(page: page)
                    .id(page.id)
            } else {
                PageListView(world: world, kind: kind, selection: selectedPage)
            }
        } else {
            // The page opens on top of the list, in the navigation stack the world is already in, so it has the whole width.
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

#if DEBUG
@MainActor
private func charactersPreview(_ width: WindowWidth) -> some View {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world {
            PagesBrowser(world: world, kind: .character)
        }
    }
    .environment(WorldNavigation())
    .modelContainer(container)
    .inWindow(width)
}

#Preview("Characters, strip (320)") { charactersPreview(.strip) }
#Preview("Characters, half screen (507)") { charactersPreview(.half) }
#Preview("Characters, 678") { charactersPreview(.wide) }
#endif
