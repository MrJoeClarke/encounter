//
//  InkRenderer.swift
//  encounter
//

import MapKit

/// Draws an outline or a line as if by hand: with a slight wander from the true line and a stroke that thickens and thins, in a
/// size that stays the same on screen at every zoom (a pen does not get bigger as you zoom). The wander depends only on where a
/// point is, so the tiles MapKit draws a line in join up without a break, and it is the same every time.
final class InkRenderer: MKOverlayRenderer {
    private let rings: [[MKMapPoint]]
    private let isClosed: Bool
    private let fill: CGColor?
    private let stroke: CGColor
    private let width: Double
    private let dash: [Double]?
    private let hand: MapStyle.HandDrawn

    /// The outline of an area, and the holes cut in it.
    init(polygon: MKPolygon, fill: CGColor?, stroke: CGColor, width: Double, dash: [Double]?, hand: MapStyle.HandDrawn) {
        rings = ([polygon] + (polygon.interiorPolygons ?? [])).map(Self.mapPoints)
        isClosed = true
        self.fill = fill
        self.stroke = stroke
        self.width = width
        self.dash = dash
        self.hand = hand
        super.init(overlay: polygon)
    }

    /// A line.
    init(line: MKPolyline, stroke: CGColor, width: Double, dash: [Double]?, hand: MapStyle.HandDrawn) {
        rings = [Self.mapPoints(of: line)]
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
        }
        guard width > 0 else { return }

        context.setStrokeColor(stroke)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        let spacing = 3 * screen
        let reach = (width + hand.amplitude * 2 + 4) * screen
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
                    stroke(run, zoomScale: zoomScale, in: context)
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
            stroke(run, zoomScale: zoomScale, in: context)
        }
    }

    /// A stretch of line, in pieces of different thickness, or all at once if it is dashed (a dash can't be thicker in one place).
    private func stroke(_ run: [Sample], zoomScale: MKZoomScale, in context: CGContext) {
        guard run.count >= 2 else { return }
        let screen = 1 / Double(zoomScale)
        if let dash {
            context.setLineWidth(width * screen)
            context.setLineDash(phase: CGFloat(run[0].along), lengths: dash.map { CGFloat($0 * screen) })
            context.beginPath()
            context.move(to: run[0].point)
            for sample in run.dropFirst() { context.addLine(to: sample.point) }
            context.strokePath()
            context.setLineDash(phase: 0, lengths: [])
            return
        }
        for i in 1..<run.count {
            context.setLineWidth(width * screen * (run[i].weight + run[i - 1].weight) / 2)
            context.move(to: run[i - 1].point)
            context.addLine(to: run[i].point)
            context.strokePath()
        }
    }
}

// MARK: Preview

import SwiftUI

/// The ink look on a few shapes, drawn straight into a picture (a preview can't show MapKit itself), at two sizes of the same shapes.
@MainActor
private func inkSample(zoomScale: Double) -> Image {
    let size = CGSize(width: 520, height: 330)
    let context = CGContext(
        data: nil, width: Int(size.width * 2), height: Int(size.height * 2), bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    context.scaleBy(x: 2, y: -2)
    context.translateBy(x: 0, y: -size.height)
    context.setFillColor(CGColor(red: 0.93, green: 0.87, blue: 0.73, alpha: 1))
    context.fill(CGRect(origin: .zero, size: size))
    let hand = MapStyle.parchment.hand ?? MapStyle.HandDrawn(amplitude: 1, wavelength: 16, weight: 0.3)
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
    func draw(_ renderer: InkRenderer) {
        let corner = renderer.overlay.boundingMapRect.origin
        context.saveGState()
        context.translateBy(x: corner.x - origin.x, y: corner.y - origin.y)
        renderer.draw(rect, zoomScale: MKZoomScale(zoomScale), in: context)
        context.restoreGState()
    }
    let land = polygon([(40, 60), (200, 30), (330, 70), (360, 150), (300, 250), (180, 290), (70, 240), (30, 140)])
    let seaWithHole = polygon([(0, 0), (520, 0), (520, 330), (0, 330)], holes: [land])
    let ink = CGColor(red: 0.3, green: 0.18, blue: 0.08, alpha: 1)
    draw(InkRenderer(polygon: seaWithHole, fill: CGColor(red: 0.55, green: 0.68, blue: 0.72, alpha: 0.6), stroke: CGColor(red: 0.35, green: 0.45, blue: 0.5, alpha: 1), width: 1.5, dash: nil, hand: hand))
    draw(InkRenderer(line: line([(120, 80), (150, 140), (130, 190), (190, 240), (170, 310)]), stroke: CGColor(red: 0.35, green: 0.5, blue: 0.6, alpha: 1), width: 3, dash: nil, hand: hand))
    draw(InkRenderer(line: line([(60, 200), (160, 170), (250, 190), (340, 130), (480, 150)]), stroke: CGColor(red: 0.4, green: 0.26, blue: 0.12, alpha: 1), width: 1.8, dash: nil, hand: hand))
    draw(InkRenderer(line: line([(200, 40), (210, 120), (250, 190), (240, 270)]), stroke: CGColor(red: 0.55, green: 0.2, blue: 0.12, alpha: 1), width: 1.6, dash: [9, 3, 1.5, 3], hand: hand))
    _ = ink
    return Image(decorative: context.makeImage()!, scale: 2)
}

#Preview("Ink, small") { inkSample(zoomScale: 1) }
#Preview("Ink, zoomed") { inkSample(zoomScale: 4) }
