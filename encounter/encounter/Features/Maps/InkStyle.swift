//
//  InkStyle.swift
//  encounter
//

import MapKit

extension InkRenderer {
    private static func colour(_ c: StyleColor) -> CGColor { PlatformColor(style: c).cgColor }

    /// The renderer for an area of a type in a style, or nil if the style doesn't draw that type by hand.
    static func make(polygon: MKPolygon, type: String, style mapStyle: MapStyle, highlighted: Bool = false) -> InkRenderer? {
        // A highlighted place is drawn this way in every style, with a straight pen where the style has none.
        guard let hand = hand(for: type, in: mapStyle, highlighted: highlighted) else { return nil }
        let look = mapStyle.style(forPlaceType: type)
        var decoration: InkDecoration?
        if let symbols = mapStyle.symbols {
            switch type {
            case "Forest": decoration = .trees(ink: colour(symbols.tree), wash: colour(symbols.treeWash), regular: symbols.regular, soft: symbols.soft)
            case "Mountains": decoration = .peaks(ink: colour(symbols.peak), ground: colour(mapStyle.background), contours: symbols.contours, soft: symbols.soft)
            case "Water": decoration = symbols.shore.map { .shore(ink: colour($0), inside: false, soft: symbols.soft) }
            case "Lake": decoration = symbols.shore.map { .shore(ink: colour($0), inside: true, soft: symbols.soft) }
            default: break
            }
        }
        return InkRenderer(
            polygon: polygon, fill: look.fill.map(colour), stroke: colour(look.stroke), width: look.lineWidth,
            dash: look.isDashed ? (look.dashPattern ?? [6, 4]) : nil, hand: hand, decoration: decoration,
            wash: type == "Building" ? nil : mapStyle.wash, highlight: highlighted ? colour(mapStyle.accent) : nil
        )
    }

    /// The renderer for a line of a type in a style, or nil if the style doesn't draw that type by hand.
    static func make(line: MKPolyline, type: String, style mapStyle: MapStyle, highlighted: Bool = false) -> InkRenderer? {
        guard let hand = hand(for: type, in: mapStyle, highlighted: highlighted) else { return nil }
        let look = mapStyle.style(forPlaceType: type)
        return InkRenderer(line: line, stroke: colour(look.stroke), width: look.lineWidth, dash: look.isDashed ? (look.dashPattern ?? [6, 4]) : nil, hand: hand, highlight: highlighted ? colour(mapStyle.accent) : nil)
    }

    private static func hand(for type: String, in style: MapStyle, highlighted: Bool) -> MapStyle.HandDrawn? {
        if highlighted { return style.hand ?? MapStyle.HandDrawn(amplitude: 0, wavelength: 16, weight: 0) }
        guard let hand = style.hand, MapStyle.HandDrawn.types.contains(type) else { return nil }
        return hand
    }
}
