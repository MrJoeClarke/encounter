//
//  PlaneMaths.swift
//  encounter
//

import Foundation

typealias V = SettlementGenerator.V

/// Polygons on a flat plane, as the generators need them: area, centre, cutting and shrinking. Polygons are lists of
/// corners going round, and the functions that need a direction make them go anticlockwise first.
nonisolated enum Plane {
    /// Positive when the corners go anticlockwise.
    static func signedArea(_ p: [V]) -> Double {
        guard p.count >= 3 else { return 0 }
        var sum = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            sum += a.x * b.y - b.x * a.y
        }
        return sum / 2
    }

    static func area(_ p: [V]) -> Double { abs(signedArea(p)) }

    /// The polygon with its corners going anticlockwise.
    static func anticlockwise(_ p: [V]) -> [V] { signedArea(p) < 0 ? Array(p.reversed()) : p }

    /// The centre of area, or the average of the corners when the polygon has no area.
    static func centroid(_ p: [V]) -> V {
        let signed = signedArea(p)
        guard abs(signed) > 1e-9 else {
            guard !p.isEmpty else { return V(x: 0, y: 0) }
            return V(x: p.map(\.x).reduce(0, +) / Double(p.count), y: p.map(\.y).reduce(0, +) / Double(p.count))
        }
        var x = 0.0, y = 0.0
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            let cross = a.x * b.y - b.x * a.y
            x += (a.x + b.x) * cross
            y += (a.y + b.y) * cross
        }
        return V(x: x / (6 * signed), y: y / (6 * signed))
    }

    static func bounds(_ p: [V]) -> (min: V, max: V) {
        (V(x: p.map(\.x).min() ?? 0, y: p.map(\.y).min() ?? 0), V(x: p.map(\.x).max() ?? 0, y: p.map(\.y).max() ?? 0))
    }

    static func perimeter(_ p: [V]) -> Double {
        p.indices.reduce(0) { $0 + p[$1].distance(to: p[($1 + 1) % p.count]) }
    }

    /// The part of a polygon on the side of a line that `normal` points to (including the line itself).
    static func clip(_ polygon: [V], through point: V, normal: V) -> [V] {
        guard !polygon.isEmpty else { return [] }
        func side(_ v: V) -> Double { (v.x - point.x) * normal.x + (v.y - point.y) * normal.y }
        var result: [V] = []
        for i in polygon.indices {
            let current = polygon[i], next = polygon[(i + 1) % polygon.count]
            let a = side(current), b = side(next)
            if a >= 0 { result.append(current) }
            if (a > 0 && b < 0) || (a < 0 && b > 0) {
                let t = a / (a - b)
                result.append(V(x: current.x + (next.x - current.x) * t, y: current.y + (next.y - current.y) * t))
            }
        }
        return result
    }

    /// The part of a polygon nearer to `site` than to `other`.
    static func clipNearer(_ polygon: [V], site: V, than other: V) -> [V] {
        let middle = V(x: (site.x + other.x) / 2, y: (site.y + other.y) / 2)
        return clip(polygon, through: middle, normal: (site - other).unit)
    }

    /// The polygon with every edge moved inward by a distance. A convex polygon stays a polygon (and may vanish); a
    /// concave one is cut down by the same lines, which is close enough for plots.
    static func inset(_ polygon: [V], by distance: Double) -> [V] {
        let p = anticlockwise(polygon)
        var result = p
        for i in p.indices {
            let a = p[i], b = p[(i + 1) % p.count]
            let edge = (b - a).unit
            // For an anticlockwise polygon the inside is to the left of each edge.
            let normal = edge.perpendicular
            result = clip(result, through: a + normal * distance, normal: normal)
            if result.count < 3 { return [] }
        }
        return result
    }

    /// The polygon with each edge moved inward by its own distance, for a block whose sides face streets of different
    /// widths. The corners go anticlockwise, and `distances` has one for each edge, from a corner to the next.
    static func inset(_ polygon: [V], distances: [Double]) -> [V] {
        var result = polygon
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            guard a.distance(to: b) > 1e-6 else { continue }
            let normal = (b - a).unit.perpendicular
            result = clip(result, through: a + normal * distances[i], normal: normal)
            if result.count < 3 { return [] }
        }
        return result
    }

    /// Cuts a polygon in two along a line through `point` in `direction`. Either piece may be empty.
    static func split(_ polygon: [V], through point: V, direction: V) -> (left: [V], right: [V]) {
        let normal = direction.unit.perpendicular
        return (clip(polygon, through: point, normal: normal), clip(polygon, through: point, normal: V(x: -normal.x, y: -normal.y)))
    }

    /// Cuts a polygon in two along the longest stretch of a line through `point` in `direction` that lies inside it. Unlike
    /// `split`, it works for a polygon that is hollowed or bent, where the line may enter and leave several times.
    /// Returns nil if the line doesn't pass through the polygon.
    static func cut(_ polygon: [V], through point: V, direction: V) -> (first: [V], second: [V])? {
        let along = direction.unit, normal = along.perpendicular
        func side(_ v: V) -> Double { (v.x - point.x) * normal.x + (v.y - point.y) * normal.y }
        func position(_ v: V) -> Double { v.x * along.x + v.y * along.y }
        var ring: [V] = []
        var crossings: [Int] = []
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            ring.append(a)
            let sa = side(a), sb = side(b)
            if (sa > 1e-9 && sb < -1e-9) || (sa < -1e-9 && sb > 1e-9) {
                let t = sa / (sa - sb)
                ring.append(V(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t))
                crossings.append(ring.count - 1)
            }
        }
        guard crossings.count >= 2 else { return nil }
        let ordered = crossings.sorted { position(ring[$0]) < position(ring[$1]) }
        var best: (Int, Int)?
        var bestLength = 0.0
        for k in stride(from: 0, to: ordered.count - 1, by: 2) {
            let a = ring[ordered[k]], b = ring[ordered[k + 1]]
            let length = a.distance(to: b)
            if length > bestLength, contains(polygon, V(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)) { best = (ordered[k], ordered[k + 1]); bestLength = length }
        }
        guard let (i, j) = best else { return nil }
        let low = min(i, j), high = max(i, j)
        return (Array(ring[low...high]), Array(ring[high...]) + Array(ring[...low]))
    }

    /// The direction of the polygon's longest edge, which is the way a block runs.
    static func longestEdgeDirection(_ polygon: [V]) -> V {
        var best = V(x: 1, y: 0), bestLength = 0.0
        for i in polygon.indices {
            let a = polygon[i], b = polygon[(i + 1) % polygon.count]
            if a.distance(to: b) > bestLength { bestLength = a.distance(to: b); best = (b - a).unit }
        }
        return best
    }

    /// How far the polygon reaches along a direction: from its nearest corner to its farthest.
    static func extent(of polygon: [V], along direction: V) -> (low: Double, high: Double) {
        let projected = polygon.map { $0.x * direction.x + $0.y * direction.y }
        return (projected.min() ?? 0, projected.max() ?? 0)
    }

    /// Whether the point is inside (corners going either way).
    static func contains(_ polygon: [V], _ point: V) -> Bool { SettlementGenerator.contains(polygon, point) }

    /// The distance from a point to the nearest edge of a polygon.
    static func distanceToEdge(_ point: V, _ polygon: [V]) -> Double {
        polygon.indices.map { SettlementGenerator.distance(from: point, toSegment: polygon[$0], polygon[($0 + 1) % polygon.count]) }.min() ?? .infinity
    }
}

/// Cells of a Voronoi diagram: each site's part of an area, being all the points nearer to it than to any other site.
nonisolated enum Voronoi {
    /// Each site's cell cut out of `area`. A cell with no area left is empty. Cells are made by cutting the area with the
    /// line half way to each other site, nearest first, and stopping once no farther site could still cut.
    static func cells(sites: [V], in area: [V]) -> [[V]] {
        let area = Plane.anticlockwise(area)
        return sites.indices.map { index in
            let site = sites[index]
            var cell = area
            let others = sites.indices.filter { $0 != index }.sorted { sites[$0].distance(to: site) < sites[$1].distance(to: site) }
            for other in others {
                let distance = sites[other].distance(to: site)
                // Every corner of the cell is already nearer to the site than half way to this one, and so to all after it.
                if let farthest = cell.map({ $0.distance(to: site) }).max(), farthest < distance / 2 { break }
                cell = Plane.clipNearer(cell, site: site, than: sites[other])
                if cell.count < 3 { return [] }
            }
            return Plane.area(cell) > 1 ? cell : []
        }
    }

    /// Moves each site to the middle of its cell, which makes the cells rounder and more even.
    static func relax(_ sites: [V], in area: [V], times: Int) -> [V] {
        var current = sites
        for _ in 0..<times {
            let cells = Self.cells(sites: current, in: area)
            current = current.indices.map { cells[$0].isEmpty ? current[$0] : Plane.centroid(cells[$0]) }
        }
        return current
    }
}
