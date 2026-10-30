//
//  WorldShellView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The working area for one world: page kinds, the pages of the selected kind, and a detail pane.
struct WorldShellView: View {
    let world: World

    @State private var selectedKind: PageKind = .character
    @State private var selectedPage: Page?

    var body: some View {
        NavigationSplitView {
            List(PageKind.allCases, selection: kindSelection) { kind in
                Label {
                    Text(kind.title)
                } icon: {
                    Image(systemName: kind.systemImage)
                }
                .badge(count(of: kind))
                .tag(kind)
            }
            .navigationTitle(world.name)
        } content: {
            PageListView(world: world, kind: selectedKind, selection: $selectedPage)
                .id(selectedKind)
        } detail: {
            if let selectedPage {
                PageEditorView(page: selectedPage)
                    .id(selectedPage.id)
            } else {
                ContentUnavailableView("No Page Selected", systemImage: "doc.text")
            }
        }
        .onChange(of: selectedKind) {
            selectedPage = nil
        }
    }

    /// The list reports nil selection on some clicks (notably on macOS). A kind is always selected, so ignore those.
    private var kindSelection: Binding<PageKind?> {
        Binding(
            get: { selectedKind },
            set: { if let kind = $0 { selectedKind = kind } }
        )
    }

    private func count(of kind: PageKind) -> Int {
        (world.pages ?? []).filter { $0.kind == kind }.count
    }
}

#Preview {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return Group {
        if let world {
            WorldShellView(world: world)
        }
    }
    .modelContainer(container)
}
