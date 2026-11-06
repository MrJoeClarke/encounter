//
//  MapLettering.swift
//  encounter
//

import Foundation
import CoreGraphics
import Vision

/// A name written on a picture of a map, as read from it: one name, which may be on two lines, and where it is.
nonisolated struct MapLabel: Equatable, Sendable {
    /// The name itself, as it is to be used for a place.
    var name: String
    /// What follows it on a second line, such as "The Bare Mountains", if anything.
    var description: String
    /// The middle of the lettering in the picture's pixels, from the top left.
    var x: Double
    var y: Double
    /// How tall a line of its lettering is, in pixels.
    var height: Double
    /// The type of area its words say it is (Mountains, Forest, Sea), if they say.
    var type: TracedType?
    /// Whether it was written in capitals, as a map writes the names of realms.
    var isCapitals = false
    /// How wide its widest line of lettering is, in pixels.
    var width = 0.0

    /// How much of the picture its lettering covers, roughly, for telling which of two names is the main one.
    var size: Double { height * max(width, height) }
}

/// Reads the names written on a picture of a map. The reading is done on the device by text recognition.
nonisolated enum MapLettering {
    /// One line of lettering as it was read, in the picture's pixels from the top left.
    struct Line: Equatable, Sendable {
        var text: String
        var x: Double
        var y: Double
        var width: Double
        var height: Double
    }

    /// The lines of lettering text recognition finds in a picture.
    static func read(_ image: CGImage) -> [Line] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Names in a made-up world are not words, so correcting them would spoil them.
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.004
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        guard (try? handler.perform([request])) != nil else { return [] }
        let width = Double(image.width), height = Double(image.height)
        return (request.results ?? []).compactMap { observation in
            guard let best = observation.topCandidates(1).first, best.confidence >= 0.3 else { return nil }
            let box = observation.boundingBox
            return Line(
                text: best.string, x: (box.midX) * width, y: (1 - box.midY) * height, width: box.width * width, height: box.height * height
            )
        }
    }

    /// Words that say what sort of area a name is of.
    private static let words: [String: TracedType] = [
        "sea": .water, "ocean": .water, "bay": .water, "gulf": .water, "strait": .water, "straits": .water, "lake": .water, "sound": .water,
        "forest": .forest, "wood": .forest, "woods": .forest, "woodland": .forest, "jungle": .forest, "grove": .forest, "weald": .forest,
        "mountains": .mountains, "mountain": .mountains, "mount": .mountains, "peaks": .mountains, "range": .mountains, "hills": .mountains, "highlands": .mountains,
        "marsh": .wilderness, "marshes": .wilderness, "swamp": .wilderness, "fen": .wilderness, "moor": .wilderness, "moors": .wilderness,
        "wilderness": .wilderness, "waste": .wilderness, "wastes": .wilderness, "desert": .wilderness, "dunes": .wilderness, "gorge": .wilderness,
        "canyon": .wilderness, "valley": .wilderness, "steppe": .wilderness, "tundra": .wilderness,
    ]

    /// The type of area that words say, if they say one. The words of the name itself count, and so do those of its second line.
    static func type(of text: String) -> TracedType? {
        let found = text.lowercased().split { !$0.isLetter }.compactMap { words[String($0)] }
        return found.first
    }

    /// A name as it is to be kept: no stray marks round it, and words in capitals (which maps use for realms) in capitals only at their start.
    static func tidy(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters.subtracting(CharacterSet(charactersIn: "'’"))))
        let letters = trimmed.filter(\.isLetter)
        guard letters.count > 1, letters == letters.uppercased() else { return trimmed }
        return trimmed.split(separator: " ").map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }.joined(separator: " ")
    }

    /// Words that are small words of a name, not the end of a word that was read in two.
    private static let connectors: Set<String> = ["of", "the", "de", "del", "la", "le", "von", "van", "and", "on", "upon", "in", "at", "by", "du", "der", "den", "al", "el"]

    /// Letter-spaced lettering is often read in pieces, "Moel fan" for Moelfan. A lowercase piece after a word is put back on the word,
    /// unless it is a small word of a name.
    static func mended(_ text: String) -> String {
        var words: [String] = []
        for word in text.split(separator: " ").map(String.init) {
            if let first = word.first, first.isLowercase, !connectors.contains(word), !words.isEmpty, words.last?.first?.isLetter == true {
                words[words.count - 1] += word
            } else {
                words.append(word)
            }
        }
        return words.joined(separator: " ")
    }

    /// Joins lines of lettering that are one name written on two or three lines, and turns them into names. A second line that begins
    /// with "The" is what the first one means, and goes in the description; otherwise the lines are one name.
    static func labels(from lines: [Line]) -> [MapLabel] {
        // Only lettering that is mostly letters: marks and speckles of the paper are read as lettering too.
        let usable = lines.filter { line in
            let letters = line.text.filter(\.isLetter).count
            return letters >= 3 && Double(letters) >= 0.6 * Double(line.text.filter { !$0.isWhitespace }.count)
        }.sorted { $0.y < $1.y }
        var groups: [[Line]] = []
        for line in usable {
            if let index = groups.firstIndex(where: { group in
                guard let last = group.last, group.count < 3 else { return false }
                let gap = (line.y - line.height / 2) - (last.y + last.height / 2)
                let similar = max(line.height, last.height) / max(min(line.height, last.height), 1) < 1.7
                return gap < 0.9 * max(line.height, last.height) && abs(line.x - last.x) < 0.5 * max(line.width, last.width) && similar
            }) {
                groups[index].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.map { group in
            let texts = group.map(\.text)
            var name = texts[0], description = ""
            if texts.count > 1 {
                if texts[1].lowercased().hasPrefix("the ") && !texts[0].lowercased().hasPrefix("the ") {
                    description = texts.dropFirst().joined(separator: " ")
                } else {
                    name = texts.joined(separator: " ")
                }
            }
            let capitals = name.filter(\.isLetter).count >= 4 && name.filter(\.isLetter) == name.filter(\.isLetter).uppercased()
            name = mended(name)
            let x = group.map(\.x).reduce(0, +) / Double(group.count), y = group.map(\.y).reduce(0, +) / Double(group.count)
            return MapLabel(
                name: tidy(name), description: description, x: x, y: y, height: group.map(\.height).max() ?? 0,
                type: type(of: ([name, description].filter { !$0.isEmpty }).joined(separator: " ")), isCapitals: capitals, width: group.map(\.width).max() ?? 0
            )
        }
    }
}
