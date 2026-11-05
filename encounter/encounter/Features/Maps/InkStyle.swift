//
//  InkStyle.swift
//  encounter
//

import MapKit

extension InkRenderer {
    private static func colour(_ c: StyleColor) -> CGColor { PlatformColor(style: c).cgColor }

    /// The renderer for an area of a type in a style, or nil if the style doesn't draw that type by hand.
    static func make(polygon: MKPolygon, type: String, style mapStyle: MapStyle) -> InkRenderer? {
        guard let hand = mapStyle.hand, MapStyle.HandDrawn.types.contains(type) else { return nil }
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
            wash: type == "Building" ? nil : mapStyle.wash
        )
    }

    /// The renderer for a line of a type in a style, or nil if the style doesn't draw that type by hand.
    static func make(line: MKPolyline, type: String, style mapStyle: MapStyle) -> InkRenderer? {
        guard let hand = mapStyle.hand, MapStyle.HandDrawn.types.contains(type) else { return nil }
        let look = mapStyle.style(forPlaceType: type)
        return InkRenderer(line: line, stroke: colour(look.stroke), width: look.lineWidth, dash: look.isDashed ? (look.dashPattern ?? [6, 4]) : nil, hand: hand)
    }
}
