//
//  SheetDecorations.swift
//  encounter
//

import SwiftUI

/// What the map view says about itself that the decorations on the sheet need: how many metres a point on screen is, and which way
/// the map is turned.
struct MapViewReading: Equatable {
    var metresPerPoint: Double
    /// Degrees clockwise that the map is turned from north being up.
    var heading: Double
}

/// A compass rose and a scale bar over the corners of a vector map, in the style's ink, like the ones drawn on an old map's margin.
struct SheetDecorations: View {
    let style: MapStyle
    let unit: DistanceUnit
    let reading: MapViewReading

    private var ink: Color { Color(red: style.ink.red, green: style.ink.green, blue: style.ink.blue) }

    private func font(_ size: Double, italic: Bool = false) -> Font {
        if let lettering = style.lettering { return .custom(italic ? lettering.italic : lettering.regular, size: size) }
        return .system(size: size, design: .serif)
    }

    var body: some View {
        ZStack {
            VStack {
                HStack {
                    Spacer()
                    CompassRose(heading: reading.heading, ink: ink, font: font(13, italic: true))
                        .frame(width: 92, height: 92)
                        .padding(.trailing, 28)
                        .padding(.top, 30)
                }
                Spacer()
            }
            VStack {
                Spacer()
                HStack {
                    ScaleBar(metresPerPoint: reading.metresPerPoint, unit: unit, ink: ink, font: font(11))
                        .padding(.leading, 28)
                        .padding(.bottom, 40)
                    Spacer()
                }
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// An eight-pointed rose, with north marked and turned to point the way north is on the map.
struct CompassRose: View {
    let heading: Double
    let ink: Color
    let font: Font

    var body: some View {
        Canvas { context, size in
            let middle = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 15
            context.translateBy(x: middle.x, y: middle.y)
            context.rotate(by: .degrees(-heading))
            context.stroke(Path(ellipseIn: CGRect(x: -radius * 0.5, y: -radius * 0.5, width: radius, height: radius)), with: .color(ink), lineWidth: 0.7)
            // The four long points and the four short ones. Each is a thin diamond with one half filled, so it looks lit from one side;
            // only the long ones are filled, so the rose isn't a black blot.
            for (index, angle) in stride(from: 0.0, to: 360.0, by: 45.0).enumerated() {
                let long = index % 2 == 0
                let length = long ? radius : radius * 0.62
                let half = long ? radius * 0.13 : radius * 0.08
                var point = context
                point.rotate(by: .degrees(angle))
                var left = Path()
                left.move(to: CGPoint(x: 0, y: 0))
                left.addLine(to: CGPoint(x: -half, y: -radius * 0.22))
                left.addLine(to: CGPoint(x: 0, y: -length))
                left.closeSubpath()
                var right = Path()
                right.move(to: CGPoint(x: 0, y: 0))
                right.addLine(to: CGPoint(x: half, y: -radius * 0.22))
                right.addLine(to: CGPoint(x: 0, y: -length))
                right.closeSubpath()
                if long { point.fill(right, with: .color(ink)) }
                point.stroke(left, with: .color(ink), lineWidth: 0.7)
                point.stroke(right, with: .color(ink), lineWidth: 0.7)
            }
            // North is named at the tip of its point, and turns with the rose.
            context.draw(Text("N").font(font).foregroundStyle(ink), at: CGPoint(x: 0, y: -radius - 9))
        }
    }
}

/// A bar marked off in four, with a round length to its end, which changes as the map is zoomed.
struct ScaleBar: View {
    let metresPerPoint: Double
    let unit: DistanceUnit
    let ink: Color
    let font: Font

    /// The longest of 1, 2 and 5 times a power of ten that fits in about 130 points.
    static func length(metresPerPoint: Double, unit: DistanceUnit, longest: Double = 130) -> (value: Double, points: Double)? {
        guard metresPerPoint > 0, metresPerPoint.isFinite else { return nil }
        let perPoint = metresPerPoint / unit.metres
        let limit = longest * perPoint
        guard limit > 0, limit.isFinite else { return nil }
        let power = pow(10, floor(log10(limit)))
        let value = [5.0, 2.0, 1.0].map { $0 * power }.first { $0 <= limit } ?? power
        return (value, value / perPoint)
    }

    private func label(_ value: Double) -> String {
        let number = value >= 1 || value == 0 ? String(Int(value.rounded())) : String(format: "%g", value)
        return "\(number) \(unit.symbol)"
    }

    var body: some View {
        if let bar = Self.length(metresPerPoint: metresPerPoint, unit: unit) {
            VStack(alignment: .leading, spacing: 3) {
                ZStack(alignment: .leading) {
                    ForEach(0..<4, id: \.self) { index in
                        Rectangle()
                            .fill(index % 2 == 0 ? ink : Color.clear)
                            .frame(width: bar.points / 4, height: 4)
                            .offset(x: bar.points / 4 * Double(index))
                    }
                    Rectangle().stroke(ink, lineWidth: 0.8).frame(width: bar.points, height: 4)
                }
                .frame(width: bar.points, height: 4, alignment: .leading)
                HStack {
                    Text("0")
                    Spacer()
                    Text(label(bar.value))
                }
                .font(font)
                .foregroundStyle(ink)
                .frame(width: bar.points)
            }
        }
    }
}

#Preview("Compass and scale") {
    ZStack {
        Color(red: 0.93, green: 0.87, blue: 0.73)
        SheetDecorations(style: .parchment, unit: .miles, reading: MapViewReading(metresPerPoint: 600, heading: 0))
    }
    .frame(width: 420, height: 300)
}

#Preview("Turned") {
    ZStack {
        Color(red: 0.93, green: 0.87, blue: 0.73)
        SheetDecorations(style: .parchment, unit: .miles, reading: MapViewReading(metresPerPoint: 12, heading: 40))
    }
    .frame(width: 420, height: 300)
}
