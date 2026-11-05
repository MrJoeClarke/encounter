//
//  LabelSpot.swift
//  encounter
//

import Foundation

/// Where to put the name of an area so that it reads as belonging to it: well inside, away from the edge and from the pins, and for the
/// sea out on open water, not in the middle of the rectangle it is drawn as, which can be in the middle of the land.
nonisolated enum LabelSpot {
    private typealias V = SettlementGenerator.V

    /// Every so many points of a long outline are enough to measure how far a spot is from its edge.
    private static func sampled(_ outline: [GridPoint]) -> [V] {
        let step = max(1, outline.count / 240)
        var points = stride(from: 0, to: outline.count, by: step).map { V(x: outline[$0].easting, y: outline[$0].northing) }
        if let first = points.first { points.append(first) }
        return points
    }

    /// The spot inside an area that is furthest from its edge, less any that are near a pin. Falls back on the middle of the area's
    /// bounding box if no spot found is inside it, as for a very thin area.
    static func inside(_ outline: [GridPoint], avoiding pins: [GridPoint] = []) -> GridPoint {
        let fallback = GridPoint(
            easting: ((outline.map(\.easting).min() ?? 0) + (outline.map(\.easting).max() ?? 0)) / 2,
            northing: ((outline.map(\.northing).min() ?? 0) + (outline.map(\.northing).max() ?? 0)) / 2
        )
        guard outline.count >= 3 else { return fallback }
        let edge = sampled(outline)
        let polygon = outline.map { V(x: $0.easting, y: $0.northing) }
        let low = V(x: outline.map(\.easting).min() ?? 0, y: outline.map(\.northing).min() ?? 0)
        let high = V(x: outline.map(\.easting).max() ?? 0, y: outline.map(\.northing).max() ?? 0)
        let near = pins.map { V(x: $0.easting, y: $0.northing) }.filter { $0.x >= low.x && $0.x <= high.x && $0.y >= low.y && $0.y <= high.y }
        let steps = 24
        var best: (score: Double, point: V)?
        for i in 0..<steps {
            for j in 0..<steps {
                let point = V(x: low.x + (high.x - low.x) * (Double(i) + 0.5) / Double(steps), y: low.y + (high.y - low.y) * (Double(j) + 0.5) / Double(steps))
                guard SettlementGenerator.contains(polygon, point) else { continue }
                let clearance = SettlementGenerator.distance(from: point, toPolyline: edge)
                let away = near.map { $0.distance(to: point) }.min() ?? .infinity
                // The edge counts in full; a pin counts for less, so a name will sit a little off the middle before it sits on a pin.
                let score = min(clearance, away * 0.8)
                if best == nil || score > best!.score { best = (score, point) }
            }
        }
        guard let best else { return fallback }
        return GridPoint(easting: best.point.x, northing: best.point.y)
    }

    /// The spot in the sea, which is the rectangle `low` to `high` less the land, that is furthest from any land, and a little in from
    /// the edge of the map, so that the name is on the open water.
    static func openWater(from low: GridPoint, to high: GridPoint, land: [[GridPoint]]) -> GridPoint {
        let middle = GridPoint(easting: (low.easting + high.easting) / 2, northing: (low.northing + high.northing) / 2)
        let shores = land.map(sampled)
        let outlines = land.map { $0.map { V(x: $0.easting, y: $0.northing) } }
        let width = high.easting - low.easting, height = high.northing - low.northing
        let steps = 30
        var best: (score: Double, point: V)?
        for i in 0..<steps {
            for j in 0..<steps {
                let point = V(x: low.easting + width * (Double(i) + 0.5) / Double(steps), y: low.northing + height * (Double(j) + 0.5) / Double(steps))
                if outlines.contains(where: { SettlementGenerator.contains($0, point) }) { continue }
                var clearance = shores.map { SettlementGenerator.distance(from: point, toPolyline: $0) }.min() ?? .infinity
                // Not hard against the edge of the map either.
                clearance = min(clearance, (point.x - low.easting) * 1.5, (high.easting - point.x) * 1.5, (point.y - low.northing) * 1.5, (high.northing - point.y) * 1.5)
                if best == nil || clearance > best!.score { best = (clearance, point) }
            }
        }
        guard let best else { return middle }
        return GridPoint(easting: best.point.x, northing: best.point.y)
    }
}
