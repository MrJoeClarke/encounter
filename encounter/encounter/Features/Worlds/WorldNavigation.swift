//
//  WorldNavigation.swift
//  encounter
//

import Foundation
import Observation
import SwiftData

/// What's showing in a world: the sidebar selection, the open page and the open library entry. Shared through
/// the environment so a mention or a "Referenced by" row anywhere can open a page, even one of another kind.
@Observable
final class WorldNavigation {
    var selection: WorldSidebarItem = .home
    var selectedPage: Page?
    /// The key of the library entry open in the Library, if any.
    var selectedLibraryKey: String?
    /// The campaign open in Campaigns, if any.
    var selectedCampaign: Campaign?
    /// The map open in the map view, if it isn't the world map.
    var selectedMap: WorldMap?
    /// What the user has typed in the search field. While it isn't empty, the results are showing.
    var searchText = ""
    var searchScope: SearchScope = .all

    /// Shows the page: switches the sidebar to its kind and selects it.
    func open(_ page: Page) {
        selection = .kind(page.kind)
        selectedPage = page
        selectedLibraryKey = nil
        searchText = ""
    }

    /// Shows the map: switches the sidebar to the world map, which holds whichever map is open.
    func openMap(_ map: WorldMap) {
        selection = .worldMap
        selectedMap = map
        selectedPage = nil
        selectedLibraryKey = nil
        searchText = ""
    }

    /// Shows the campaign: switches the sidebar to Campaigns and selects it.
    func openCampaign(_ campaign: Campaign) {
        selection = .campaigns
        selectedCampaign = campaign
        selectedPage = nil
        selectedLibraryKey = nil
        searchText = ""
    }

    /// Shows the library entry: switches the sidebar to its list and selects it.
    func openLibraryEntry(_ entry: LibraryEntry) {
        selection = .library(LibraryList(of: entry))
        selectedLibraryKey = entry.key
        selectedPage = nil
        searchText = ""
    }

    /// A sidebar choice made by the user. Clears what was open, since it belongs to the previous choice.
    func choose(_ item: WorldSidebarItem) {
        // Choosing anything in the sidebar leaves the search, even the item that was already showing.
        searchText = ""
        // Choosing the world map again comes back from a map further down to the world map itself.
        if item == .worldMap { selectedMap = nil }
        guard item != selection else { return }
        selection = item
        selectedPage = nil
        selectedLibraryKey = nil
        selectedMap = nil
        selectedCampaign = nil
    }

    // MARK: Back and forward

    /// Where the user is in the world: enough to come back to it.
    struct Place: Equatable {
        var selection: WorldSidebarItem
        var page: Page?
        var libraryKey: String?
        var campaign: Campaign?
        var map: WorldMap?
    }

    /// Where the user is now.
    var place: Place {
        Place(selection: selection, page: selectedPage, libraryKey: selectedLibraryKey, campaign: selectedCampaign, map: selectedMap)
    }

    /// The places the user came from, the latest last, and the ones they went back from.
    private(set) var backStack: [Place] = []
    private(set) var forwardStack: [Place] = []
    /// The place going back or forward is going to, so arriving there isn't recorded as a new journey.
    private var restoring: Place?
    private static let historyLimit = 100

    var canGoBack: Bool { backStack.contains(where: Self.isShowable) }
    var canGoForward: Bool { forwardStack.contains(where: Self.isShowable) }

    /// Notes a change of place. The world's screen calls it as the place changes. A place left for another is kept to go
    /// back to, and anything that was gone back from is forgotten.
    func record(from old: Place, to new: Place) {
        if let restoring, new == restoring {
            self.restoring = nil
            return
        }
        guard old != new, Self.isShowable(old) else { return }
        if backStack.last != old { backStack.append(old) }
        if backStack.count > Self.historyLimit { backStack.removeFirst(backStack.count - Self.historyLimit) }
        forwardStack.removeAll()
    }

    func goBack() {
        guard let target = Self.popShowable(&backStack) else { return }
        forwardStack.append(place)
        show(target)
    }

    func goForward() {
        guard let target = Self.popShowable(&forwardStack) else { return }
        backStack.append(place)
        show(target)
    }

    private func show(_ target: Place) {
        searchText = ""
        // Arriving at the place the user is already at changes nothing, and so wouldn't be seen to arrive.
        restoring = target == place ? nil : target
        selection = target.selection
        selectedPage = target.page
        selectedLibraryKey = target.libraryKey
        selectedCampaign = target.campaign
        selectedMap = target.map
    }

    /// Takes the latest place that can still be shown off a stack, leaving behind any whose page, map or campaign has since
    /// been deleted.
    private static func popShowable(_ stack: inout [Place]) -> Place? {
        while let last = stack.popLast() {
            if isShowable(last) { return last }
        }
        return nil
    }

    private static func isShowable(_ place: Place) -> Bool {
        (place.page == nil || place.page?.modelContext != nil)
            && (place.map == nil || place.map?.modelContext != nil)
            && (place.campaign == nil || place.campaign?.modelContext != nil)
    }
}
