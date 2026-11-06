//
//  WindowRoute.swift
//  encounter
//

import Foundation
import SwiftUI
import SwiftData

/// Where a window of the app is: the world and the screen in it, in a form that can be saved (so a window comes back to it) and
/// handed to a new window (so a page, a map or a sheet can be opened in a window of its own).
struct WindowRoute: Codable, Hashable {
    enum Screen: Codable, Hashable {
        case home
        /// A kind of page, by its raw value.
        case kind(String)
        case worldMap
        case timeline
        case campaigns
        case library
    }

    var worldID: UUID
    var screen: Screen = .home
    var pageID: UUID?
    var mapID: UUID?
    var campaignID: UUID?
    /// The library entry open, by its key.
    var libraryKey: String?
    /// Whether a character is showing as its sheet and not its page.
    var showsSheet = false

    /// A page: its kind's list with the page open.
    static func page(_ page: Page, showsSheet: Bool = false) -> WindowRoute? {
        guard let worldID = page.world?.id else { return nil }
        return WindowRoute(worldID: worldID, screen: .kind(page.kind.rawValue), pageID: page.id, showsSheet: showsSheet)
    }

    /// A map, which is the world map's screen with that map open.
    static func map(_ map: WorldMap) -> WindowRoute? {
        guard let worldID = map.world?.id else { return nil }
        return WindowRoute(worldID: worldID, screen: .worldMap, mapID: map.isWorldMap ? nil : map.id)
    }
}

extension WorldNavigation {
    /// Where this world's window is now.
    func route(in world: World) -> WindowRoute {
        var route = WindowRoute(worldID: world.id)
        switch selection {
        case .home: route.screen = .home
        case .kind(let kind): route.screen = .kind(kind.rawValue)
        case .worldMap: route.screen = .worldMap
        case .timeline: route.screen = .timeline
        case .campaigns: route.screen = .campaigns
        case .library: route.screen = .library
        }
        route.pageID = selectedPage?.id
        route.mapID = selectedMap?.id
        route.campaignID = selectedCampaign?.id
        route.libraryKey = selectedLibraryKey
        route.showsSheet = showsSheet
        return route
    }

    /// Shows what a route names, as far as it can still be found in the world (a page may have been deleted since it was saved).
    func apply(_ route: WindowRoute, in world: World) {
        showsSheet = route.showsSheet
        switch route.screen {
        case .home:
            choose(.home)
        case .kind(let raw):
            if let kind = PageKind(rawValue: raw) {
                if let page = world.pages?.first(where: { $0.id == route.pageID && !$0.isDeleted }) { open(page) } else { choose(.kind(kind)) }
            }
        case .worldMap:
            choose(.worldMap)
            if let map = world.maps?.first(where: { $0.id == route.mapID && !$0.isDeleted }) { openMap(map) }
        case .timeline:
            choose(.timeline)
        case .campaigns:
            if let campaign = world.campaigns?.first(where: { $0.id == route.campaignID && !$0.isDeleted }) { openCampaign(campaign) } else { choose(.campaigns) }
        case .library:
            if let key = route.libraryKey, let entry = Library.shared.entry(forKey: key) { openLibraryEntry(entry) }
        }
    }
}

/// A window made for a route, shown by the app's second kind of window: a world's screens, with no list of worlds behind them.
struct WorldWindowView: View {
    let route: WindowRoute

    @Query private var worlds: [World]
    @Environment(LinkRouter.self) private var linkRouter

    init(route: WindowRoute) {
        self.route = route
        let id = route.worldID
        _worlds = Query(filter: #Predicate<World> { $0.id == id })
    }

    var body: some View {
        NavigationStack {
            if let world = worlds.first {
                WorldShellView(world: world, route: route, onDelete: nil)
            } else {
                ContentUnavailableView("This World Isn’t Here Any More", systemImage: "globe.europe.africa", description: Text("It was deleted, or has not arrived on this device."))
            }
        }
    }
}

/// The "Open in New Window" items for a menu, where the system allows more than one window: one for the route, and one more for the
/// character's sheet if it has one.
struct OpenInNewWindowButtons: View {
    let route: WindowRoute?
    var sheetRoute: WindowRoute?

    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if supportsMultipleWindows {
            if let route {
                Button("Open in New Window", systemImage: "macwindow.badge.plus") { openWindow(id: WindowRoute.windowID, value: route) }
            }
            if let sheetRoute {
                Button("Open Sheet in New Window", systemImage: "rectangle.portrait.on.rectangle.portrait") { openWindow(id: WindowRoute.windowID, value: sheetRoute) }
            }
        }
    }
}

extension WindowRoute {
    /// The identifier of the app's window made from a route.
    static let windowID = "world-window"
}
