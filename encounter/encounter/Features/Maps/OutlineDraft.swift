//
//  OutlineDraft.swift
//  encounter
//

import Foundation

/// An outline for a place being drawn on a map, one corner at a time. Kept apart from the views so the rules
/// can be tested.
struct OutlineDraft {
    struct Corner: Equatable {
        var x: Double
        var y: Double
    }

    let page: Page
    private(set) var corners: [Corner] = []

    init(page: Page) {
        self.page = page
    }

    /// Adds a corner at an image position. A click on top of the last corner is ignored.
    mutating func add(x: Double, y: Double, closerThan tolerance: Double = 2) {
        if let last = corners.last, hypot(last.x - x, last.y - y) < tolerance { return }
        corners.append(Corner(x: x, y: y))
    }

    mutating func removeLast() {
        if !corners.isEmpty { corners.removeLast() }
    }

    /// The outline in the world, or nil until it has three corners that form a proper shape that lies on the plane.
    func geometry(on calibration: MapCalibration) -> PlaceGeometry? {
        let shape = PlaceGeometry.polygon(corners.map { calibration.gridPoint(atX: $0.x, y: $0.y) })
        return corners.count >= 3 && shape.isValid ? shape : nil
    }

    /// What is wrong with the outline so far, in words for the creator, or nil if it can be finished.
    func problem(on calibration: MapCalibration) -> String? {
        if corners.count < 3 { return String(localized: "Click the map to add corners. An outline needs at least three.") }
        if geometry(on: calibration) == nil {
            return String(localized: "The outline crosses itself, or reaches off the edge of the world. Undo a corner, or start again.")
        }
        return nil
    }
}
