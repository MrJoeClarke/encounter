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
/// so the selection resets when the kind changes.
struct PagesBrowser: View {
    let world: World
    let kind: PageKind

    @State private var selectedPage: Page?

    var body: some View {
        #if os(macOS)
        HSplitView {
            PageListView(world: world, kind: kind, selection: $selectedPage)
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
                .layoutPriority(-1)
            detail
                .frame(minWidth: 360, idealWidth: 800, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #else
        NavigationSplitView {
            PageListView(world: world, kind: kind, selection: $selectedPage)
        } detail: {
            detail
        }
        #endif
    }

    @ViewBuilder
    private var detail: some View {
        if let selectedPage {
            PageEditorView(page: selectedPage)
                .id(selectedPage.id)
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
    .frame(width: 900, height: 600)
    .modelContainer(container)
}
