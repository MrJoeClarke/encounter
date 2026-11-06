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

/// Where a place is: a single point (a tavern, a landmark), the outline of an area (a settlement, a region), or a
/// line (a road, a river).
/// All the spatial questions live here as plain maths, so they can be tested without any storage.
nonisolated enum PlaceGeometry: Codable, Hashable, Sendable {
    case point(GridPoint)
    /// The corners in order, either way round. The last corner joins back to the first.
    case polygon([GridPoint])
    /// An area made of several pieces, such as a realm that has islands: the outlines of the pieces, the biggest first. Each is a simple
    /// polygon of its own, and they don't overlap.
    case multiPolygon([[GridPoint]])
    /// The points of a line in order, such as a road or a river. It can bend and cross itself, but it has a length.
    case line([GridPoint])

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
        case .multiPolygon(let pieces):
            !pieces.isEmpty && pieces.allSatisfy { PlaceGeometry.polygon($0).isValid }
        case .line(let points):
            points.count >= 2 && points.allSatisfy(\.isValid) && length > 0
        }
    }

    // MARK: Measures

    /// Square metres. A point has none.
    var area: Double {
        outlines.reduce(0) { $0 + abs(Self.signedArea($1)) }
    }

    /// The outlines of an area: one for a polygon, one for each piece of a multi-polygon, the biggest first, and none for a point or a line.
    var outlines: [[GridPoint]] {
        switch self {
        case .polygon(let corners): [corners]
        case .multiPolygon(let pieces): pieces
        case .point, .line: []
        }
    }

    /// The outline of an area's biggest piece, which is the whole of it unless it has several.
    var largestOutline: [GridPoint]? {
        outlines.max { abs(Self.signedArea($0)) < abs(Self.signedArea($1)) }
    }

    /// Metres along a line. A point or an area has none.
    var length: Double {
        guard case .line(let points) = self else { return 0 }
        return zip(points, points.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// The point itself, a polygon's centre of area (its corner average if it has no area), or the point half way
    /// along a line, which is on the line even when it bends.
    var centre: GridPoint {
        switch self {
        case .point(let point):
            return point
        case .line(let points):
            guard let first = points.first else { return GridPoint(easting: 0, northing: 0) }
            var remaining = length / 2
            for (a, b) in zip(points, points.dropFirst()) {
                let segment = a.distance(to: b)
                if remaining <= segment, segment > 0 {
                    let t = remaining / segment
                    return GridPoint(easting: a.easting + (b.easting - a.easting) * t, northing: a.northing + (b.northing - a.northing) * t)
                }
                remaining -= segment
            }
            return points.last ?? first
        case .multiPolygon:
            // The middle of the biggest piece, which is where the area is named and is at least in the area.
            return largestOutline.map { PlaceGeometry.polygon($0).centre } ?? GridPoint(easting: 0, northing: 0)
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
        if case .multiPolygon(let pieces) = self { return pieces.contains { PlaceGeometry.polygon($0).contains(point) } }
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
        if case .multiPolygon(let pieces) = self {
            // Held if it lies wholly in one piece, or, if it has pieces of its own, each of them does.
            if case .multiPolygon(let inner) = other {
                return inner.allSatisfy { piece in pieces.contains { PlaceGeometry.polygon($0).contains(PlaceGeometry.polygon(piece)) } }
            }
            return pieces.contains { PlaceGeometry.polygon($0).contains(other) }
        }
        guard case .polygon(let outer) = self else { return false }
        switch other {
        case .multiPolygon(let pieces):
            return pieces.allSatisfy { contains(.polygon($0)) }
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
        case .line(let points):
            // A line is held if every bend and every stretch between bends is inside, and it never leaves and comes back.
            guard points.count >= 2, points.allSatisfy({ contains($0) }) else { return false }
            for (a, b) in zip(points, points.dropFirst()) {
                let middle = GridPoint(easting: (a.easting + b.easting) / 2, northing: (a.northing + b.northing) / 2)
                if !contains(middle) { return false }
                for (c, d) in Self.edges(of: outer) where Self.properlyCross(a, b, c, d) { return false }
            }
            return true
        }
    }

    // MARK: Lines

    /// The shortest distance in metres from a position to a line, or to the point itself. Nil for an area.
    func distance(toPoint point: GridPoint) -> Double? {
        switch self {
        case .point(let own): return own.distance(to: point)
        case .polygon, .multiPolygon: return nil
        case .line(let points):
            return zip(points, points.dropFirst()).map { Self.distance(from: point, toSegment: $0.0, $0.1) }.min()
        }
    }

    private static func distance(from p: GridPoint, toSegment a: GridPoint, _ b: GridPoint) -> Double {
        let dx = b.easting - a.easting, dy = b.northing - a.northing
        let lengthSquared = dx * dx + dy * dy
        guard lengthSquared > 0 else { return p.distance(to: a) }
        let t = max(0, min(1, ((p.easting - a.easting) * dx + (p.northing - a.northing) * dy) / lengthSquared))
        return p.distance(to: GridPoint(easting: a.easting + t * dx, northing: a.northing + t * dy))
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
