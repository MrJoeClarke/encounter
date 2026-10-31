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

    /// Shows the page: switches the sidebar to its kind and selects it.
    func open(_ page: Page) {
        selection = .kind(page.kind)
        selectedPage = page
        selectedLibraryKey = nil
    }

    /// Shows the library entry: switches the sidebar to its list and selects it.
    func openLibraryEntry(_ entry: LibraryEntry) {
        selection = .library(entry.kind.listKind)
        selectedLibraryKey = entry.key
        selectedPage = nil
    }

    /// A sidebar choice made by the user. Clears what was open, since it belongs to the previous choice.
    func choose(_ item: WorldSidebarItem) {
        guard item != selection else { return }
        selection = item
        selectedPage = nil
        selectedLibraryKey = nil
    }
}
