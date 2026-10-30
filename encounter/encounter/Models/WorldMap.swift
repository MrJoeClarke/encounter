//
//  WorldMap.swift
//  encounter
//

import Foundation
import SwiftData

/// A map image with pins. Viewing and pinning arrive in the maps milestone.
@Model
final class WorldMap {
    var id: UUID = UUID()
    var name: String = ""
    @Attribute(.externalStorage)
    var imageData: Data?
    var world: World?
    /// The place this map depicts, which lets a pin drill down into a more detailed map.
    var place: Page?

    @Relationship(deleteRule: .cascade, inverse: \MapPin.map)
    var pins: [MapPin]?

    init(name: String, imageData: Data? = nil) {
        self.name = name
        self.imageData = imageData
    }
}
