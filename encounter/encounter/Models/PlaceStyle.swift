//
//  PlaceStyle.swift
//  encounter
//

import Foundation

/// A colour, as the plain numbers the map views turn into the platform's own.
nonisolated struct StyleColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha = 1.0

    func with(alpha: Double) -> StyleColor { StyleColor(red: red, green: green, blue: blue, alpha: alpha) }
}

/// How a place is drawn on a map, from its type. A place with no type, or a type with no style of its own, is drawn
/// in the plain red outline an outlined place has always had.
nonisolated struct PlaceStyle: Equatable, Sendable {
    /// What an area is filled with, or nil for just an outline (and for lines, which have no inside).
    var fill: StyleColor?
    var stroke: StyleColor
    /// In points on screen.
    var lineWidth: Double
    var isDashed = false
    /// Which is drawn first: lower numbers sit underneath. Seas under settlements, buildings above, then roads and rivers.
    var drawOrder: Int

    static let plain = PlaceStyle(
        fill: StyleColor(red: 0.9, green: 0.2, blue: 0.2, alpha: 0.18),
        stroke: StyleColor(red: 0.9, green: 0.2, blue: 0.2), lineWidth: 2, drawOrder: 15
    )

    /// The place types the map knows how to draw, with the order they are listed in.
    static let types = ["Region", "Settlement", "District", "Building", "Wilderness", "Water", "Forest", "Mountains", "River", "Road", "Street", "Wall", "Square", "Garden", "Landmark", "Point of Interest"]

    static func style(forPlaceType type: String?) -> PlaceStyle {
        switch type {
        case "Water":
            PlaceStyle(fill: StyleColor(red: 0.25, green: 0.5, blue: 0.85, alpha: 0.55), stroke: StyleColor(red: 0.15, green: 0.35, blue: 0.7), lineWidth: 1.5, drawOrder: 5)
        case "Region":
            PlaceStyle(fill: StyleColor(red: 0.6, green: 0.45, blue: 0.8, alpha: 0.1), stroke: StyleColor(red: 0.55, green: 0.4, blue: 0.75), lineWidth: 1.5, isDashed: true, drawOrder: 6)
        case "Wilderness":
            PlaceStyle(fill: StyleColor(red: 0.7, green: 0.65, blue: 0.4, alpha: 0.3), stroke: StyleColor(red: 0.55, green: 0.5, blue: 0.3), lineWidth: 1, drawOrder: 8)
        case "Forest":
            PlaceStyle(fill: StyleColor(red: 0.2, green: 0.55, blue: 0.25, alpha: 0.5), stroke: StyleColor(red: 0.12, green: 0.4, blue: 0.18), lineWidth: 1, drawOrder: 9)
        case "Mountains":
            PlaceStyle(fill: StyleColor(red: 0.55, green: 0.5, blue: 0.45, alpha: 0.6), stroke: StyleColor(red: 0.4, green: 0.36, blue: 0.32), lineWidth: 1, drawOrder: 10)
        case "District":
            PlaceStyle(fill: StyleColor(red: 0.95, green: 0.8, blue: 0.3, alpha: 0.1), stroke: StyleColor(red: 0.8, green: 0.6, blue: 0.1), lineWidth: 1.5, isDashed: true, drawOrder: 18)
        case "Settlement":
            PlaceStyle(fill: StyleColor(red: 0.95, green: 0.6, blue: 0.2, alpha: 0.3), stroke: StyleColor(red: 0.85, green: 0.45, blue: 0.1), lineWidth: 2, drawOrder: 20)
        case "Building":
            PlaceStyle(fill: StyleColor(red: 0.45, green: 0.4, blue: 0.4, alpha: 0.8), stroke: StyleColor(red: 0.25, green: 0.22, blue: 0.22), lineWidth: 1, drawOrder: 30)
        case "River":
            PlaceStyle(fill: nil, stroke: StyleColor(red: 0.2, green: 0.45, blue: 0.85), lineWidth: 3.5, drawOrder: 40)
        case "Road":
            PlaceStyle(fill: nil, stroke: StyleColor(red: 0.65, green: 0.5, blue: 0.3), lineWidth: 2.5, drawOrder: 41)
        case "Street":
            PlaceStyle(fill: nil, stroke: StyleColor(red: 0.62, green: 0.52, blue: 0.38), lineWidth: 1.5, drawOrder: 40)
        case "Square":
            PlaceStyle(fill: StyleColor(red: 0.8, green: 0.75, blue: 0.62, alpha: 0.4), stroke: StyleColor(red: 0.65, green: 0.58, blue: 0.4), lineWidth: 1.5, drawOrder: 19)
        case "Garden":
            PlaceStyle(fill: StyleColor(red: 0.35, green: 0.65, blue: 0.3, alpha: 0.28), stroke: StyleColor(red: 0.25, green: 0.5, blue: 0.2), lineWidth: 1.5, isDashed: true, drawOrder: 18)
        case "Landmark":
            PlaceStyle(fill: StyleColor(red: 0.85, green: 0.65, blue: 0.2, alpha: 0.9), stroke: StyleColor(red: 0.5, green: 0.35, blue: 0.05), lineWidth: 1.5, drawOrder: 31)
        case "Wall":
            PlaceStyle(fill: nil, stroke: StyleColor(red: 0.4, green: 0.4, blue: 0.43), lineWidth: 4, drawOrder: 42)
        default:
            .plain
        }
    }

    /// Whether the type is drawn as a line by default, which is what a new place of the type is offered.
    static func isLineType(_ type: String?) -> Bool { type == "River" || type == "Road" || type == "Street" || type == "Wall" }
}
