//
//  WorldMapView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The World Map screen: the world's main map, or the map further down that was opened from it. Other maps are
/// reached from pins on the maps, or from their place's page.
struct WorldMapView: View {
    let world: World

    @Environment(WorldNavigation.self) private var navigation

    var body: some View {
        if let map = navigation.selectedMap ?? world.worldMap {
            MapDetailView(map: map)
                .id(map.id)
        } else if let root = world.rootPlace {
            ContentUnavailableView {
                ThemedEmptyLabel("No World Map Yet", systemImage: "map")
            } description: {
                Text("Add an image of your world to see it here. You can then put places on it, and open their own maps from it.")
            } actions: {
                AddMapControls(place: root)
            }
        } else {
            ContentUnavailableView { ThemedEmptyLabel("No World Map", systemImage: "map") }
        }
    }
}
