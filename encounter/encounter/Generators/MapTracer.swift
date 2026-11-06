//
//  MapTracer.swift
//  encounter
//

import Foundation
import CoreGraphics

/// What a coloured area of a picture of a map is, as far as the world is concerned.
nonisolated enum TracedType: String, CaseIterable, Identifiable, Sendable {
    case region, water, forest, mountains, wilderness
    /// Left out: not made into a place.
    case ignore

    var id: String { rawValue }

    /// The type of place it becomes, or nil if it is left out.
    var placeType: String? {
        switch self {
        case .region: "Region"
        case .water: "Water"
        case .forest: "Forest"
        case .mountains: "Mountains"
        case .wilderness: "Wilderness"
        case .ignore: nil
        }
    }

    var title: String {
        switch self {
        case .region: String(localized: "Realm")
        case .water: String(localized: "Sea or Water")
        case .forest: String(localized: "Forest")
        case .mountains: String(localized: "Mountains")
        case .wilderness: String(localized: "Wilderness")
        case .ignore: String(localized: "Leave Out")
        }
    }
}

/// One of the main colours of a picture, and the areas of it.
nonisolated struct TracedColour: Identifiable, Equatable, Sendable {
    let id: Int
    /// The colour, from 0 to 1.
    var red: Double
    var green: Double
    var blue: Double
    /// The share of the picture it covers, from 0 to 1.
    var share: Double
    /// Whether it is only ever in thin strokes (rivers, roads, lettering, outlines), not in areas.
    var isThin: Bool
    /// What its areas are: guessed from the colour, and changed by the user.
    var type: TracedType
    /// The name its place is to have.
    var name: String
    /// Its areas in the world's plane, biggest first. Empty for a thin colour, and for the surround of the picture.
    var outlines: [[GridPoint]]
}

nonisolated struct MapTrace: Equatable, Sendable {
    var colours: [TracedColour]
    /// The size of the picture, in pixels.
    var width: Int
    var height: Int

    /// The colours that have areas, which are the ones to choose a type for.
    var areaColours: [TracedColour] { colours.filter { !$0.outlines.isEmpty } }
}

/// Finds the coloured areas of a picture of a map: the colours it is made of, and the outlines of each colour's areas. All of it
/// is done on the device.
nonisolated enum MapTracer {
    /// How the picture is worked on.
    struct Settings: Sendable {
        /// How many pixels long the picture's longer side is made, for working.
        var workingSize = 1600
        /// How many colours are looked for, before near ones are joined.
        var colours = 12
        /// How far apart two colours must be (in Lab) to be different ones.
        var separation = 12.0
        /// A colour is thin if less than this share of its pixels are left after taking a few pixels off every edge.
        var thinShare = 0.15
        /// How many pixels are taken off every edge to find out.
        var thinRadius = 3
        /// The smallest patch kept, as a share of the picture.
        var smallestPatch = 0.00003
    }

    /// The colours of `image` and the outlines of their areas in the plane, by `calibration`, or nil if it is too plain to have any.
    static func trace(image: CGImage, calibration: MapCalibration, settings: Settings = Settings()) -> MapTrace? {
        guard let raster = Raster(image: image, size: settings.workingSize) else { return nil }
        let w = raster.width, h = raster.height
        let count = w * h

        // The colours: found among a sample of the pixels, then joined where near, then every pixel takes the nearest.
        let centres = findColours(raster, settings: settings)
        guard centres.count > 0 else { return nil }
        var labels = [Int16](repeating: 0, count: count)
        assign(raster, to: centres, labels: &labels)

        // Strokes are not areas: a colour that is only strokes, and the strokes of one that is also areas (a river in the sea's blue, an
        // outline in the surround's black), give their pixels to what they lie between.
        let thin = removeStrokes(&labels, count: centres.count, width: w, height: h, settings: settings)
        guard fill(&labels, width: w, height: h) else { return nil }
        // So are specks, and anything too small to be an area.
        let smallest = max(8, Int(settings.smallestPatch * Double(count)))
        removeSmallPatches(&labels, width: w, height: h, smallest: smallest)
        guard fill(&labels, width: w, height: h) else { return nil }

        // The dark surround of a picture, joined to its edge, is outside the map.
        let outside = markOutside(&labels, centres: centres, width: w, height: h)

        // The colours that are left, numbered from 0, with the surround last.
        var used = Set<Int16>()
        for label in labels { used.insert(label) }
        let order = used.sorted()
        var number: [Int16: Int16] = [:]
        for (i, label) in order.enumerated() { number[label] = Int16(i) }
        // Traced from the bottom up, as the outlines' points are, so they come out the right way round.
        var compact = [Int16](repeating: 0, count: count)
        for y in 0..<h { for x in 0..<w { compact[(h - 1 - y) * w + x] = number[labels[y * w + x]] ?? 0 } }

        let sx = Double(w) / Double(image.width), sy = Double(h) / Double(image.height)
        let minimumArea = Double(smallest)
        let traced = RasterPartition.trace(
            labels: compact, width: w, height: h, smoothing: RasterPartition.Smoothing(simplify: 1.0, finalSimplify: 0.3, rounding: 2, longestRun: 6),
            skipping: outside.flatMap { number[$0] }.map { [Int($0)] } ?? []
        ) { loop in
            let area = Plane.signedArea(loop)
            // A hole in an area goes the other way round; it is a different colour's area, so it is not this one's.
            guard area >= minimumArea else { return .tooSmall }
            var points: [GridPoint] = []
            for p in loop {
                // The picture is traced upside down (row 0 is its bottom), so it is turned back for its pixels.
                let plane = calibration.gridPoint(atX: p.x / sx, y: (Double(h) - p.y) / sy)
                if let last = points.last, abs(last.easting - plane.easting) < 1e-9, abs(last.northing - plane.northing) < 1e-9 { continue }
                points.append(plane)
            }
            if points.count > 1, let first = points.first, let last = points.last, abs(first.easting - last.easting) < 1e-9, abs(first.northing - last.northing) < 1e-9 { points.removeLast() }
            guard points.count >= 3, PlaceGeometry.polygon(points).isValid else { return .invalid }
            return .made(area: area, points: points)
        }

        var colours: [TracedColour] = []
        let valid = Double(compact.count)
        var counts = [Int](repeating: 0, count: order.count)
        for label in compact { counts[Int(label)] += 1 }
        for (i, label) in order.enumerated() {
            let isOutside = outside != nil && label == outside
            let isThinColour = Int(label) < centres.count && thin[Int(label)]
            let lab = Int(label) < centres.count ? centres[Int(label)] : (l: 0, a: 0, b: 0)
            let (r, g, b) = Lab.rgb(l: lab.l, a: lab.a, b: lab.b)
            let outlines = isOutside ? [] : (traced[i] ?? []).map(\.points)
            colours.append(TracedColour(
                id: i, red: r, green: g, blue: b, share: Double(counts[i]) / valid, isThin: isThinColour,
                type: isOutside ? .ignore : guess(l: lab.l, a: lab.a, b: lab.b), name: "", outlines: outlines
            ))
        }
        // Thin colours dropped out of the labels above; they are reported too, so the lines can be followed later.
        for (label, isThin) in thin.enumerated() where isThin {
            let lab = centres[label]
            let (r, g, b) = Lab.rgb(l: lab.l, a: lab.a, b: lab.b)
            colours.append(TracedColour(id: colours.count, red: r, green: g, blue: b, share: 0, isThin: true, type: .ignore, name: "", outlines: []))
        }
        name(&colours)
        return MapTrace(colours: colours, width: image.width, height: image.height)
    }

    // MARK: The picture at working size

    /// A picture at working size, lightly blurred to take out the grain of paper, in Lab colour.
    struct Raster {
        var width: Int
        var height: Int
        var l: [Float]
        var a: [Float]
        var b: [Float]

        init?(image: CGImage, size: Int) {
            let longest = max(image.width, image.height)
            guard longest > 0 else { return nil }
            let scale = min(1, Double(size) / Double(longest))
            let width = max(1, Int((Double(image.width) * scale).rounded()))
            let height = max(1, Int((Double(image.height) * scale).rounded()))
            var bytes = [UInt8](repeating: 0, count: width * height * 4)
            let drawn = bytes.withUnsafeMutableBytes { buffer -> Bool in
                guard let context = CGContext(
                    data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                ) else { return false }
                // See-through parts of a picture are taken to be black, which is how its surround is shown.
                context.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
                context.interpolationQuality = .high
                context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
                return true
            }
            guard drawn else { return nil }
            self.width = width
            self.height = height
            l = [Float](repeating: 0, count: width * height)
            a = l
            b = l
            for i in 0..<(width * height) {
                let lab = Lab.lab(red: Double(bytes[i * 4]) / 255, green: Double(bytes[i * 4 + 1]) / 255, blue: Double(bytes[i * 4 + 2]) / 255)
                l[i] = Float(lab.l); a[i] = Float(lab.a); b[i] = Float(lab.b)
            }
            l = Self.blurred(l, width: width, height: height)
            a = Self.blurred(a, width: width, height: height)
            b = Self.blurred(b, width: width, height: height)
        }

        /// A 3 by 3 average.
        static func blurred(_ values: [Float], width: Int, height: Int) -> [Float] {
            var across = values
            for y in 0..<height {
                for x in 0..<width {
                    let left = values[y * width + max(0, x - 1)], right = values[y * width + min(width - 1, x + 1)]
                    across[y * width + x] = (left + values[y * width + x] + right) / 3
                }
            }
            var result = across
            for y in 0..<height {
                for x in 0..<width {
                    result[y * width + x] = (across[max(0, y - 1) * width + x] + across[y * width + x] + across[min(height - 1, y + 1) * width + x]) / 3
                }
            }
            return result
        }
    }

    // MARK: Colours

    typealias LabColour = (l: Float, a: Float, b: Float)

    private static func distance(_ p: LabColour, _ q: LabColour) -> Float {
        let dl = p.l - q.l, da = p.a - q.a, db = p.b - q.b
        return (dl * dl + da * da + db * db).squareRoot()
    }

    /// The main colours of a picture: clusters of a sample of its pixels, with near ones joined, biggest first.
    static func findColours(_ raster: Raster, settings: Settings) -> [LabColour] {
        let count = raster.width * raster.height
        let step = max(1, count / 20_000)
        var samples: [LabColour] = []
        for i in Swift.stride(from: 0, to: count, by: step) { samples.append((raster.l[i], raster.a[i], raster.b[i])) }
        guard !samples.isEmpty else { return [] }
        // Start from the sample nearest the average, then each next colour is the one furthest from those chosen, so rare colours (the
        // ink, a river) get a cluster of their own.
        let mean = (
            l: samples.reduce(0) { $0 + $1.l } / Float(samples.count),
            a: samples.reduce(0) { $0 + $1.a } / Float(samples.count),
            b: samples.reduce(0) { $0 + $1.b } / Float(samples.count)
        )
        var centres: [LabColour] = [samples.min { distance($0, mean) < distance($1, mean) } ?? mean]
        var nearest = samples.map { distance($0, centres[0]) }
        while centres.count < settings.colours {
            guard let far = nearest.indices.max(by: { nearest[$0] < nearest[$1] }), nearest[far] > Float(settings.separation) / 2 else { break }
            centres.append(samples[far])
            for (i, sample) in samples.enumerated() { nearest[i] = min(nearest[i], distance(sample, samples[far])) }
        }
        var sizes = [Int](repeating: 0, count: centres.count)
        for _ in 0..<10 {
            var sums = [(l: Float, a: Float, b: Float)](repeating: (0, 0, 0), count: centres.count)
            sizes = [Int](repeating: 0, count: centres.count)
            for sample in samples {
                var best = 0, bestDistance = Float.infinity
                for (k, centre) in centres.enumerated() {
                    let d = distance(sample, centre)
                    if d < bestDistance { best = k; bestDistance = d }
                }
                sums[best].l += sample.l; sums[best].a += sample.a; sums[best].b += sample.b
                sizes[best] += 1
            }
            for k in centres.indices where sizes[k] > 0 {
                centres[k] = (sums[k].l / Float(sizes[k]), sums[k].a / Float(sizes[k]), sums[k].b / Float(sizes[k]))
            }
        }
        // Join colours too near to be different ones, into the bigger.
        var merged = Array(zip(centres, sizes)).sorted { $0.1 > $1.1 }.filter { $0.1 > 0 }
        var changed = true
        while changed {
            changed = false
            outer: for i in merged.indices {
                for j in merged.indices where j > i && Double(distance(merged[i].0, merged[j].0)) < settings.separation {
                    let total = Float(merged[i].1 + merged[j].1)
                    let wi = Float(merged[i].1) / total, wj = Float(merged[j].1) / total
                    merged[i].0 = (merged[i].0.l * wi + merged[j].0.l * wj, merged[i].0.a * wi + merged[j].0.a * wj, merged[i].0.b * wi + merged[j].0.b * wj)
                    merged[i].1 += merged[j].1
                    merged.remove(at: j)
                    changed = true
                    break outer
                }
            }
        }
        return merged.map(\.0)
    }

    private static func assign(_ raster: Raster, to centres: [LabColour], labels: inout [Int16]) {
        for i in labels.indices {
            let pixel: LabColour = (raster.l[i], raster.a[i], raster.b[i])
            var best = 0, bestDistance = Float.infinity
            for (k, centre) in centres.enumerated() {
                let d = distance(pixel, centre)
                if d < bestDistance { best = k; bestDistance = d }
            }
            labels[i] = Int16(best)
        }
    }

    // MARK: Cleaning up

    /// How many set cells there are in the square of `radius` round each cell, and how many cells that square has (less at the edge).
    private static func windowCounts(_ mask: [Bool], width: Int, height: Int, radius: Int) -> (counts: [Int32], sizes: [Int32]) {
        var across = [Int32](repeating: 0, count: width * height)
        for y in 0..<height {
            var prefix = [Int32](repeating: 0, count: width + 1)
            for x in 0..<width { prefix[x + 1] = prefix[x] + (mask[y * width + x] ? 1 : 0) }
            for x in 0..<width { across[y * width + x] = prefix[min(width, x + radius + 1)] - prefix[max(0, x - radius)] }
        }
        var counts = [Int32](repeating: 0, count: width * height)
        var sizes = counts
        for x in 0..<width {
            var prefix = [Int32](repeating: 0, count: height + 1)
            for y in 0..<height { prefix[y + 1] = prefix[y] + across[y * width + x] }
            let columns = Int32(min(width, x + radius + 1) - max(0, x - radius))
            for y in 0..<height {
                let top = min(height, y + radius + 1), bottom = max(0, y - radius)
                counts[y * width + x] = prefix[top] - prefix[bottom]
                sizes[y * width + x] = columns * Int32(top - bottom)
            }
        }
        return (counts, sizes)
    }

    /// Takes the colour off strokes: what is left of a colour's pixels after taking `thinRadius` off every edge and putting it back is
    /// the part of it that is wide enough to be an area. Returns which colours are only strokes, which have nothing left.
    private static func removeStrokes(_ labels: inout [Int16], count colours: Int, width: Int, height: Int, settings: Settings) -> [Bool] {
        var result = [Bool](repeating: false, count: colours)
        let r = settings.thinRadius
        var keep = [Bool](repeating: false, count: labels.count)
        for colour in 0..<colours {
            let mask = labels.map { Int($0) == colour }
            let before = mask.reduce(0) { $0 + ($1 ? 1 : 0) }
            guard before > 0 else { result[colour] = true; continue }
            let eroded = windowCounts(mask, width: width, height: height, radius: r)
            let core = (0..<mask.count).map { eroded.counts[$0] == eroded.sizes[$0] }
            let after = core.reduce(0) { $0 + ($1 ? 1 : 0) }
            if Double(after) < settings.thinShare * Double(before) { result[colour] = true; continue }
            let grown = windowCounts(core, width: width, height: height, radius: r)
            for i in mask.indices where mask[i] && grown.counts[i] > 0 { keep[i] = true }
        }
        for i in labels.indices where result[Int(labels[i])] || !keep[i] { labels[i] = -1 }
        return result
    }

    /// Gives every pixel with no colour (-1) the colour nearest it, spreading outwards from the others. False if none has one.
    private static func fill(_ labels: inout [Int16], width: Int, height: Int) -> Bool {
        var queue: [Int] = []
        for y in 0..<height {
            for x in 0..<width where labels[y * width + x] >= 0 {
                let i = y * width + x
                if (x > 0 && labels[i - 1] < 0) || (x + 1 < width && labels[i + 1] < 0) || (y > 0 && labels[i - width] < 0) || (y + 1 < height && labels[i + width] < 0) {
                    queue.append(i)
                }
            }
        }
        if queue.isEmpty { return !labels.contains(-1) }
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i % width, y = i / width
            for n in [x > 0 ? i - 1 : -1, x + 1 < width ? i + 1 : -1, y > 0 ? i - width : -1, y + 1 < height ? i + width : -1] where n >= 0 && labels[n] < 0 {
                labels[n] = labels[i]
                queue.append(n)
            }
        }
        return true
    }

    /// Takes the colour off patches of fewer than `smallest` pixels.
    private static func removeSmallPatches(_ labels: inout [Int16], width: Int, height: Int, smallest: Int) {
        var seen = [Bool](repeating: false, count: labels.count)
        for start in labels.indices where !seen[start] && labels[start] >= 0 {
            let colour = labels[start]
            var patch = [start]
            seen[start] = true
            var head = 0
            while head < patch.count {
                let i = patch[head]
                head += 1
                let x = i % width, y = i / width
                for n in [x > 0 ? i - 1 : -1, x + 1 < width ? i + 1 : -1, y > 0 ? i - width : -1, y + 1 < height ? i + width : -1] where n >= 0 && !seen[n] && labels[n] == colour {
                    seen[n] = true
                    patch.append(n)
                }
            }
            if patch.count < smallest { for i in patch { labels[i] = -1 } }
        }
    }

    /// Gives the dark surround of a picture, which reaches its edge, a colour of its own, and says which. Nil if there is none.
    private static func markOutside(_ labels: inout [Int16], centres: [LabColour], width: Int, height: Int) -> Int16? {
        let dark = Set(centres.indices.filter { centres[$0].l < 25 }.map { Int16($0) })
        guard !dark.isEmpty else { return nil }
        let outside = Int16(centres.count)
        var queue: [Int] = []
        func take(_ i: Int) {
            if dark.contains(labels[i]) { labels[i] = outside; queue.append(i) }
        }
        for x in 0..<width { take(x); take((height - 1) * width + x) }
        for y in 0..<height { take(y * width); take(y * width + width - 1) }
        guard !queue.isEmpty else { return nil }
        var head = 0
        while head < queue.count {
            let i = queue[head]
            head += 1
            let x = i % width, y = i / width
            if x > 0 { take(i - 1) }
            if x + 1 < width { take(i + 1) }
            if y > 0 { take(i - width) }
            if y + 1 < height { take(i + width) }
        }
        return outside
    }

    // MARK: Guessing

    /// What an area of a colour probably is. Only a guess, for the user to correct.
    static func guess(l: Float, a: Float, b: Float) -> TracedType {
        // Black is the surround or ink, not land.
        if l < 22 { return .ignore }
        let chroma = (a * a + b * b).squareRoot()
        var hue = Double(atan2(b, a)) * 180 / .pi
        if hue < 0 { hue += 360 }
        // Blues are water.
        if chroma > 10, hue > 215, hue < 290 { return .water }
        // Dark greens are forest; paler ones are land.
        if chroma > 12, hue > 100, hue < 175, l < 52 { return .forest }
        // Greys and greyish browns are mountains.
        if chroma < 14, l > 35, l < 75 { return .mountains }
        // Sandy yellows and tans that are darker than paper are wilderness; the rest is land.
        if chroma > 14, hue > 55, hue < 85, l < 72 { return .wilderness }
        return .region
    }

    /// Gives each area a name to start with: its type and a number.
    private static func name(_ colours: inout [TracedColour]) {
        var counts: [TracedType: Int] = [:]
        for i in colours.indices where !colours[i].outlines.isEmpty && colours[i].type != .ignore {
            counts[colours[i].type, default: 0] += 1
            let n = counts[colours[i].type] ?? 1
            colours[i].name = colours[i].type == .ignore ? "" : "\(colours[i].type.title) \(n)"
        }
    }
}

/// Colour in CIE Lab, for telling how different two colours look.
nonisolated enum Lab {
    private static func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func gamma(_ c: Double) -> Double { c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055 }

    static func lab(red: Double, green: Double, blue: Double) -> (l: Double, a: Double, b: Double) {
        let r = linear(red), g = linear(green), b = linear(blue)
        let x = (0.4124564 * r + 0.3575761 * g + 0.1804375 * b) / 0.95047
        let y = 0.2126729 * r + 0.7151522 * g + 0.0721750 * b
        let z = (0.0193339 * r + 0.1191920 * g + 0.9503041 * b) / 1.08883
        func f(_ t: Double) -> Double { t > 0.008856 ? cbrt(t) : 7.787 * t + 16.0 / 116 }
        return (116 * f(y) - 16, 500 * (f(x) - f(y)), 200 * (f(y) - f(z)))
    }

    static func rgb(l: Float, a: Float, b: Float) -> (Double, Double, Double) {
        let fy = (Double(l) + 16) / 116, fx = Double(a) / 500 + fy, fz = fy - Double(b) / 200
        func inverse(_ t: Double) -> Double { t * t * t > 0.008856 ? t * t * t : (t - 16.0 / 116) / 7.787 }
        let x = inverse(fx) * 0.95047, y = inverse(fy), z = inverse(fz) * 1.08883
        let r = 3.2404542 * x - 1.5371385 * y - 0.4985314 * z
        let g = -0.9692660 * x + 1.8760108 * y + 0.0415560 * z
        let bl = 0.0556434 * x - 0.2040259 * y + 1.0572252 * z
        func clamp(_ c: Double) -> Double { min(max(gamma(max(c, 0)), 0), 1) }
        return (clamp(r), clamp(g), clamp(bl))
    }
}
