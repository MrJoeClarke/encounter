//
//  PlaceGeometry.swift
//  encounter
//

import Foundation

/// A position on a world's flat plane, in metres, like the UK National Grid: eastings run east and
/// northings run north from a south-west origin, so both are zero or more.
nonisolated struct GridPoint: Codable, Hashable, Sendable {
    var easting: Double
    var northing: Double

    var isValid: Bool {
        easting.isFinite && northing.isFinite && easting >= 0 && northing >= 0
    }

    func distance(to other: GridPoint) -> Double {
        hypot(easting - other.easting, northing - other.northing)
    }
}

/// Where a place is: a single point (a tavern, a landmark) or the outline of an area (a settlement, a region).
/// All the spatial questions live here as plain maths, so they can be tested without any storage.
nonisolated enum PlaceGeometry: Codable, Hashable, Sendable {
    case point(GridPoint)
    /// The corners in order, either way round. The last corner joins back to the first.
    case polygon([GridPoint])

    /// Points on an edge count as inside, within this many metres.
    private static let tolerance = 1e-9

    // MARK: Validity

    /// A usable shape: every coordinate on the plane, and a polygon with at least three corners that has an
    /// area and doesn't cross itself.
    var isValid: Bool {
        switch self {
        case .point(let point):
            point.isValid
        case .polygon(let corners):
            corners.count >= 3
                && corners.allSatisfy(\.isValid)
                && area > 0
                && Self.isSimple(corners)
        }
    }

    // MARK: Measures

    /// Square metres. A point has none.
    var area: Double {
        guard case .polygon(let corners) = self else { return 0 }
        return abs(Self.signedArea(corners))
    }

    /// The point itself, or a polygon's centre of area (its corner average if it has no area).
    var centre: GridPoint {
        switch self {
        case .point(let point):
            return point
        case .polygon(let corners):
            guard !corners.isEmpty else { return GridPoint(easting: 0, northing: 0) }
            let signed = Self.signedArea(corners)
            guard signed != 0 else {
                return GridPoint(
                    easting: corners.map(\.easting).reduce(0, +) / Double(corners.count),
                    northing: corners.map(\.northing).reduce(0, +) / Double(corners.count)
                )
            }
            var x = 0.0, y = 0.0
            for (a, b) in Self.edges(of: corners) {
                let cross = a.easting * b.northing - b.easting * a.northing
                x += (a.easting + b.easting) * cross
                y += (a.northing + b.northing) * cross
            }
            return GridPoint(easting: x / (6 * signed), northing: y / (6 * signed))
        }
    }

    /// Metres between the two shapes' centres.
    func distance(to other: PlaceGeometry) -> Double {
        centre.distance(to: other.centre)
    }

    // MARK: Containment

    /// Whether this is a polygon with `point` inside it or on its edge.
    func contains(_ point: GridPoint) -> Bool {
        guard case .polygon(let corners) = self, corners.count >= 3 else { return false }
        var inside = false
        for (a, b) in Self.edges(of: corners) {
            if Self.isOnSegment(point, a, b) { return true }
            // Count edges that cross a ray running east from the point.
            if (a.northing > point.northing) != (b.northing > point.northing) {
                let crossing = a.easting + (point.northing - a.northing) / (b.northing - a.northing) * (b.easting - a.easting)
                if point.easting < crossing { inside.toggle() }
            }
        }
        return inside
    }

    /// Whether this polygon holds the whole of `other`. A point is held if it is inside. A polygon is held if
    /// it is smaller than this one and none of it lies outside, which also catches a shape that leaves and
    /// re-enters a concave outline. The same shape doesn't hold itself.
    func contains(_ other: PlaceGeometry) -> Bool {
        guard case .polygon(let outer) = self else { return false }
        switch other {
        case .point(let point):
            return contains(point)
        case .polygon(let inner):
            guard other.area < area else { return false }
            guard inner.allSatisfy({ contains($0) }) else { return false }
            for (a, b) in Self.edges(of: inner) {
                let middle = GridPoint(easting: (a.easting + b.easting) / 2, northing: (a.northing + b.northing) / 2)
                if !contains(middle) { return false }
                for (c, d) in Self.edges(of: outer) where Self.properlyCross(a, b, c, d) { return false }
            }
            return true
        }
    }

    // MARK: Geometry helpers

    private static func edges(of corners: [GridPoint]) -> [(GridPoint, GridPoint)] {
        corners.indices.map { (corners[$0], corners[($0 + 1) % corners.count]) }
    }

    private static func signedArea(_ corners: [GridPoint]) -> Double {
        edges(of: corners).reduce(0) { $0 + ($1.0.easting * $1.1.northing - $1.1.easting * $1.0.northing) } / 2
    }

    /// Positive if c is left of the line a to b, negative if right, zero if on it.
    private static func side(_ a: GridPoint, _ b: GridPoint, _ c: GridPoint) -> Double {
        (b.easting - a.easting) * (c.northing - a.northing) - (b.northing - a.northing) * (c.easting - a.easting)
    }

    private static func isOnSegment(_ p: GridPoint, _ a: GridPoint, _ b: GridPoint) -> Bool {
        let length = a.distance(to: b)
        guard length > 0 else { return p.distance(to: a) <= tolerance }
        // Distance from the line, then check p lies between the ends.
        guard abs(side(a, b, p)) / length <= tolerance else { return false }
        return min(a.easting, b.easting) - tolerance <= p.easting && p.easting <= max(a.easting, b.easting) + tolerance
            && min(a.northing, b.northing) - tolerance <= p.northing && p.northing <= max(a.northing, b.northing) + tolerance
    }

    /// Segments that cross at a single point inside both, not just at an end or along each other.
    private static func properlyCross(_ a: GridPoint, _ b: GridPoint, _ c: GridPoint, _ d: GridPoint) -> Bool {
        let d1 = side(a, b, c), d2 = side(a, b, d), d3 = side(c, d, a), d4 = side(c, d, b)
        return ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0))
    }

    /// Segments that share any point, ends included.
    private static func touch(_ a: GridPoint, _ b: GridPoint, _ c: GridPoint, _ d: GridPoint) -> Bool {
        properlyCross(a, b, c, d)
            || isOnSegment(c, a, b) || isOnSegment(d, a, b) || isOnSegment(a, c, d) || isOnSegment(b, c, d)
    }

    /// A polygon whose edges meet only at neighbouring corners.
    private static func isSimple(_ corners: [GridPoint]) -> Bool {
        let all = edges(of: corners)
        for i in all.indices {
            for j in all.indices where j > i {
                let neighbours = j == i + 1 || (i == 0 && j == all.count - 1)
                if neighbours {
                    // Neighbouring edges share a corner, but must not fold back along each other.
                    let (a, b) = all[i], (c, d) = all[j]
                    let isNext = j == i + 1
                    let shared = isNext ? b : a
                    let farOfFirst = isNext ? a : b
                    let farOfSecond = isNext ? d : c
                    if isOnSegment(farOfSecond, shared, farOfFirst) || isOnSegment(farOfFirst, shared, farOfSecond) { return false }
                } else if touch(all[i].0, all[i].1, all[j].0, all[j].1) {
                    return false
                }
            }
        }
        return true
    }
}
