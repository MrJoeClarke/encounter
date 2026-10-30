//
//  WorldNavigation.swift
//  encounter
//

import Foundation
import Observation

/// What's showing in a world: the sidebar selection and the open page. Shared through the environment so a
/// mention or a "Referenced by" row anywhere can open a page, even one of another kind.
@Observable
final class WorldNavigation {
    var selection: WorldSidebarItem = .home
    var selectedPage: Page?

    /// Shows the page: switches the sidebar to its kind and selects it.
    func open(_ page: Page) {
        selection = .kind(page.kind)
        selectedPage = page
    }

    /// A sidebar choice made by the user. Clears the open page, since it belongs to the previous choice.
    func choose(_ item: WorldSidebarItem) {
        guard item != selection else { return }
        selection = item
        selectedPage = nil
    }
}
