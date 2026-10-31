//
//  AttributeFieldView.swift
//  encounter
//

import SwiftUI

/// Edits one attribute of a page, choosing the control from the attribute's definition.
struct AttributeFieldView: View {
    let definition: AttributeDefinition
    @Bindable var page: Page

    var body: some View {
        switch definition.type {
        case .text:
            TextField(text: textBinding) {
                Text(definition.label)
            }
        case .number:
            TextField(value: numberBinding, format: .number) {
                Text(definition.label)
            }
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
        case .bool:
            Toggle(isOn: boolBinding) {
                Text(definition.label)
            }
        case .abilityScore:
            LabeledContent {
                HStack {
                    TextField(value: abilityScoreBinding, format: .number) {
                        Text(definition.label)
                    }
                    .labelsHidden()
                    .multilineTextAlignment(.trailing)
                    #if os(iOS)
                    .keyboardType(.numberPad)
                    #endif
                    if let score = page.attributeNumber(definition.key) {
                        Text(DnD5eSystem.abilityModifierText(for: Int(score)))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .frame(minWidth: 36, alignment: .trailing)
                            .accessibilityLabel("Modifier \(DnD5eSystem.abilityModifierText(for: Int(score)))")
                    }
                }
            } label: {
                Text(definition.label)
            }
        case .contentReference(let kind, let role):
            ContentReferenceField(label: definition.label, kind: kind, role: role, page: page)
        case .subclassReference(let role, let classRole):
            SubclassField(label: definition.label, role: role, classRole: classRole, page: page)
        case .entries(let showsLevel):
            EntriesField(definition: definition, page: page, showsLevel: showsLevel)
        case .choice(let options):
            let current = page.attributeText(definition.key)
            Picker(selection: textBinding) {
                Text("None").tag("")
                // Keep a value that isn't in the list (typed before this field became a picker, say) selectable.
                if !current.isEmpty && !options.contains(current) {
                    Text(current).tag(current)
                }
                ForEach(options, id: \.self) { option in
                    Text(option).tag(option)
                }
            } label: {
                Text(definition.label)
            }
        }
    }

    private var textBinding: Binding<String> {
        Binding(
            get: { page.attributeText(definition.key) },
            set: { page.setAttributeText(definition.key, $0) }
        )
    }

    private var numberBinding: Binding<Double?> {
        Binding(
            get: { page.attributeNumber(definition.key) },
            set: { page.setAttributeNumber(definition.key, $0) }
        )
    }

    private var boolBinding: Binding<Bool> {
        Binding(
            get: { page.attributeBool(definition.key) },
            set: { page.setAttributeBool(definition.key, $0) }
        )
    }

    /// Whole numbers only, kept within the ability score range.
    private var abilityScoreBinding: Binding<Double?> {
        Binding(
            get: { page.attributeNumber(definition.key) },
            set: { newValue in
                let range = DnD5eSystem.abilityScoreRange
                let score = newValue.map { min(max(Int($0.rounded()), range.lowerBound), range.upperBound) }
                page.setAttributeNumber(definition.key, score.map(Double.init))
            }
        )
    }
}
