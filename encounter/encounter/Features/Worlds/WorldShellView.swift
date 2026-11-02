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
    case timeline
    case campaigns
    case library(LibraryList)
}

/// The working area for one world: a sidebar (home page, page kinds and the library) and, beside it, the
/// selection using the rest of the window.
struct WorldShellView: View {
    let world: World
    /// Called when the user deletes the world from its home page.
    let onDelete: (World) -> Void

    @State private var navigation = WorldNavigation()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LinkRouter.self) private var linkRouter
    @Environment(\.horizontalSizeClass) private var sizeClass

    private var isSearching: Bool {
        !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasLibrary: Bool {
        world.rules.contains(.library)
    }

    /// On iOS, whether the screen chosen from the menu is open on top of it.
    @State private var isShowingDetail = false
    /// Beside the screen, whether the menu is showing. Where it slides over the screen, choosing a row closes it.
    @State private var columnVisibility = NavigationSplitViewVisibility.automatic

    var body: some View {
        layout
            .searchable(text: $navigation.searchText, prompt: "Search \(world.name)")
            .environment(navigation)
            // Something opened from elsewhere (a link, a pin, a search result) shows its screen on a phone too.
            .onChange(of: navigation.selection) {
                isShowingDetail = true
                columnVisibility = .automatic
            }
            .onChange(of: navigation.selectedPage) { if navigation.selectedPage != nil { isShowingDetail = true } }
            .onChange(of: navigation.selectedMap) { if navigation.selectedMap != nil { isShowingDetail = true } }
            .onChange(of: navigation.selectedCampaign) { if navigation.selectedCampaign != nil { isShowingDetail = true } }
            .onChange(of: navigation.selectedLibraryKey) { if navigation.selectedLibraryKey != nil { isShowingDetail = true } }
            // What the menus can do in this world: go back and forward and between screens, and make a page.
            .focusedSceneValue(\.worldNavigation, navigation)
            .focusedSceneValue(\.worldActions, WorldActions(newPageTitle: String(localized: "New \(String(localized: navigation.newPageKind.singularTitle))")) {
                navigation.open(world.addPage(kind: navigation.newPageKind, in: modelContext))
            })
            // Where the user has been, so Back and Forward can return to it.
            .onChange(of: navigation.place) { old, new in navigation.record(from: old, to: new) }
            // Beside the screen, Back and Forward (also in the Go menu, with their shortcuts) move through what was open in the
            // world. They never leave the world: "All Worlds" at the top of the menu does that.
            .navigationBarBackButtonHidden(showsSideBySide(sizeClass))
            .toolbar {
                if showsSideBySide(sizeClass) {
                    ToolbarItemGroup(placement: .navigation) {
                        Button("Back", systemImage: "chevron.backward") { navigation.goBack() }
                            .disabled(!navigation.canGoBack)
                            .help("Go back to what was open before")
                        Button("Forward", systemImage: "chevron.forward") { navigation.goForward() }
                            .disabled(!navigation.canGoForward)
                            .help("Go forward again")
                    }
                }
            }
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

    /// With room (a Mac, or an iPad at regular width) the menu sits beside the screen it chose. On a phone, or a
    /// narrow iPad window, the menu is shown and the screen it chose is pushed on top of it, in the navigation
    /// stack the world list already provides. (A split view inside that stack would not navigate when collapsed.)
    @ViewBuilder
    private var layout: some View {
        if showsSideBySide(sizeClass) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .navigationTitle(world.name)
            } detail: {
                if isSearching {
                    SearchResultsView(world: world)
                } else {
                    screen
                }
            }
            #if os(iOS)
            // In a narrow iPad window the menu slides over the screen rather than squeezing it.
            .navigationSplitViewStyle(.prominentDetail)
            #endif
        } else {
            Group {
                if isSearching {
                    SearchResultsView(world: world)
                } else {
                    sidebar
                        .navigationTitle(world.name)
                }
            }
            // The screen is presented by the world list's stack, so it doesn't see what is set on this view. It
            // needs the navigation passed on to it.
            .navigationDestination(isPresented: $isShowingDetail) { screen.environment(navigation) }
        }
    }

    /// The screen the menu has chosen.
    @ViewBuilder
    private var screen: some View {
        switch navigation.selection {
        case .home:
            WorldHomeView(world: world, onDelete: onDelete)
        case .kind(let kind):
            PagesBrowser(world: world, kind: kind)
                .id(kind)
        case .worldMap:
            WorldMapView(world: world)
        case .timeline:
            WorldTimelineView(world: world)
        case .campaigns:
            CampaignsBrowser(world: world)
        case .library(let list):
            LibraryBrowser(world: world, list: list)
                .id(list)
        }
    }

    /// The menu. Beside the screen a row is selected, which highlights it. Otherwise the rows are buttons and the
    /// list has no selection, so a phone starts on the menu rather than on the screen the selection would open.
    @ViewBuilder
    private var sidebar: some View {
        if showsSideBySide(sizeClass) {
            List(selection: sidebarSelection) { sidebarRows }
                // Above the list, not in it, so it is never one of its rows: it is where the user leaves the world.
                .safeAreaInset(edge: .top, spacing: 0) {
                    Button { dismiss() } label: {
                        Label("All Worlds", systemImage: "chevron.backward")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Leaves this world and shows every world")
                }
        } else {
            List { sidebarRows }
        }
    }

    @ViewBuilder
    private var sidebarRows: some View {
        row(.home, "Home", systemImage: "house")
        row(.worldMap, "World Map", systemImage: "map")
        row(.timeline, "Timeline", systemImage: "clock")
        row(.campaigns, "Campaigns", systemImage: "flag", badge: (world.campaigns ?? []).count)

        Section("Pages") {
            ForEach(world.visibleKinds) { kind in
                row(.kind(kind), kind.title, systemImage: kind.systemImage, badge: count(of: kind))
            }
        }

        if hasLibrary {
            Section("Library") {
                ForEach(Library.shared.lists(in: world.edition), id: \.self) { list in
                    row(.library(list), Library.shared.title(of: list, in: world.edition), systemImage: Library.shared.systemImage(of: list, in: world.edition))
                }
            }
        }
    }

    /// One row of the menu. Beside the screen it is a selectable row. Otherwise it is a button that opens its
    /// screen, so choosing a row works even if it is already the current one, which a phone's list wouldn't report.
    @ViewBuilder
    private func row(_ item: WorldSidebarItem, _ title: LocalizedStringResource, systemImage: String, badge: Int = 0) -> some View {
        if showsSideBySide(sizeClass) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: systemImage)
            }
            .badge(badge)
            .tag(item)
        } else {
            Button {
                navigation.choose(item)
                isShowingDetail = true
            } label: {
                Label {
                    Text(title)
                } icon: {
                    Image(systemName: systemImage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .badge(badge)
            .listRowBackground(navigation.selection == item ? Color.accentColor.opacity(0.18) : nil)
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
    #if os(macOS)
    .frame(width: 1100, height: 800)
    #endif
    .modelContainer(container)
}
