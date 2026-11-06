//
//  ConditionsView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// The conditions the character is under, as chips to tap for the rules, with a menu to add more.
struct ConditionsBox: View {
    let page: Page

    @State private var inspecting: Condition?

    var body: some View {
        if let sheet = CharacterSheet(page: page) {
            let state = sheet.conditionState
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Conditions").font(.headline)
                    Spacer()
                    Menu("Add", systemImage: "plus.circle") {
                        ForEach(Condition.allCases.filter { !state.all.contains($0) }) { condition in
                            Button(condition.title) { sheet.addCondition(condition) }
                        }
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(state.all.count == Condition.allCases.count)
                }
                if state.isEmpty {
                    Text("None. Add one to see what it does to your rolls.").font(.callout).foregroundStyle(.secondary)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(Condition.allCases.filter { state.all.contains($0) }) { condition in
                            Button { inspecting = condition } label: {
                                Text(condition == .exhaustion ? "Exhaustion \(state.exhaustion)" : condition.title)
                                    .font(.callout.weight(.medium))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .background(.orange.opacity(0.2), in: Capsule())
                                    .contentShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    ForEach(sheet.incapacitatingConditions.isEmpty ? [] : [sheet.incapacitatingConditions.map(\.title).joined(separator: ", ")], id: \.self) { names in
                        Label("\(names): can't take actions or reactions.", systemImage: "hand.raised.slash").font(.callout).foregroundStyle(.orange)
                    }
                    ForEach(sheet.againstYou, id: \.self) { line in
                        Label(line, systemImage: "scope").font(.caption).foregroundStyle(.secondary)
                    }
                    if sheet.effectiveMaximumHitPoints != sheet.maximumHitPoints {
                        Label("Hit point maximum is \(sheet.effectiveMaximumHitPoints) while exhausted.", systemImage: "heart.slash").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .themedSheetPanel()
            .sheet(item: $inspecting) { condition in
                ConditionInfoView(page: page, condition: condition) { inspecting = nil }
            }
        }
    }
}

/// A condition's rules text from the library, with exhaustion's level and a button to take the condition off.
struct ConditionInfoView: View {
    let page: Page
    let condition: Condition
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            if let sheet = CharacterSheet(page: page) {
                Form {
                    if condition == .exhaustion {
                        ThemedSection("Level") {
                            Stepper("Exhaustion level \(sheet.conditionState.exhaustion)", value: Binding(
                                get: { sheet.conditionState.exhaustion },
                                set: { sheet.setExhaustion($0) }
                            ), in: 0...6)
                            if sheet.conditionState.exhaustion >= 6 {
                                Label("Level 6 is death.", systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                            }
                        }
                    }
                    ThemedSection("What It Does") {
                        Text(sheet.rulesText(of: condition) ?? String(localized: "The rules text for this condition isn't in this edition's library."))
                            .font(.callout)
                    }
                    Section {
                        Button("Remove \(condition.title)", role: .destructive) {
                            sheet.removeCondition(condition)
                            onClose()
                        }
                    }
                }
                .formStyle(.grouped)
                .themedScreen()
                .themedRow()
                .navigationTitle(condition.title)
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done", action: onClose) } }
            }
        }
        #if os(macOS)
        .frame(minWidth: 440, minHeight: 420)
        #endif
    }
}
