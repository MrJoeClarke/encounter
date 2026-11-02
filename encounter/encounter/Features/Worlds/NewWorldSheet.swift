//
//  NewWorldSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

/// Creates a new world. An existing world is edited on its home page.
struct NewWorldSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var summary = ""
    @State private var systemKey = RuleSystemID.none.rawValue

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Rule System", selection: $systemKey) {
                        ForEach(RuleSystems.choices) { system in
                            Text(system.title).tag(system.key)
                        }
                    }
                } footer: {
                    Text("The rule system adds attributes to your pages. You can change it later without losing data.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("New World")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func create() {
        let world = World(name: trimmedName, summary: summary)
        world.choose(systemKey: systemKey)
        modelContext.insert(world)
        // Every world has a place at the top of its hierarchy, named after it, whose map is the world map.
        world.ensureRootPlace(in: modelContext)
        dismiss()
    }
}

#Preview {
    NewWorldSheet()
        .modelContainer(SampleData.makePreviewContainer(populated: false))
}
