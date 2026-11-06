//
//  MapTypeGuesser.swift
//  encounter
//

import Foundation
import FoundationModels

/// What the on-device model says an area of a picture is.
@Generable
enum GuessedAreaType: String, CaseIterable {
    case realm
    case water
    case forest
    case mountains
    case wilderness
    case leaveOut

    var traced: TracedType {
        switch self {
        case .realm: .region
        case .water: .water
        case .forest: .forest
        case .mountains: .mountains
        case .wilderness: .wilderness
        case .leaveOut: .ignore
        }
    }
}

/// Asks the on-device model what each coloured area of a picture of a map is, from its colour, its size, and the names written on it.
/// Optional: where there is no model the colour rules and the names are all there is.
enum MapTypeGuesser {
    /// Whether the model's guess is used in the sheet. It is kept only if it makes the guesses better than the rules do; see
    /// `MapTypeGuesserTests`, which compares them on the sample picture.
    static let isUsed = false

    /// A few words for a colour, for the model, which cannot see it: "pale green", "dark brown".
    nonisolated static func describe(red: Double, green: Double, blue: Double) -> String {
        let lab = Lab.lab(red: red, green: green, blue: blue)
        let chroma = (lab.a * lab.a + lab.b * lab.b).squareRoot()
        let lightness = lab.l > 75 ? "pale " : (lab.l < 40 ? "dark " : "")
        if chroma < 8 { return lab.l > 80 ? "white" : (lab.l < 25 ? "black" : lightness + "grey") }
        var hue = atan2(lab.b, lab.a) * 180 / .pi
        if hue < 0 { hue += 360 }
        let name: String
        switch hue {
        case 20..<45: name = lab.l > 60 ? "pink" : "reddish brown"
        case 45..<75: name = lab.l > 60 ? "tan" : "brown"
        case 75..<105: name = "yellow or olive"
        case 105..<170: name = "green"
        case 170..<260: name = "blue"
        case 260..<330: name = "purple"
        default: name = "red"
        }
        return lightness + name
    }

    /// What the model says each colour with areas is, by colour `id`. Nil if there is no model. A colour it declines or fails on has no entry.
    static func guess(for colours: [TracedColour]) async -> [Int: TracedType]? {
        guard RootLanguageDrafter.availability == .available else { return nil }
        var result: [Int: TracedType] = [:]
        for colour in colours where !colour.outlines.isEmpty {
            let names = colour.named.sorted { $0.key < $1.key }.map { $0.value.summary.isEmpty ? $0.value.name : "\($0.value.name) (\($0.value.summary))" }
            let session = LanguageModelSession(instructions: """
                You help a game master turn a picture of a fantasy map into places. You are told one colour of the picture, how much of it \
                that colour covers, and any names written on it. Say what the coloured areas are: a realm (land that a kingdom or people \
                holds), water, a forest, mountains, wilderness (desert, marsh, wasteland, moor), or leave them out (the black surround, \
                lettering, anything that is not part of the map). On most maps the sea is blue, forests are dark green, mountains are \
                grey or brown, and the realms are the pale colours in between.
                """)
            let prompt = """
                The colour is \(describe(red: colour.red, green: colour.green, blue: colour.blue)). It covers \(Int((colour.share * 100).rounded())) \
                per cent of the picture, in \(colour.outlines.count) separate piece\(colour.outlines.count == 1 ? "" : "s"). \
                \(names.isEmpty ? "No names are written on it." : "Names written on it: \(names.joined(separator: "; ")).")
                """
            if let response = try? await session.respond(to: prompt, generating: GuessedAreaType.self) {
                result[colour.id] = response.content.traced
            }
        }
        return result
    }
}
