//
//  InkRenderer.swift
//  encounter
//

import MapKit

/// Draws an outline or a line as if by hand: with a slight wander from the true line and a stroke that thickens and thins, in a
/// size that stays the same on screen at every zoom (a pen does not get bigger as you zoom). The wander depends only on where a
/// point is, so the tiles MapKit draws a line in join up without a break, and it is the same every time.
final class InkRenderer: MKOverlayRenderer {
    let rings: [[MKMapPoint]]
    /// The smallest rectangle round the shape.
    let bounds: MKMapRect
    private let decoration: InkDecoration?
    private let wash: MapStyle.Wash?
    /// The accent colour the place is highlighted in, if it is the one chosen.
    private let highlight: CGColor?
    /// How much of its own thickness the line is drawn at, for how many points per MapKit point the view has; nil for always all of it.
    private let thickness: ((Double) -> Double)?
    private let isClosed: Bool
    private let fill: CGColor?
    private let stroke: CGColor
    private let width: Double
    private let dash: [Double]?
    private let hand: MapStyle.HandDrawn

    /// The outline of an area, and the holes cut in it.
    init(polygon: MKPolygon, fill: CGColor?, stroke: CGColor, width: Double, dash: [Double]?, hand: MapStyle.HandDrawn, decoration: InkDecoration? = nil, wash: MapStyle.Wash? = nil, highlight: CGColor? = nil) {
        thickness = nil
        rings = ([polygon] + (polygon.interiorPolygons ?? [])).map(Self.mapPoints)
        bounds = polygon.boundingMapRect
        self.decoration = decoration
        self.wash = wash
        self.highlight = highlight
        isClosed = true
        self.fill = fill
        self.stroke = stroke
        self.width = width
        self.dash = dash
        self.hand = hand
        super.init(overlay: polygon)
    }

    /// A line.
    init(line: MKPolyline, stroke: CGColor, width: Double, dash: [Double]?, hand: MapStyle.HandDrawn, highlight: CGColor? = nil, thickness: ((Double) -> Double)? = nil) {
        self.thickness = thickness
        rings = [Self.mapPoints(of: line)]
        bounds = line.boundingMapRect
        decoration = nil
        wash = nil
        self.highlight = highlight
        isClosed = false
        fill = nil
        self.stroke = stroke
        self.width = width
        self.dash = dash
        self.hand = hand
        super.init(overlay: line)
    }

    /// A shape's points in MapKit's own coordinates, worked out from its map coordinates (the points a shape keeps are not all measured
    /// from the same place).
    private static func mapPoints(of shape: MKMultiPoint) -> [MKMapPoint] {
        var coordinates = [CLLocationCoordinate2D](repeating: CLLocationCoordinate2D(), count: shape.pointCount)
        shape.getCoordinates(&coordinates, range: NSRange(location: 0, length: shape.pointCount))
        return coordinates.map(MKMapPoint.init)
    }

    private struct Sample {
        var point: CGPoint
        /// How much thicker or thinner than the plain stroke it is here, about 1.
        var weight: Double
        /// How far along the line it is, in MapKit's points.
        var along: Double
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let screen = 1 / Double(zoomScale)   // one point on screen, in MapKit's points
        if let fill, isClosed {
            context.beginPath()
            for ring in rings where ring.count >= 3 {
                context.move(to: point(for: ring[0]))
                for p in ring.dropFirst() { context.addLine(to: point(for: p)) }
                context.closePath()
            }
            context.setFillColor(fill)
            context.fillPath(using: .evenOdd)
            // Paint gathers at the edge of a wash: a few bands of the edge colour, widest and faintest first, kept inside the wash.
            if let wash {
                context.saveGState()
                context.beginPath()
                for ring in rings where ring.count >= 3 {
                    context.move(to: point(for: ring[0]))
                    for p in ring.dropFirst() { context.addLine(to: point(for: p)) }
                    context.closePath()
                }
                context.clip(using: .evenOdd)
                context.setLineJoin(.round)
                for (share, alpha) in [(1.0, 0.35), (0.62, 0.55), (0.3, 0.9)] {
                    context.setStrokeColor(stroke.copy(alpha: stroke.alpha * wash.strength * alpha * 0.5) ?? stroke)
                    context.setLineWidth(wash.band * share * 2 * screen)
                    context.beginPath()
                    for ring in rings where ring.count >= 3 {
                        context.move(to: point(for: ring[0]))
                        for p in ring.dropFirst() { context.addLine(to: point(for: p)) }
                        context.closePath()
                    }
                    context.strokePath()
                }
                context.restoreGState()
            }
        }
        // A highlighted area is washed with the accent colour and outlined heavily in it; a highlighted line gets a wide pale halo of it behind
        // its own stroke.
        if let highlight, isClosed {
            context.beginPath()
            for ring in rings where ring.count >= 3 {
                context.move(to: point(for: ring[0]))
                for p in ring.dropFirst() { context.addLine(to: point(for: p)) }
                context.closePath()
            }
            context.setFillColor(highlight.copy(alpha: 0.22) ?? highlight)
            context.fillPath(using: .evenOdd)
        }
        var pens: [(color: CGColor, width: Double, dash: [Double]?)] = [(stroke, width, dash)]
        if let highlight {
            pens = isClosed
                // An empty dash is a solid line drawn as one stroke, so a translucent halo has no darker beads where pieces overlap.
                ? [(highlight, max(width * 1.6, 2.5), [])]
                : [(highlight.copy(alpha: 0.32) ?? highlight, width + 9, []), (stroke, width, dash)]
        }
        // Thinner, and fainter, the further out the view is, or not drawn at all.
        if let thickness {
            let factor = thickness(Double(zoomScale))
            guard factor > 0 else { return }
            pens = pens.map { ($0.color.copy(alpha: $0.color.alpha * (0.6 + 0.4 * factor)) ?? $0.color, $0.width * factor, $0.dash) }
        }
        for pen in pens where pen.width > 0 { strokePass(pen, mapRect: mapRect, zoomScale: zoomScale, in: context) }
        if let decoration { drawDecoration(decoration, mapRect: mapRect, zoomScale: zoomScale, in: context) }
    }

    /// The whole of the outline or line, drawn once in one pen.
    private func strokePass(_ pen: (color: CGColor, width: Double, dash: [Double]?), mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        let screen = 1 / Double(zoomScale)
        context.setStrokeColor(pen.color)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let spacing = 3 * screen
        let reach = (pen.width + hand.amplitude * 2 + 4) * screen
        let visible = mapRect.insetBy(dx: -reach, dy: -reach)

        for ring in rings where ring.count >= 2 {
            let segments = isClosed ? ring.count : ring.count - 1
            var run: [Sample] = []
            var along = 0.0
            for i in 0..<segments {
                let a = ring[i], b = ring[(i + 1) % ring.count]
                let dx = b.x - a.x, dy = b.y - a.y
                let length = hypot(dx, dy)
                defer { along += length }
                guard length > 0 else { continue }
                let box = MKMapRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(dx), height: abs(dy))
                guard box.intersects(visible) else {
                    stroke(run, pen: pen, zoomScale: zoomScale, in: context)
                    run = []
                    continue
                }
                let normalX = -dy / length, normalY = dx / length
                let pieces = max(1, Int(length / spacing))
                for k in (run.isEmpty ? 0 : 1)...pieces {
                    let t = Double(k) / Double(pieces)
                    let x = a.x + dx * t, y = a.y + dy * t
                    // Noise by where the point is on screen, so the same place is wobbled the same way in whichever tile it is drawn.
                    let u = x * Double(zoomScale), v = y * Double(zoomScale)
                    let slow = PaperTexture.noise(u / hand.wavelength, v / hand.wavelength, 101) - 0.5
                    let fast = PaperTexture.noise(u / (hand.wavelength * 0.35), v / (hand.wavelength * 0.35), 102) - 0.5
                    let push = (slow + 0.45 * fast) * 2 / 1.45 * hand.amplitude * screen
                    let thick = (PaperTexture.noise(u / (hand.wavelength * 2.5), v / (hand.wavelength * 2.5), 103) - 0.5) * 2
                    run.append(Sample(
                        point: point(for: MKMapPoint(x: x + normalX * push, y: y + normalY * push)),
                        weight: 1 + hand.weight * thick, along: along + length * t
                    ))
                }
            }
            stroke(run, pen: pen, zoomScale: zoomScale, in: context)
        }
    }

    /// A stretch of line, in pieces of different thickness, or all at once if it is dashed (a dash can't be thicker in one place).
    private func stroke(_ run: [Sample], pen: (color: CGColor, width: Double, dash: [Double]?), zoomScale: MKZoomScale, in context: CGContext) {
        guard run.count >= 2 else { return }
        let screen = 1 / Double(zoomScale)
        if let dash = pen.dash {
            context.setLineWidth(pen.width * screen)
            context.setLineDash(phase: CGFloat(run[0].along), lengths: dash.map { CGFloat($0 * screen) })
            context.beginPath()
            context.move(to: run[0].point)
            for sample in run.dropFirst() { context.addLine(to: sample.point) }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            return
        }
        for i in 1..<run.count {
            context.setLineWidth(pen.width * screen * (run[i].weight + run[i - 1].weight) / 2)
            context.move(to: run[i - 1].point)
            context.addLine(to: run[i].point)
            context.strokePath()
        }
    }
}

// MARK: Preview

import SwiftUI

/// A style's look on a few shapes, drawn straight into a picture (a preview can't show MapKit itself).
@MainActor
func inkSample(_ style: MapStyle, zoomScale: Double = 1, highlighted: Set<String> = []) -> Image {
    let size = CGSize(width: 520, height: 330)
    let context = CGContext(
        data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: 2, y: -2)
    context.translateBy(x: 0, y: -size.height)
    let ground = style.background
    context.setFillColor(CGColor(red: ground.red, green: ground.green, blue: ground.blue, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    // MapKit points are `zoomScale` times a point on screen, so the shapes are drawn that much smaller to land in the same picture.
    let k = 1 / zoomScale
    // Near the middle of the world's map, where coordinates are exact, and moved back to the corner of the picture.
    let origin = MKMapPoint(x: 134_217_728, y: 134_217_728)
    context.scaleBy(x: zoomScale, y: zoomScale)
    func polygon(_ points: [(Double, Double)], holes: [MKPolygon] = []) -> MKPolygon {
        var map = points.map { MKMapPoint(x: origin.x + $0.0 * k, y: origin.y + $0.1 * k).coordinate }
        return MKPolygon(coordinates: &map, count: map.count, interiorPolygons: holes.isEmpty ? nil : holes)
    }
    func line(_ points: [(Double, Double)]) -> MKPolyline {
        var map = points.map { MKMapPoint(x: origin.x + $0.0 * k, y: origin.y + $0.1 * k).coordinate }
        return MKPolyline(coordinates: &map, count: map.count)
    }
    let rect = MKMapRect(x: origin.x, y: origin.y, width: size.width * k, height: size.height * k)
    // A renderer draws in a space whose corner is the corner of its overlay, which MapKit sets up; here it is set up by hand.
    func draw(_ renderer: InkRenderer?) {
        guard let renderer else { return }
        let corner = renderer.overlay.boundingMapRect.origin
        context.saveGState()
        context.translateBy(x: corner.x - origin.x, y: corner.y - origin.y)
        renderer.draw(rect, zoomScale: MKZoomScale(zoomScale), in: context)
        context.restoreGState()
    }
    let land = polygon([(40, 60), (200, 30), (330, 70), (360, 150), (300, 250), (180, 290), (70, 240), (30, 140)])
    draw(.make(polygon: polygon([(0, 0), (520, 0), (520, 330), (0, 330)], holes: [land]), type: "Water", style: style, highlighted: highlighted.contains("Water")))
    draw(.make(polygon: polygon([(70, 90), (150, 80), (195, 125), (175, 205), (100, 215), (60, 150)]), type: "Forest", style: style, highlighted: highlighted.contains("Forest")))
    draw(.make(polygon: polygon([(225, 80), (340, 95), (350, 175), (265, 205), (215, 150)]), type: "Mountains", style: style, highlighted: highlighted.contains("Mountains")))
    draw(.make(polygon: polygon([(255, 235), (325, 228), (340, 265), (290, 295), (248, 270)]), type: "Lake", style: style, highlighted: highlighted.contains("Lake")))
    draw(.make(line: line([(120, 80), (150, 140), (130, 190), (190, 240), (170, 310)]), type: "River", style: style, highlighted: highlighted.contains("River")))
    draw(.make(line: line([(60, 200), (160, 170), (250, 190), (340, 130), (480, 150)]), type: "Road", style: style, highlighted: highlighted.contains("Road")))
    draw(.make(line: line([(200, 40), (210, 120), (250, 190), (240, 270)]), type: "Region", style: style, highlighted: highlighted.contains("Region")))
    return Image(decorative: context.makeImage()!, scale: 2)
}

#Preview("Parchment ink") { inkSample(.parchment) }
#Preview("Parchment ink, zoomed") { inkSample(.parchment, zoomScale: 4) }
#Preview("Survey ink") { inkSample(.survey) }
#Preview("Watercolour ink") { inkSample(.watercolour) }

#Preview("Highlighted, Parchment") { inkSample(.parchment, highlighted: ["Forest", "River", "Region"]) }
#Preview("Highlighted, Dark") { inkSample(.dark, highlighted: ["Mountains", "Road"]) }
#Preview("Highlighted, Survey") { inkSample(.survey, highlighted: ["Forest", "Road"]) }
#Preview("Highlighted, Watercolour") { inkSample(.watercolour, highlighted: ["Mountains", "River"]) }
