//
//  GenericRestSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Takes a rest that offers moves: choose the moves, then see what they gave back.
struct GenericRestSheet: View {
    let page: Page
    let rest: RestDefinition

    @Environment(\.dismiss) private var dismiss
    @State private var counts: [String: Int] = [:]
    @State private var lines: [String]?

    private var system: any RuleSystem { RuleSystems.system(forKey: page.world?.systemRaw ?? "") }
    private var chosen: Int { counts.values.reduce(0, +) }
    private var picks: [String] { rest.moves.flatMap { move in Array(repeating: move.id, count: counts[move.id] ?? 0) } }

    var body: some View {
        NavigationStack {
            Form {
                if let lines {
                    ThemedSection("What the rest gave back") {
                        if lines.isEmpty { Text("Nothing needed restoring.") }
                        ForEach(lines, id: \.self) { Text($0) }
                    }
                } else {
                    Section {
                        ForEach(rest.moves) { move in
                            Stepper(value: Binding(get: { counts[move.id] ?? 0 }, set: { counts[move.id] = $0 }), in: 0...((counts[move.id] ?? 0) + max(0, rest.movesToChoose - chosen))) {
                                HStack { Text(move.title); Spacer(); Text("\(counts[move.id] ?? 0)").foregroundStyle(.secondary).monospacedDigit() }
                            }
                        }
                    } header: {
                        Text("Choose \(rest.movesToChoose) moves")
                    } footer: {
                        Text("You can choose the same move more than once. \(rest.movesToChoose - chosen) left to choose.")
                    }
                }
            }
            .formStyle(.grouped)
            .themedScreen()
            .themedRow()
            .themedNavigationTitle(rest.name)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { if lines == nil { Button("Cancel") { dismiss() } } }
                ToolbarItem(placement: .confirmationAction) {
                    if lines == nil {
                        Button("Take Rest") { lines = RestEngine.take(rest, moves: picks, on: page, system: system, dice: GenericSheetView.rollDice) }
                            .disabled(chosen != rest.movesToChoose)
                    } else {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 380)
        #endif
    }
}

#Preview("Daggerheart short rest") {
    let data = GenericPreviewData.make()
    let rest = RuleSystems.system(forKey: "daggerheart").rests.first
    return Group { if let data, let rest { GenericRestSheet(page: data.character, rest: rest).modelContainer(data.container) } }
}
