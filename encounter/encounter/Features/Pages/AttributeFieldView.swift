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
        case .pageReference(let kind, let role):
            PageReferenceField(label: definition.label, kind: kind, role: role, page: page)
        case .choice(let options):
            Picker(selection: textBinding) {
                Text("None").tag("")
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
}
