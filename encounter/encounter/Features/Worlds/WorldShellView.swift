//
//  WorldShellView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// What's selected in a world's sidebar: its home page, one kind of page, or a list in the content library.
enum WorldSidebarItem: Hashable {
    case home
    case kind(PageKind)
    case worldMap
    case library(LibraryKind)
}

/// The working area for one world: a sidebar (home page, page kinds and the library) and, beside it, the
/// selection using the rest of the window.
struct WorldShellView: View {
    let world: World
    /// Called when the user deletes the world from its home page.
    let onDelete: (World) -> Void

    @State private var navigation = WorldNavigation()
    @Environment(LinkRouter.self) private var linkRouter

    private var isSearching: Bool {
        !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasLibrary: Bool {
        RuleSystems.system(for: world.system).hasContentLibrary
    }

    var body: some View {
        NavigationSplitView {
            List(selection: sidebarSelection) {
                Label("Home", systemImage: "house")
                    .tag(WorldSidebarItem.home)

                Label("World Map", systemImage: "map")
                    .tag(WorldSidebarItem.worldMap)

                Section("Pages") {
                    ForEach(world.visibleKinds) { kind in
                        Label {
                            Text(kind.title)
                        } icon: {
                            Image(systemName: kind.systemImage)
                        }
                        .badge(count(of: kind))
                        .tag(WorldSidebarItem.kind(kind))
                    }
                }

                if hasLibrary {
                    Section("Library") {
                        ForEach(Library.shared.listKinds(in: world.edition), id: \.self) { kind in
                            Label {
                                Text(kind.listTitle(in: world.edition))
                            } icon: {
                                Image(systemName: kind.systemImage)
                            }
                            .tag(WorldSidebarItem.library(kind))
                        }
                    }
                }
            }
            .navigationTitle(world.name)
        } detail: {
            if isSearching {
                SearchResultsView(world: world)
            } else {
                switch navigation.selection {
                case .home:
                    WorldHomeView(world: world, onDelete: onDelete)
                case .kind(let kind):
                    PagesBrowser(world: world, kind: kind)
                        .id(kind)
                case .worldMap:
                    WorldMapView(world: world)
                case .library(let kind):
                    LibraryBrowser(world: world, kind: kind)
                        .id(kind)
                }
            }
        }
        .searchable(text: $navigation.searchText, prompt: "Search \(world.name)")
        .environment(navigation)
        // Mention links that arrive from the system are opened in the world that's showing.
        .onAppear { linkRouter.activate(world: world, navigation: navigation) }
        .onDisappear { linkRouter.deactivate(navigation: navigation) }
        // If the rule system changes to one without a library while the library is showing, go home.
        .onChange(of: hasLibrary) {
            if !hasLibrary, case .library = navigation.selection {
                navigation.choose(.home)
            }
        }
    }

    /// The list reports nil selection on some clicks (notably on macOS). Something is always selected, so ignore those.
    private var sidebarSelection: Binding<WorldSidebarItem?> {
        Binding(
            get: { navigation.selection },
            set: { if let item = $0 { navigation.choose(item) } }
        )
    }

    private func count(of kind: PageKind) -> Int {
        (world.pages ?? []).filter { $0.kind == kind }.count
    }
}

#Preview("Home") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return Group {
        if let world {
            WorldShellView(world: world) { _ in }
        }
    }
    .environment(LinkRouter())
    .frame(width: 1100, height: 800)
    .modelContainer(container)
}
