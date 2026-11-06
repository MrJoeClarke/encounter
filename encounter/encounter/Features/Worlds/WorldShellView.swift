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
    /// Where a window made for a route starts. Nil in the main window, which starts at the world's home.
    var route: WindowRoute?
    /// Called when the user deletes the world from its home page. Nil in a window of its own, which has no list of worlds behind it.
    let onDelete: ((World) -> Void)?

    @State private var navigation = WorldNavigation()
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(LinkRouter.self) private var linkRouter
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.appTheme) private var theme

    private var isSearching: Bool {
        !navigation.searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var hasLibrary: Bool {
        world.rules.contains(.library)
    }

    /// On iOS, whether the screen chosen from the menu is open on top of it.
    @State private var isShowingDetail = false
    /// Where this window was, kept by the system for it so it comes back to the same screen after the app has been closed.
    @SceneStorage("windowRoute") private var savedRoute = ""
    @State private var hasRestored = false
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
            // A window made narrower (Split View, Slide Over, Stage Manager) changes from the menu beside the screen to the menu with
            // the screen pushed over it. What was open stays open, instead of the window going back to the menu.
            .onChange(of: sizeClass) { old, new in
                if showsSideBySide(old) && !showsSideBySide(new) { isShowingDetail = true }
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
            .onChange(of: navigation.place) { old, new in
                navigation.record(from: old, to: new)
                saveRoute()
            }
            .onChange(of: navigation.showsSheet) { saveRoute() }
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
            .onAppear {
                linkRouter.activate(world: world, navigation: navigation)
                restore()
            }
            .onDisappear { linkRouter.deactivate(navigation: navigation) }
            // If the rule system changes to one without a library while the library is showing, go home.
            .onChange(of: hasLibrary) {
                if !hasLibrary, case .library = navigation.selection {
                    navigation.choose(.home)
                }
            }
    }

    /// Notes where the window is, for its coming back to it.
    private func saveRoute() {
        guard hasRestored, let data = try? JSONEncoder().encode(navigation.route(in: world)), let text = String(data: data, encoding: .utf8) else { return }
        savedRoute = text
    }

    /// Takes the window back to where it was left, or where it was made to start, once.
    private func restore() {
        guard !hasRestored else { return }
        defer { hasRestored = true }
        let saved = savedRoute.data(using: .utf8).flatMap { try? JSONDecoder().decode(WindowRoute.self, from: $0) }
        if let saved, saved.worldID == world.id {
            navigation.apply(saved, in: world)
        } else if let route, route.worldID == world.id {
            navigation.apply(route, in: world)
        } else {
            return
        }
        // On a phone, or a narrow window, the screen is pushed over the menu.
        if !showsSideBySide(sizeClass) { isShowingDetail = navigation.selection != .home || navigation.selectedPage != nil }
    }

    /// With room (a Mac, or an iPad at regular width) the menu sits beside the screen it chose. On a phone, or a
    /// narrow iPad window, the menu is shown and the screen it chose is pushed on top of it, in the navigation
    /// stack the world list already provides. (A split view inside that stack would not navigate when collapsed.)
    @ViewBuilder
    private var layout: some View {
        if showsSideBySide(sizeClass) {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                sidebar
                    .themedNavigationTitle(world.name)
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
                        .themedNavigationTitle(world.name)
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
                // The sidebar keeps the system's own material beside the screen, which a fill of the theme's would fight; its icons
                // take the theme's accent.
                .listItemTint(theme.accent.map { .fixed($0.themeColor) })
                // Above the list, not in it, so it is never one of its rows: it is where the user leaves the world.
                .safeAreaInset(edge: .top, spacing: 0) {
                    VStack(spacing: 0) {
                    if route == nil {
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
                    // A flourished rule under it, where the theme has flourishes.
                    OrnamentalRule()
                        .padding(.horizontal, 16)
                        .padding(.bottom, 6)
                    }
                }
        } else {
            List { sidebarRows }
                .themedScreen()
        }
    }

    @ViewBuilder
    private var sidebarRows: some View {
        row(.home, "Home", systemImage: "house")
        row(.worldMap, "World Map", systemImage: "map")
        row(.timeline, "Timeline", systemImage: "clock")
        row(.campaigns, "Campaigns", systemImage: "flag", badge: (world.campaigns ?? []).count)

        Section {
            ForEach(world.visibleKinds) { kind in
                row(.kind(kind), kind.title, systemImage: kind.systemImage, badge: count(of: kind))
            }
        } header: {
            ThemedLabel("Pages")
        }

        if hasLibrary {
            Section {
                ForEach(Library.shared.lists(in: world.edition), id: \.self) { list in
                    row(.library(list), Library.shared.title(of: list, in: world.edition), systemImage: Library.shared.systemImage(of: list, in: world.edition))
                }
            } header: {
                ThemedLabel("Library")
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
                ThemedIcon(systemName: systemImage)
            }
            .badge(badge)
            .tag(item)
            // Choosing the item that is already showing returns to its list, which the list's own selection doesn't report.
            .simultaneousGesture(TapGesture().onEnded { navigation.chooseAgain(item) })
        } else {
            Button {
                navigation.choose(item)
                isShowingDetail = true
            } label: {
                Label {
                    Text(title)
                } icon: {
                    ThemedIcon(systemName: systemImage)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .badge(badge)
            .listRowBackground(navigation.selection == item ? (theme.selection?.themeColor ?? (theme.accent?.themeColor ?? Color.accentColor).opacity(0.18)) : theme.panel?.themeColor)
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

#if DEBUG
@MainActor
private func shellPreview(_ width: WindowWidth) -> some View {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world {
            WorldShellView(world: world) { _ in }
        }
    }
    .environment(LinkRouter())
    .modelContainer(container)
    .inWindow(width)
}

#Preview("Shell, Slide Over strip (320)") { shellPreview(.strip) }
#Preview("Shell, half screen (507)") { shellPreview(.half) }
#Preview("Shell, narrowest with the menu beside (678)") { shellPreview(.wide) }
#Preview("Shell menu, Parchment and Ink") { shellPreview(.strip).inTheme(.parchment()) }
#Preview("Shell menu, Parchment and Ink at night") { shellPreview(.strip).inTheme(.parchment(night: true)).preferredColorScheme(.dark) }
#Preview("Shell home, Parchment and Ink") { shellPreview(.full).inTheme(.parchment()) }
#Preview("Shell home, Parchment and Ink at night") { shellPreview(.full).inTheme(.parchment(night: true)).preferredColorScheme(.dark) }
#endif
