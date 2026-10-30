//
//  WorldEditorSheet.swift
//  encounter
//

import SwiftUI
import SwiftData

enum WorldEditorMode: Identifiable {
    case create
    case edit(World)

    var id: String {
        switch self {
        case .create: "create"
        case .edit(let world): world.id.uuidString
        }
    }
}

/// Creates a new world or edits an existing one.
struct WorldEditorSheet: View {
    let mode: WorldEditorMode

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var summary = ""
    @State private var system = RuleSystemID.none

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Summary", text: $summary, axis: .vertical)
                        .lineLimit(2...5)
                }
                Section {
                    Picker("Rule System", selection: $system) {
                        ForEach(RuleSystemID.allCases) { system in
                            Text(system.title).tag(system)
                        }
                    }
                } footer: {
                    Text("The rule system adds attributes to your pages. You can change it later without losing data.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle(isEditing ? "Edit World" : "New World")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditing ? "Save" : "Create", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .onAppear(perform: load)
    }

    private var isEditing: Bool {
        if case .edit = mode { true } else { false }
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func load() {
        guard case .edit(let world) = mode else { return }
        name = world.name
        summary = world.summary
        system = world.system
    }

    private func save() {
        switch mode {
        case .create:
            modelContext.insert(World(name: trimmedName, summary: summary, system: system))
        case .edit(let world):
            world.name = trimmedName
            world.summary = summary
            world.system = system
        }
        dismiss()
    }
}

#Preview("New") {
    WorldEditorSheet(mode: .create)
        .modelContainer(SampleData.makePreviewContainer(populated: false))
}
