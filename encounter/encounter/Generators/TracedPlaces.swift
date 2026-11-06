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
        for colour in colours where colour.type != .ignore {
            // Pieces with a name from the lettering make a place each (one for each different name); the others make one with the colour's
            // name, or if the colour has just one name, are more of that place, as an island is of its realm.
            var groups: [(name: String, summary: String, type: TracedType, pieces: [[GridPoint]])] = []
            var unnamed: [[GridPoint]] = []
            for (i, outline) in colour.outlines.enumerated() {
                guard let named = colour.named[i], !named.name.isEmpty else { unnamed.append(outline); continue }
                let type = named.type ?? colour.type
                if let at = groups.firstIndex(where: { $0.name == named.name && $0.type == type }) {
                    groups[at].pieces.append(outline)
                } else {
                    groups.append((named.name, named.summary, type, [outline]))
                }
            }
            if groups.count == 1 {
                groups[0].pieces.append(contentsOf: unnamed)
            } else if !unnamed.isEmpty {
                let name = colour.name.trimmingCharacters(in: .whitespacesAndNewlines)
                groups.append((name.isEmpty ? colour.type.title : name, "", colour.type, unnamed))
            }
            for group in groups {
                guard let placeType = group.type.placeType, let first = group.pieces.first else { continue }
                let page = addPage(kind: .place, in: context)
                page.title = group.name
                page.summary = group.summary
                page.attributes["core.placeType"] = .text(placeType)
                page.geometry = group.pieces.count == 1 ? .polygon(first) : .multiPolygon(group.pieces)
                page.parent = parent
                page.parentSource = .manual
                page.markGenerated(by: map)
                page.attributes["gen.traced"] = .text("1")
                page.updateSearchText()
                summary.created += 1
            }
        }
        return summary
    }
}
