//
//  EntriesField.swift
//  encounter
//

import SwiftUI

/// Edits a list of named entries on a page, such as a race's traits or a class's features.
struct EntriesField: View {
    let definition: AttributeDefinition
    @Bindable var page: Page
    let showsLevel: Bool

    private var entries: [EntryValue] {
        if case .entries(let entries) = page.attributes[definition.key] { entries } else { [] }
    }

    /// An empty list removes the attribute rather than storing it.
    private func setEntries(_ entries: [EntryValue]) {
        page.attributes[definition.key] = entries.isEmpty ? nil : .entries(entries)
    }

    var body: some View {
        let current = entries
        ForEach(current.indices, id: \.self) { index in
            EntryRow(entry: binding(at: index), showsLevel: showsLevel) {
                var remaining = entries
                if remaining.indices.contains(index) {
                    remaining.remove(at: index)
                    setEntries(remaining)
                }
            }
        }
        Button(addTitle, systemImage: "plus") {
            setEntries(current + [EntryValue()])
        }
    }

    /// "Add Feature" and "Add Trait" for a class and a race, and otherwise the name of the list, such as "Add to Experiences".
    private var addTitle: LocalizedStringResource {
        switch definition.key {
        case CoreAttributes.featuresKey: "Add Feature"
        case CoreAttributes.traitsKey: "Add Trait"
        default: "Add to \(definition.label)"
        }
    }

    private func binding(at index: Int) -> Binding<EntryValue> {
        Binding(
            get: {
                let all = entries
                return all.indices.contains(index) ? all[index] : EntryValue()
            },
            set: { newValue in
                var all = entries
                guard all.indices.contains(index) else { return }
                all[index] = newValue
                setEntries(all)
            }
        )
    }
}

private struct EntryRow: View {
    @Binding var entry: EntryValue
    let showsLevel: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("Name", text: $entry.name)
                    .font(.headline)
                if showsLevel {
                    TextField("Level", value: $entry.level, format: .number)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 64)
                        #if os(iOS)
                        .keyboardType(.numberPad)
                        #endif
                }
                Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
            }
            TextField("Description", text: $entry.text, axis: .vertical)
                .lineLimit(2...30)
        }
        .padding(.vertical, 2)
    }
}
