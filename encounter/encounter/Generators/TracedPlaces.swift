//
//  TracedPlaces.swift
//  encounter
//

import Foundation
import SwiftData

extension Page {
    /// Whether this place was made by tracing a picture, rather than by a generator.
    var wasTraced: Bool { attributeText("gen.traced") == "1" }
}

extension World {
    /// Makes a place for each area of a trace that has a type, on the world the picture is of. Traced again, it replaces the places the
    /// last trace made, except any that have been edited, linked or written about.
    @MainActor
    @discardableResult
    func addTracedPlaces(from colours: [TracedColour], for map: WorldMap, in context: ModelContext) -> GeneratedMapSummary {
        var summary = GeneratedMapSummary(map: map)
        for page in pages ?? [] where page.wasTraced && page.wasGenerated(by: map) && !page.isDeleted {
            if page.isUneditedGeneration {
                context.delete(page)
                summary.replaced += 1
            } else {
                summary.kept += 1
            }
        }
        let parent = map.place ?? rootPlace
        for colour in colours {
            guard let placeType = colour.type.placeType, let first = colour.outlines.first else { continue }
            let page = addPage(kind: .place, in: context)
            page.title = colour.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? colour.type.title : colour.name
            page.attributes["core.placeType"] = .text(placeType)
            page.geometry = colour.outlines.count == 1 ? .polygon(first) : .multiPolygon(colour.outlines)
            page.parent = parent
            page.parentSource = .manual
            page.markGenerated(by: map)
            page.attributes["gen.traced"] = .text("1")
            page.updateSearchText()
            summary.created += 1
        }
        return summary
    }
}
