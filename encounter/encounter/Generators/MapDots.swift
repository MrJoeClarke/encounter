//
//  MapDots.swift
//  encounter
//

import Foundation

/// A dot on a picture of a map, which is a settlement.
nonisolated struct TracedDot: Identifiable, Equatable, Sendable {
    let id: Int
    /// Where it is, in the world's plane.
    var point: GridPoint
    /// How big the dot is, in the picture's pixels across.
    var size: Double
    /// Its name, from the lettering beside it, or one to start with.
    var name: String
    var isNamed: Bool
    /// "city", "town" or "village", by how big its dot is beside the others.
    var kind: String
    var isIncluded = true
    /// Whether it is thick enough to be a dot on its own. A thinner one (a bridge looks just like it) is kept only with a name beside it.
    var isFirm = true
}

/// Finds the dots of a picture: small, solid, round and dark, and not part of any lettering.
nonisolated enum MapDots {
    /// Where there are dots, in the plane, with the lettering that is beside each as its name.
    static func find(in trace: MapTrace, lettering: [MapLettering.Line], roads: [TracedLine] = [], calibration: MapCalibration) -> [TracedDot] {
        let w = trace.workingWidth, h = trace.workingHeight
        guard w > 0, h > 0, trace.classes.count == w * h, trace.width > 0, trace.height > 0 else { return [] }
        let sx = Double(w) / Double(trace.width), sy = Double(h) / Double(trace.height)
        // Dark and without colour: black ink.
        let dark = Set(trace.strokeColours.enumerated().filter { entry in
            let lab = entry.element
            return lab[0] < 40 && (lab[1] * lab[1] + lab[2] * lab[2]).squareRoot() < 18
        }.map { Int16($0.offset) })
        guard !dark.isEmpty else { return [] }
        // Letters are dark and solid too, so the places lettering was read are left out.
        var blank = [Bool](repeating: false, count: w * h)
        for line in lettering {
            let x0 = Int(((line.x - line.width / 2) * sx).rounded(.down)), x1 = Int(((line.x + line.width / 2) * sx).rounded(.up))
            let top = Int(((line.y - line.height / 2) * sy).rounded(.down)), bottom = Int(((line.y + line.height / 2) * sy).rounded(.up))
            guard x1 >= 0, bottom >= 0, x0 < w, top < h else { continue }
            for row in max(0, top)...min(h - 1, max(top, bottom)) {
                for x in max(0, x0)...min(w - 1, max(x0, x1)) { blank[(h - 1 - row) * w + x] = true }
            }
        }
        var mask = [Bool](repeating: false, count: w * h)
        for i in mask.indices where dark.contains(trace.classes[i]) && trace.labels[i] != trace.surround && !blank[i] { mask[i] = true }
        // How thick the dark is at each place: the pixels left after taking one, two, three... pixels off every edge. A dot is a thick place,
        // and a road's tail or a stroke of a letter is not.
        var levels: [[Bool]] = []
        for radius in 1...6 {
            let eroded = MapTracer.windowCounts(mask, width: w, height: h, radius: radius)
            let level = mask.indices.map { eroded.counts[$0] == eroded.sizes[$0] }
            if !level.contains(true) { break }
            levels.append(level)
        }

        // Strokes a pixel or two wide (a road's tail, a letter) are taken off first: the pixels left after a pixel is taken off every
        // edge and given back.
        var solid = [Bool](repeating: false, count: w * h)
        if let first = levels.first {
            let grown = MapTracer.windowCounts(first, width: w, height: h, radius: 1)
            for i in solid.indices where mask[i] && grown.counts[i] > 0 { solid[i] = true }
        }

        var found: [(x: Double, y: Double, size: Double, firm: Bool)] = []
        var seen = [Bool](repeating: false, count: w * h)
        for start in solid.indices where solid[start] && !seen[start] {
            var piece = [start]
            seen[start] = true
            var head = 0
            var minX = Int.max, maxX = Int.min, minY = Int.max, maxY = Int.min
            while head < piece.count {
                let i = piece[head]
                head += 1
                let x = i % w, y = i / w
                minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let n = ny * w + nx
                    if solid[n] && !seen[n] { seen[n] = true; piece.append(n) }
                }
            }
            let area = Double(piece.count)
            guard area >= 14, area <= 900 else { continue }
            // The thickest the piece gets, and where.
            var thickest = 0
            for (k, level) in levels.enumerated() where piece.contains(where: { level[$0] }) { thickest = k + 1 }
            guard thickest >= 1 else { continue }
            let core = piece.filter { levels[thickest - 1][$0] }
            let radius = Double(thickest) + 0.5
            // A disc, with at most a short tail: not much more than a disc's area and not much longer than it is wide.
            let longest = Double(max(maxX - minX, maxY - minY) + 1)
            guard area <= (thickest == 1 ? 7 : 3.5) * .pi * radius * radius, longest <= (thickest == 1 ? 10 : 7) * radius else { continue }
            // Not at the very edge of the picture, where what is left of a torn surround is.
            let middleX = Double(minX + maxX) / 2, middleY = Double(minY + maxY) / 2
            guard middleX > 0.05 * Double(w), middleX < 0.95 * Double(w), middleY > 0.05 * Double(h), middleY < 0.95 * Double(h) else { continue }
            let cx = core.reduce(0.0) { $0 + Double($1 % w) + 0.5 } / Double(core.count)
            let cy = core.reduce(0.0) { $0 + Double($1 / w) + 0.5 } / Double(core.count)
            // In the picture's pixels from the top left.
            found.append((cx / sx, (Double(h) - cy) / sy, 2 * radius / sx, thickest >= 2))
        }
        // A dark blob that a road runs through, well in from both its ends, is a bridge and not a settlement.
        let metres = calibration.metresPerPixel
        func isBridge(_ dot: (x: Double, y: Double, size: Double, firm: Bool)) -> Bool {
            let here = calibration.gridPoint(atX: dot.x, y: dot.y)
            // Where a road ends, or roads meet, there is a settlement; a road that just goes on through is crossing something.
            for road in roads where road.kind == .road && road.points.count >= 2 {
                for end in [road.points[0], road.points[road.points.count - 1]] where hypot(end.easting - here.easting, end.northing - here.northing) <= 3 * dot.size * metres { return false }
            }
            for road in roads where road.kind == .road && road.points.count >= 2 {
                var travelled = 0.0, total = 0.0
                for (a, b) in zip(road.points, road.points.dropFirst()) { total += hypot(b.easting - a.easting, b.northing - a.northing) }
                for (a, b) in zip(road.points, road.points.dropFirst()) {
                    let length = hypot(b.easting - a.easting, b.northing - a.northing)
                    guard length > 0 else { continue }
                    let t = min(max(((here.easting - a.easting) * (b.easting - a.easting) + (here.northing - a.northing) * (b.northing - a.northing)) / (length * length), 0), 1)
                    let nearest = GridPoint(easting: a.easting + (b.easting - a.easting) * t, northing: a.northing + (b.northing - a.northing) * t)
                    let along = travelled + t * length
                    if hypot(nearest.easting - here.easting, nearest.northing - here.northing) <= dot.size * 0.8 * metres,
                       along > 2.5 * dot.size * metres, total - along > 2.5 * dot.size * metres { return true }
                    travelled += length
                }
            }
            return false
        }
        found = found.filter { !isBridge($0) }
        // Two blobs almost together are one dot and a stroke of a letter by it: the thicker is the dot.
        found = found.enumerated().filter { entry in
            !found.enumerated().contains { other in
                (other.element.size > entry.element.size || (other.element.size == entry.element.size && other.offset < entry.offset))
                    && hypot(other.element.x - entry.element.x, other.element.y - entry.element.y) < 2.5 * (other.element.size + entry.element.size)
            }
        }.map(\.element)
        let sizes = found.map(\.size).sorted()
        let typical = sizes.isEmpty ? 0 : sizes[sizes.count / 2]
        return found.enumerated().map { index, dot in
            let kind = dot.size >= 1.3 * typical ? "city" : (dot.size <= 0.75 * typical ? "village" : "town")
            return TracedDot(
                id: index, point: calibration.gridPoint(atX: dot.x, y: dot.y), size: dot.size,
                name: "", isNamed: false, kind: kind, isFirm: dot.firm
            )
        }
    }

    /// Gives each dot the lettering nearest it, if that is close enough: within a line of lettering's height of its edge. Each name goes
    /// to one dot, the nearest. Dots with none are named from a number.
    static func name(_ dots: [TracedDot], from labels: [MapLabel], notNaming used: Set<String>, calibration: MapCalibration) -> (dots: [TracedDot], used: Set<String>) {
        var result = dots
        var taken = Set<String>()
        // Lettering turned to run along a river is read very tall; it is not beside a dot.
        let heights = labels.map(\.height).sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        // How far each label is from each dot, in the plane.
        var pairs: [(dot: Int, label: Int, distance: Double)] = []
        for (d, dot) in dots.enumerated() {
            for (l, label) in labels.enumerated() where label.type == nil && label.description.isEmpty && !used.contains(label.name) && label.height <= 2.5 * typical {
                let centre = calibration.gridPoint(atX: label.x, y: label.y)
                // To the lettering's box rather than its middle, as the dot is beside a name and not under it.
                let halfWidth = max(label.width, label.height) / 2 * calibration.metresPerPixel, halfHeight = label.height / 2 * calibration.metresPerPixel
                let dx = max(abs(dot.point.easting - centre.easting) - halfWidth, 0), dy = max(abs(dot.point.northing - centre.northing) - halfHeight, 0)
                let distance = hypot(dx, dy)
                if distance <= 1.2 * label.height * calibration.metresPerPixel { pairs.append((d, l, distance)) }
            }
        }
        var dotDone = Set<Int>(), labelDone = Set<Int>()
        for pair in pairs.sorted(by: { $0.distance < $1.distance }) where !dotDone.contains(pair.dot) && !labelDone.contains(pair.label) {
            dotDone.insert(pair.dot)
            labelDone.insert(pair.label)
            result[pair.dot].name = labels[pair.label].name
            result[pair.dot].isNamed = true
            taken.insert(labels[pair.label].name)
        }
        // A dot that is not thick and has no name beside it is as likely a bridge as a settlement.
        result = result.filter { $0.isNamed || $0.isFirm }
        var number = 0
        for i in result.indices where !result[i].isNamed {
            number += 1
            result[i].name = String(localized: "Settlement \(number)")
        }
        return (result, taken)
    }
}
