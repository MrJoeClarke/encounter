//
//  WorldNavigation.swift
//  encounter
//

import Foundation
import Observation

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
}
