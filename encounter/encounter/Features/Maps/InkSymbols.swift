//
//  InkSymbols.swift
//  encounter
//

import MapKit

/// What is drawn over and beside an area, besides its outline: trees across a forest, peaks across mountains, and lines along a shore.
enum InkDecoration {
    /// Small drawn trees scattered over the area.
    case trees(ink: CGColor, wash: CGColor, regular: Bool, soft: Bool)
    /// Drawn peaks scattered over the area, filled with `ground` so those in front hide those behind, or contour lines, or soft dabs.
    case peaks(ink: CGColor, ground: CGColor, contours: Bool, soft: Bool)
    /// Lines that follow the shore, a little way out into the water: round every hole of the area (land in the sea), or just inside the
    /// outline of the area (a lake).
    case shore(ink: CGColor, inside: Bool, soft: Bool)
}

extension InkRenderer {
    /// A number from a place on a lattice and a salt, the same every time.
    private static func hash(_ a: Int, _ b: Int, _ salt: UInt64) -> UInt64 {
        var x = UInt64(bitPattern: Int64(a)) &* 0x9E3779B97F4A7C15 ^ UInt64(bitPattern: Int64(b)) &* 0xBF58476D1CE4E5B9 ^ salt &* 0x94D049BB133111EB
        x ^= x >> 30
        x = x &* 0xBF58476D1CE4E5B9
        x ^= x >> 27
        x = x &* 0x94D049BB133111EB
        return x ^ (x >> 31)
    }

    private static func unit(_ h: UInt64, _ shift: UInt64) -> Double { Double((h >> shift) & 0xFFFF) / 65535 }

    /// Whether a place is inside the area, counting its holes as outside.
    private func inside(_ p: MKMapPoint) -> Bool {
        var count = 0
        for ring in rings {
            var j = ring.count - 1
            for i in ring.indices {
                let a = ring[i], b = ring[j]
                if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { count += 1 }
                j = i
            }
        }
        return count % 2 == 1
    }

    func drawDecoration(_ decoration: InkDecoration, mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let screen = 1 / Double(zoomScale)
        switch decoration {
        case .trees(let ink, let wash, let regular, let soft):
            scatter(mapRect: mapRect, zoomScale: zoomScale, spacing: regular ? 24 : 36, keep: regular ? 1 : 0.55, tidy: regular, salt: 7, in: context) { c, size, h in
                tree(at: c, size: size, h: h, ink: ink, wash: wash, regular: regular, soft: soft, screen: screen, in: context)
            }
        case .peaks(let ink, let ground, let contours, let soft):
            if contours {
                self.contours(ink: ink, zoomScale: zoomScale, in: context)
            } else {
                scatter(mapRect: mapRect, zoomScale: zoomScale, spacing: 56, keep: 0.6, tidy: false, salt: 11, in: context) { c, size, h in
                    peak(at: c, size: size, h: h, ink: ink, ground: ground, soft: soft, screen: screen, in: context)
                }
            }
        case .shore(let ink, let inward, let soft):
            shore(ink: ink, inward: inward, soft: soft, mapRect: mapRect, zoomScale: zoomScale, in: context)
        }
    }

    // MARK: Scattered symbols

    /// Calls `draw` for a place on a lattice that is jittered, and so looks scattered, wherever it is inside the area. The lattice is
    /// fixed to the map and its cell is a power of two times a fixed size, so every tile agrees on where the symbols are and the
    /// same ones stay put between one zoom and the next.
    private func scatter(mapRect: MKMapRect, zoomScale: MKZoomScale, spacing: Double, keep: Double, tidy: Bool, salt: UInt64, in context: CGContext, draw: (CGPoint, Double, UInt64) -> Void) {
        let screen = 1 / Double(zoomScale)
        let cell = pow(2, (log2(spacing * screen)).rounded())
        let onScreen = cell / screen
        let size = min(max(onScreen * 0.32, 5), 15)
        let box = bounds
        let reach = size * screen
        let area = mapRect.intersection(box.insetBy(dx: -reach, dy: -reach)).insetBy(dx: -reach, dy: -reach)
        guard !area.isNull, !area.isEmpty else { return }
        let first = (Int((area.minX / cell).rounded(.down)), Int((area.minY / cell).rounded(.down)))
        let last = (Int((area.maxX / cell).rounded(.up)), Int((area.maxY / cell).rounded(.up)))
        guard (last.0 - first.0 + 1) * (last.1 - first.1 + 1) < 40_000 else { return }
        var placed: [(y: Double, point: MKMapPoint, h: UInt64)] = []
        for ix in first.0...last.0 {
            for iy in first.1...last.1 {
                let h = Self.hash(ix, iy, salt)
                let p = tidy
                    ? MKMapPoint(x: (Double(ix) + 0.5) * cell, y: (Double(iy) + 0.5) * cell)
                    : MKMapPoint(x: (Double(ix) + 0.15 + 0.7 * Self.unit(h, 0)) * cell, y: (Double(iy) + 0.15 + 0.7 * Self.unit(h, 16)) * cell)
                // Only some of the lattice's places have a symbol, so they are scattered and not in a pattern.
                if Self.unit(h &* 0x9E3779B97F4A7C15, 20) < keep, inside(p) { placed.append((p.y, p, h)) }
            }
        }
        // Back to front, so a nearer symbol is drawn over a farther.
        for item in placed.sorted(by: { $0.y < $1.y }) { draw(point(for: item.point), size * screen, item.h) }
    }

    private func tree(at c: CGPoint, size r: Double, h: UInt64, ink: CGColor, wash: CGColor, regular: Bool, soft: Bool, screen: Double, in context: CGContext) {
        if soft {
            // A dab of colour with a darker dab in it, and no outline.
            context.setFillColor(wash)
            context.fillEllipse(in: CGRect(x: c.x - r * 0.9, y: c.y - r * 1.9, width: r * 1.8, height: r * 1.7))
            context.setFillColor(ink.copy(alpha: 0.35) ?? ink)
            context.fillEllipse(in: CGRect(x: c.x - r * 0.35, y: c.y - r * 1.2, width: r * 1.1, height: r * 0.9))
            return
        }
        if regular {
            // A survey's signs: a ring with a dot for a tree in leaf, a small triangle for a fir.
            context.setStrokeColor(ink)
            context.setLineWidth(0.7 * screen)
            if Self.unit(h, 32) < 0.6 {
                context.strokeEllipse(in: CGRect(x: c.x - r * 0.55, y: c.y - r * 1.1, width: r * 1.1, height: r * 1.1))
                context.setFillColor(ink)
                context.fillEllipse(in: CGRect(x: c.x - r * 0.12, y: c.y - r * 0.67, width: r * 0.24, height: r * 0.24))
            } else {
                context.beginPath()
                context.move(to: CGPoint(x: c.x, y: c.y - r * 1.3))
                context.addLine(to: CGPoint(x: c.x + r * 0.6, y: c.y - r * 0.1))
                context.addLine(to: CGPoint(x: c.x - r * 0.6, y: c.y - r * 0.1))
                context.closePath()
                context.strokePath()
            }
            return
        }
        context.setStrokeColor(ink)
        context.setFillColor(wash)
        context.setLineWidth(0.9 * screen)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        if Self.unit(h, 32) < 0.6 {
            // A tree in leaf: a lumpy round crown on a short trunk.
            let middle = CGPoint(x: c.x, y: c.y - r * 1.0)
            context.beginPath()
            for k in 0..<9 {
                let angle = Double(k) / 9 * 2 * .pi
                let lump = r * (0.8 + 0.35 * Self.unit(h &>> UInt64(k), UInt64(k)))
                let p = CGPoint(x: middle.x + cos(angle) * lump * 0.85, y: middle.y + sin(angle) * lump)
                k == 0 ? context.move(to: p) : context.addLine(to: p)
            }
            context.closePath()
            context.drawPath(using: .fillStroke)
            context.move(to: CGPoint(x: c.x, y: middle.y + r * 0.9))
            context.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.35))
            context.strokePath()
        } else {
            // A fir: a narrow triangle with a notch in each side.
            context.beginPath()
            context.move(to: CGPoint(x: c.x, y: c.y - r * 2.2))
            context.addLine(to: CGPoint(x: c.x + r * 0.55, y: c.y - r * 1.2))
            context.addLine(to: CGPoint(x: c.x + r * 0.3, y: c.y - r * 1.2))
            context.addLine(to: CGPoint(x: c.x + r * 0.8, y: c.y - r * 0.1))
            context.addLine(to: CGPoint(x: c.x - r * 0.8, y: c.y - r * 0.1))
            context.addLine(to: CGPoint(x: c.x - r * 0.3, y: c.y - r * 1.2))
            context.addLine(to: CGPoint(x: c.x - r * 0.55, y: c.y - r * 1.2))
            context.closePath()
            context.drawPath(using: .fillStroke)
            context.move(to: CGPoint(x: c.x, y: c.y - r * 0.1))
            context.addLine(to: CGPoint(x: c.x, y: c.y + r * 0.4))
            context.strokePath()
        }
    }

    private func peak(at c: CGPoint, size w: Double, h: UInt64, ink: CGColor, ground: CGColor, soft: Bool, screen: Double, in context: CGContext) {
        if soft {
            // A soft brown hill with a darker flank, and no outline.
            let height = w * (0.8 + 0.4 * Self.unit(h, 32))
            context.setFillColor(ink.copy(alpha: 0.3) ?? ink)
            context.beginPath()
            context.move(to: CGPoint(x: c.x - w * 1.1, y: c.y))
            context.addQuadCurve(to: CGPoint(x: c.x, y: c.y - height), control: CGPoint(x: c.x - w * 0.5, y: c.y - height * 0.9))
            context.addQuadCurve(to: CGPoint(x: c.x + w * 1.1, y: c.y), control: CGPoint(x: c.x + w * 0.5, y: c.y - height * 0.9))
            context.closePath()
            context.fillPath()
            context.setFillColor(ink.copy(alpha: 0.25) ?? ink)
            context.beginPath()
            context.move(to: CGPoint(x: c.x, y: c.y - height))
            context.addQuadCurve(to: CGPoint(x: c.x + w * 1.1, y: c.y), control: CGPoint(x: c.x + w * 0.5, y: c.y - height * 0.9))
            context.addLine(to: CGPoint(x: c.x + w * 0.2, y: c.y))
            context.closePath()
            context.fillPath()
            return
        }
        let height = w * (1.0 + 0.5 * Self.unit(h, 32))
        let lean = (Self.unit(h, 48) - 0.5) * 0.3 * w
        context.setStrokeColor(ink)
        context.setFillColor(ground)
        context.setLineWidth(1.0 * screen)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        // A peak with a little shoulder on its right, and a few strokes of shade down its right side.
        let top = CGPoint(x: c.x + lean, y: c.y - height)
        context.beginPath()
        context.move(to: CGPoint(x: c.x - w, y: c.y))
        context.addLine(to: CGPoint(x: top.x - w * 0.05, y: top.y))
        context.addLine(to: CGPoint(x: top.x + w * 0.12, y: top.y + height * 0.06))
        context.addLine(to: CGPoint(x: c.x + w * 0.45, y: c.y - height * 0.45))
        context.addLine(to: CGPoint(x: c.x + w * 0.6, y: c.y - height * 0.38))
        context.addLine(to: CGPoint(x: c.x + w, y: c.y))
        context.closePath()
        context.drawPath(using: .fillStroke)
        context.setLineWidth(0.7 * screen)
        for k in 1...3 {
            let t = Double(k) / 4
            let start = CGPoint(x: top.x + w * 0.12 + (w * 0.9 - w * 0.12 - lean) * t * 0.55, y: top.y + height * 0.06 + height * 0.55 * t)
            context.move(to: start)
            context.addLine(to: CGPoint(x: start.x + w * 0.22, y: start.y + height * 0.34 * (1 - t * 0.4)))
        }
        context.strokePath()
    }

    // MARK: Lines along a shore

    /// Mountains as contour lines: the outline drawn again, smaller and smaller, about the middle of the area.
    private func contours(ink: CGColor, zoomScale: MKZoomScale, in context: CGContext) {
        let screen = 1 / Double(zoomScale)
        guard rings[0].count >= 3 else { return }
        let middle = MKMapPoint(x: bounds.midX, y: bounds.midY)
        context.saveGState()
        context.beginPath()
        for ring in rings {
            context.move(to: point(for: ring[0]))
            for p in ring.dropFirst() { context.addLine(to: point(for: p)) }
            context.closePath()
        }
        context.clip(using: .evenOdd)
        context.setStrokeColor(ink)
        context.setLineWidth(0.6 * screen)
        context.setLineJoin(.round)
        for step in 1...4 {
            let scale = 1 - Double(step) * 0.2
            context.beginPath()
            for (i, p) in rings[0].enumerated() {
                let q = point(for: MKMapPoint(x: middle.x + (p.x - middle.x) * scale, y: middle.y + (p.y - middle.y) * scale))
                i == 0 ? context.move(to: q) : context.addLine(to: q)
            }
            context.closePath()
            context.strokePath()
        }
        context.restoreGState()
    }

    private func shore(ink: CGColor, inward: Bool, soft: Bool, mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let screen = 1 / Double(zoomScale)
        let reach = 14 * screen
        let visible = mapRect.insetBy(dx: -reach, dy: -reach)
        let outlines = inward ? [rings[0]] : Array(rings.dropFirst())
        context.setStrokeColor(ink)
        context.setLineCap(.round)
        // Dashed and fine, or for a wash one wide soft band after another with no break.
        let lines: [(offset: Double, width: Double, alpha: Double, dash: [Double])] = soft
            ? [(4, 6, 0.22, []), (9, 8, 0.12, [])]
            : [(3.5, 0.9, 0.6, [16, 4]), (7, 0.7, 0.42, [10, 7]), (10.5, 0.55, 0.26, [6, 9])]
        for ring in outlines where ring.count >= 3 {
            // Not round a speck of an island or a pond, where the lines would only be a smudge.
            let xs = ring.map(\.x), ys = ring.map(\.y)
            guard (xs.max() ?? 0) - (xs.min() ?? 0) > 40 * screen || (ys.max() ?? 0) - (ys.min() ?? 0) > 40 * screen else { continue }
            // Which side of the line is out: the side that is not inside the ring, or for a lake the side that is.
            var flip = 1.0
            if let long = ring.indices.max(by: { hypot(ring[($0 + 1) % ring.count].x - ring[$0].x, ring[($0 + 1) % ring.count].y - ring[$0].y) < hypot(ring[($1 + 1) % ring.count].x - ring[$1].x, ring[($1 + 1) % ring.count].y - ring[$1].y) }) {
                let a = ring[long], b = ring[(long + 1) % ring.count]
                let length = hypot(b.x - a.x, b.y - a.y)
                if length > 0 {
                    let nx = -(b.y - a.y) / length, ny = (b.x - a.x) / length
                    let probe = MKMapPoint(x: (a.x + b.x) / 2 + nx * length * 0.01, y: (a.y + b.y) / 2 + ny * length * 0.01)
                    let insideRing = Self.contains(ring, probe)
                    flip = (insideRing == inward) ? 1 : -1
                }
            }
            for line in lines {
                context.setLineWidth(line.width * screen)
                context.setLineDash(phase: 0, lengths: line.dash.map { CGFloat($0 * screen) })
                context.setAlpha(line.alpha)
                var along = 0.0
                var drawing = false
                for i in ring.indices {
                    let a = ring[i], b = ring[(i + 1) % ring.count]
                    let dx = b.x - a.x, dy = b.y - a.y
                    let length = hypot(dx, dy)
                    defer { along += length }
                    guard length > 0 else { continue }
                    let box = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(dx), height: abs(dy))
                    guard box.intersects(visible) else {
                        if drawing { context.strokePath(); drawing = false }
                        continue
                    }
                    let nx = -dy / length * flip * line.offset * screen, ny = dx / length * flip * line.offset * screen
                    let from = point(for: MKMapPoint(x: a.x + nx, y: a.y + ny)), to = point(for: MKMapPoint(x: b.x + nx, y: b.y + ny))
                    if !drawing { context.beginPath(); context.move(to: from); drawing = true }
                    context.addLine(to: to)
                }
                if drawing { context.strokePath() }
            }
        }
        context.setAlpha(1)
        context.setLineDash(phase: 0, lengths: [])
    }

    private static func contains(_ ring: [MKMapPoint], _ p: MKMapPoint) -> Bool {
        var inside = false
        var j = ring.count - 1
        for i in ring.indices {
            let a = ring[i], b = ring[j]
            if (a.y > p.y) != (b.y > p.y), p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { inside.toggle() }
            j = i
        }
        return inside
    }
}
