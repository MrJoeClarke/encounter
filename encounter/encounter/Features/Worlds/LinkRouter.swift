//
//  LinkRouter.swift
//  encounter
//

import Foundation
import Observation

/// Sends a mention link that the system hands back to the app (`encounter://page/<id>`) to the world that is
/// open, so clicking a mention in the notes opens the page it points at.
///
/// The notes editor passes link clicks to the system rather than to the app, so the app registers the
/// `encounter` URL scheme and receives them here.
@Observable
final class LinkRouter {
    private var world: World?
    private var navigation: WorldNavigation?

    /// Called when a world's screens appear. With several windows, the one shown last receives links.
    func activate(world: World, navigation: WorldNavigation) {
        self.world = world
        self.navigation = navigation
    }

    /// Called when a world's screens go away. Ignored if another world has become active since.
    func deactivate(navigation: WorldNavigation) {
        guard self.navigation === navigation else { return }
        world = nil
        self.navigation = nil
    }

    /// Opens the page the URL points at. Returns whether it did: false for a URL that isn't a mention, when no
    /// world is open, or when the page isn't in the open world.
    @discardableResult
    func open(_ url: URL) -> Bool {
        guard let id = Mention.pageID(from: url),
              let navigation,
              let page = world?.pages?.first(where: { $0.id == id })
        else { return false }
        navigation.open(page)
        return true
    }
}
