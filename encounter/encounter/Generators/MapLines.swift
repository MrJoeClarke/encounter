//
//  MapLines.swift
//  encounter
//

import Foundation

/// What a line traced from a picture is.
nonisolated enum TracedLineKind: String, Sendable {
    case river, road

    var placeType: String { self == .river ? "River" : "Road" }
    var title: String { self == .river ? String(localized: "River") : String(localized: "Road") }
}

/// A river or road followed along its stroke in the picture.
nonisolated struct TracedLine: Identifiable, Equatable, Sendable {
    let id: Int
    var kind: TracedLineKind
    /// From end to end, in the world's plane.
    var points: [GridPoint]
    /// Its name, from the lettering beside it, or one to start with.
    var name: String
    var isNamed: Bool
    var isIncluded = true
}

/// Follows the thin lines of a picture of a map: the strokes taken off its colours are thinned to their centres, followed from end to
/// end, and joined where one carries on through a crossing.
nonisolated enum MapLines {
    /// How the lines are looked for, in pixels of the working picture.
    struct Settings: Sendable {
        /// Pieces of stroke with fewer pixels than this are specks.
        var smallestStroke = 30
        /// A branch shorter than this, at a junction, is a rough edge of the stroke and not a line.
        var spur = 10.0
        /// A line shorter than this is not kept.
        var shortest = 40.0
        /// How near two ends must be to be taken as one place.
        var meet = 4.0
    }

    /// What sort of line a stroke of this colour (Lab) is: blue ones are rivers, brown ones are roads. Black and grey are lettering and
    /// outlines, and other colours are not lines.
    static func kind(l: Float, a: Float, b: Float) -> TracedLineKind? {
        let chroma = (a * a + b * b).squareRoot()
        var hue = Double(atan2(b, a)) * 180 / .pi
        if hue < 0 { hue += 360 }
        if chroma >= 12, hue >= 190, hue <= 290 { return .river }
        if chroma >= 8, hue >= 25, hue <= 100, l < 55 { return .road }
        return nil
    }

    /// The rivers and roads of a trace, in the plane. `lettering` is where text recognition found names, which are left out so that
    /// letters are not followed as lines.
    static func find(in trace: MapTrace, lettering: [MapLettering.Line], calibration: MapCalibration, settings: Settings = Settings()) -> [TracedLine] {
        let w = trace.workingWidth, h = trace.workingHeight
        guard w > 0, h > 0, trace.strokes.count == w * h, trace.width > 0, trace.height > 0 else { return [] }
        let sx = Double(w) / Double(trace.width), sy = Double(h) / Double(trace.height)
        // The lettering that is straight (not turned to run along a river, whose box would take in the river too) is blanked.
        let heights = lettering.map(\.height).sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        var blank = [Bool](repeating: false, count: w * h)
        for line in lettering where line.height <= 2.5 * typical {
            let x0 = Int(((line.x - line.width * 0.55) * sx).rounded(.down)), x1 = Int(((line.x + line.width * 0.55) * sx).rounded(.up))
            let top = Int(((line.y - line.height * 0.55) * sy).rounded(.down)), bottom = Int(((line.y + line.height * 0.55) * sy).rounded(.up))
            for row in max(0, top)...min(h - 1, max(top, bottom)) {
                for x in max(0, x0)...min(w - 1, max(x0, x1)) { blank[(h - 1 - row) * w + x] = true }
            }
        }
        var found: [(kind: TracedLineKind, points: [V])] = []
        for kind in [TracedLineKind.river, .road] {
            // The colours of one sort of line are taken together: a stroke has an edge of mixed colour that is a colour of its own.
            let colours = Set(trace.strokeColours.enumerated().filter { Self.kind(l: $0.element[0], a: $0.element[1], b: $0.element[2]) == kind }.map { Int16($0.offset) })
            guard !colours.isEmpty else { continue }
            var mask = [Bool](repeating: false, count: w * h)
            var any = false
            for i in mask.indices where colours.contains(trace.strokes[i]) && !blank[i] { mask[i] = true; any = true }
            guard any else { continue }
            removeSpecks(&mask, width: w, height: h, smallest: settings.smallestStroke)
            thin(&mask, width: w, height: h)
            for line in follow(mask, width: w, height: h, settings: settings) where !isBorder(line, in: trace) { found.append((kind, line)) }
        }
        return found.enumerated().map { index, line in
            let smooth = smoothed(line.points)
            let points = smooth.map { calibration.gridPoint(atX: $0.x / sx, y: (Double(h) - $0.y) / sy) }
            return TracedLine(id: index, kind: line.kind, points: points, name: "", isNamed: false)
        }
    }

    /// Whether a line runs along the border between two different areas, as the mixed colour at the edge of an area does, and not along
    /// inside one, as a river does: most places along it have a different colour on one side from the other.
    private static func isBorder(_ line: [V], in trace: MapTrace) -> Bool {
        let w = trace.workingWidth, h = trace.workingHeight
        guard line.count >= 2, trace.labels.count == w * h else { return false }
        func label(_ p: V) -> Int16? {
            let x = Int(p.x), y = Int(p.y)
            return x >= 0 && y >= 0 && x < w && y < h ? trace.labels[y * w + x] : nil
        }
        var different = 0, total = 0
        var travelled = 0.0
        for (a, b) in zip(line, line.dropFirst()) {
            let length = a.distance(to: b)
            guard length > 0 else { continue }
            travelled += length
            guard travelled >= 4 else { continue }
            travelled = 0
            // Across the line, a few pixels either side of it.
            let across = V(x: -(b.y - a.y) / length * 6, y: (b.x - a.x) / length * 6)
            let middle = V(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            guard let one = label(middle + across), let other = label(middle - across) else { continue }
            total += 1
            if one != other { different += 1 }
        }
        return total > 0 && Double(different) >= 0.5 * Double(total)
    }

    // MARK: Thinning

    /// Clears pieces of the mask (joined by their sides or corners) of fewer than `smallest` pixels.
    private static func removeSpecks(_ mask: inout [Bool], width: Int, height: Int, smallest: Int) {
        var seen = [Bool](repeating: false, count: mask.count)
        for start in mask.indices where mask[start] && !seen[start] {
            var piece = [start]
            seen[start] = true
            var head = 0
            while head < piece.count {
                let i = piece[head]
                head += 1
                let x = i % width, y = i / width
                for dy in -1...1 { for dx in -1...1 where dx != 0 || dy != 0 {
                    let nx = x + dx, ny = y + dy
                    guard nx >= 0, ny >= 0, nx < width, ny < height else { continue }
                    let n = ny * width + nx
                    if mask[n] && !seen[n] { seen[n] = true; piece.append(n) }
                } }
            }
            if piece.count < smallest { for i in piece { mask[i] = false } }
        }
    }

    /// Takes the pixels off the edges of every stroke, until only a line one pixel wide down its middle is left (Zhang and Suen).
    private static func thin(_ mask: inout [Bool], width: Int, height: Int) {
        var on = mask.indices.filter { mask[$0] }
        func value(_ x: Int, _ y: Int) -> Int { x >= 0 && y >= 0 && x < width && y < height && mask[y * width + x] ? 1 : 0 }
        var changed = true
        var rounds = 0
        while changed && rounds < 60 {
            changed = false
            rounds += 1
            for step in 0..<2 {
                var removed: [Int] = []
                for i in on where mask[i] {
                    let x = i % width, y = i / width
                    let p2 = value(x, y - 1), p3 = value(x + 1, y - 1), p4 = value(x + 1, y), p5 = value(x + 1, y + 1)
                    let p6 = value(x, y + 1), p7 = value(x - 1, y + 1), p8 = value(x - 1, y), p9 = value(x - 1, y - 1)
                    let neighbours = p2 + p3 + p4 + p5 + p6 + p7 + p8 + p9
                    guard neighbours >= 2, neighbours <= 6 else { continue }
                    let ring = [p2, p3, p4, p5, p6, p7, p8, p9, p2]
                    var transitions = 0
                    for k in 0..<8 where ring[k] == 0 && ring[k + 1] == 1 { transitions += 1 }
                    guard transitions == 1 else { continue }
                    if step == 0 {
                        guard p2 * p4 * p6 == 0, p4 * p6 * p8 == 0 else { continue }
                    } else {
                        guard p2 * p4 * p8 == 0, p2 * p6 * p8 == 0 else { continue }
                    }
                    removed.append(i)
                }
                if !removed.isEmpty {
                    for i in removed { mask[i] = false }
                    changed = true
                }
            }
            on = on.filter { mask[$0] }
        }
    }

    // MARK: Following

    /// The lines along a thinned mask, from end to end of each, in working pixels.
    private static func follow(_ mask: [Bool], width: Int, height: Int, settings: Settings) -> [[V]] {
        let around = [(0, -1), (1, -1), (1, 0), (1, 1), (0, 1), (-1, 1), (-1, 0), (-1, -1)]
        func ring(_ i: Int) -> [Bool] {
            let x = i % width, y = i / width
            return around.map { dx, dy in
                let nx = x + dx, ny = y + dy
                return nx >= 0 && ny >= 0 && nx < width && ny < height && mask[ny * width + nx]
            }
        }
        /// An end or a junction, as opposed to a place along a line.
        func isNode(_ i: Int) -> Bool {
            let r = ring(i)
            let count = r.filter { $0 }.count
            var transitions = 0
            for k in 0..<8 where !r[k] && r[(k + 1) % 8] { transitions += 1 }
            return count == 1 || transitions >= 3
        }
        func neighbours(_ i: Int) -> [Int] {
            let x = i % width, y = i / width
            // Sides before corners, so a line doesn't cut a corner it need not.
            return [2, 4, 6, 0, 1, 3, 5, 7].compactMap { k in
                let nx = x + around[k].0, ny = y + around[k].1
                guard nx >= 0, ny >= 0, nx < width, ny < height, mask[ny * width + nx] else { return nil }
                return ny * width + nx
            }
        }
        let skeleton = mask.indices.filter { mask[$0] }
        var node = [Bool](repeating: false, count: mask.count)
        for i in skeleton where isNode(i) { node[i] = true }
        var visited = [Bool](repeating: false, count: mask.count)
        var chains: [[Int]] = []
        func walk(_ start: Int, _ first: Int) {
            var path = [start, first]
            var previous = start, current = first
            if !node[first] { visited[first] = true }
            while !node[current] {
                guard let next = neighbours(current).first(where: { $0 != previous && !visited[$0] && !path.suffix(4).contains($0) }) else { break }
                previous = current
                current = next
                path.append(current)
                if !node[current] { visited[current] = true }
            }
            chains.append(path)
        }
        for start in skeleton where node[start] {
            for first in neighbours(start) where !visited[first] && !node[first] { walk(start, first) }
        }
        // Lines that close on themselves have no end or junction to start from.
        for start in skeleton where !visited[start] && !node[start] {
            visited[start] = true
            if let first = neighbours(start).first(where: { !visited[$0] }) { walk(start, first) }
        }
        // A short branch with a loose end, from a junction, is a rough edge of the stroke and not a line.
        func isLooseEnd(_ i: Int) -> Bool { ring(i).filter { $0 }.count == 1 }
        chains = chains.filter { chain in
            guard chain.count >= 2 else { return false }
            let points = chain.map { V(x: Double($0 % width) + 0.5, y: Double($0 / width) + 0.5) }
            return length(points) >= settings.spur || isLooseEnd(chain[0]) == isLooseEnd(chain[chain.count - 1])
        }
        var lines: [[V]] = chains.map { $0.map { V(x: Double($0 % width) + 0.5, y: Double($0 / width) + 0.5) } }
        lines = join(lines, meet: settings.meet)
        return lines.filter { length($0) >= settings.shortest }
    }

    private static func length(_ line: [V]) -> Double {
        zip(line, line.dropFirst()).reduce(0) { $0 + $1.0.distance(to: $1.1) }
    }

    /// Joins lines that meet end to end where one carries on in the same direction as the other, as a road through a crossing or a river
    /// through a junction does, most nearly straight first.
    private static func join(_ input: [[V]], meet: Double) -> [[V]] {
        var lines = input
        /// The way a line leaves from one of its ends, from a few pixels in.
        func direction(_ line: [V], atStart: Bool) -> V {
            let near = atStart ? line[0] : line[line.count - 1]
            let far = atStart ? line[min(8, line.count - 1)] : line[max(0, line.count - 1 - 8)]
            let d = far - near
            let n = max(d.distance(to: V(x: 0, y: 0)), 1e-9)
            return V(x: d.x / n, y: d.y / n)
        }
        while true {
            var best: (a: Int, aStart: Bool, b: Int, bStart: Bool, cosine: Double)?
            for a in lines.indices {
                for aStart in [true, false] {
                    let pa = aStart ? lines[a][0] : lines[a][lines[a].count - 1]
                    let da = direction(lines[a], atStart: aStart)
                    for b in lines.indices where b > a {
                        for bStart in [true, false] {
                            let pb = bStart ? lines[b][0] : lines[b][lines[b].count - 1]
                            guard pa.distance(to: pb) <= meet else { continue }
                            let db = direction(lines[b], atStart: bStart)
                            let cosine = da.x * db.x + da.y * db.y
                            if cosine < -0.7, cosine < (best?.cosine ?? 0) { best = (a, aStart, b, bStart, cosine) }
                        }
                    }
                }
            }
            guard let pair = best else { break }
            // Put the first line so it ends where the second begins, then join.
            let first = pair.aStart ? Array(lines[pair.a].reversed()) : lines[pair.a]
            let second = pair.bStart ? lines[pair.b] : Array(lines[pair.b].reversed())
            lines[pair.a] = first + second
            lines.remove(at: pair.b)
        }
        return lines
    }

    /// A line made smooth: fewer points, with its corners rounded a little.
    private static func smoothed(_ line: [V]) -> [V] {
        let simple = Contours.simplify(open: line, tolerance: 1.5)
        return Contours.simplify(open: RasterPartition.roundedOpen(RasterPartition.subdivided(simple, closed: false, longest: 6), times: 2), tolerance: 0.5)
    }

    // MARK: Names

    private static func distance(from point: V, toLine line: [V]) -> Double {
        zip(line, line.dropFirst()).map { SettlementGenerator.distance(from: point, toSegment: $0.0, $0.1) }.min() ?? .infinity
    }

    /// Gives lines the names written beside them: lettering that does not name an area, nearest to a line and no further from it than a
    /// few lines of its own height. Lines without a name get one to start with, from their type and a number.
    static func name(_ lines: [TracedLine], from labels: [MapLabel], notNaming used: Set<String>, calibration: MapCalibration, imageWidth: Int) -> [TracedLine] {
        var result = lines
        let reach = 0.03 * Double(imageWidth) * calibration.metresPerPixel
        var claimed: [Int: (distance: Double, label: MapLabel)] = [:]
        let heights = labels.map(\.height).sorted()
        let typical = heights.isEmpty ? 0 : heights[heights.count / 2]
        // Only lettering that says it is a river or road, or that is turned to run along something (so is read as very tall): other
        // lettering beside a line is as likely to be a town's name.
        let lineWords: Set<String> = ["river", "brook", "stream", "creek", "road", "way", "highway", "path", "track", "pass", "trail", "causeway"]
        for label in labels where label.type == nil && label.description.isEmpty && !label.isCapitals && !used.contains(label.name)
            && (label.name.lowercased().split(separator: " ").contains { lineWords.contains(String($0)) } || label.height > 2.5 * typical) {
            let here = calibration.gridPoint(atX: label.x, y: label.y)
            var nearest: (index: Int, distance: Double)?
            for (i, line) in lines.enumerated() {
                let d = distance(from: V(x: here.easting, y: here.northing), toLine: line.points.map { V(x: $0.easting, y: $0.northing) })
                if d < reach, d < (nearest?.distance ?? .infinity) { nearest = (i, d) }
            }
            guard let near = nearest else { continue }
            if let existing = claimed[near.index], existing.distance <= near.distance { continue }
            claimed[near.index] = (near.distance, label)
        }
        var counts: [TracedLineKind: Int] = [:]
        for i in result.indices {
            if let pick = claimed[i] {
                result[i].name = pick.label.name
                result[i].isNamed = true
            } else {
                counts[result[i].kind, default: 0] += 1
                result[i].name = "\(result[i].kind.title) \(counts[result[i].kind] ?? 1)"
            }
        }
        return result
    }
}

extension MapLines {
    /// A trace with its rivers and roads found and named. `labels` is the lettering already read as names, whose names are kept for areas
    /// where an area took them.
    static func add(to trace: MapTrace, lettering: [MapLettering.Line], labels: [MapLabel], calibration: MapCalibration) -> MapTrace {
        var result = trace
        let used = Set(trace.colours.flatMap { $0.named.values.map(\.name) })
        let lines = find(in: trace, lettering: lettering, calibration: calibration)
        result.lines = name(lines, from: labels, notNaming: used, calibration: calibration, imageWidth: trace.width)
        return result
    }
}
