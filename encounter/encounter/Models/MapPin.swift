//
//  MapPin.swift
//  encounter
//

import Foundation
import SwiftData

/// A pin on a map, positioned in normalised image coordinates (0...1) so image resolution doesn't matter.
@Model
final class MapPin {
    var id: UUID = UUID()
    var x: Double = 0.5
    var y: Double = 0.5
    var map: WorldMap?
    var target: Page?

    init(x: Double, y: Double, target: Page? = nil) {
        self.x = x
        self.y = y
        self.target = target
    }
}
