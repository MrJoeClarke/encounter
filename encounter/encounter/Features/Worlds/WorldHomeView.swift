//
//  WorldHomeView.swift
//  encounter
//

import SwiftUI
import SwiftData

/// A world's home page: its name, summary, rule system and images, plus export and delete.
struct WorldHomeView: View {
    @Bindable var world: World
    /// Called after the user confirms deletion. The caller leaves this screen and then deletes the world,
    /// so nothing is still showing a deleted world.
    let onDelete: (World) -> Void

    @State private var exportDocument: WorldExportDocument?
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var isConfirmingDelete = false

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $world.name, prompt: Text("Untitled World"))
                    .font(.title2.weight(.semibold))
            }

            Section("Summary") {
                TextEditor(text: $world.summary)
                    .frame(minHeight: 140)
            }

            Section {
                Picker("Rule System", selection: $world.system) {
                    ForEach(RuleSystemID.allCases) { system in
                        Text(system.title).tag(system)
                    }
                }
            } footer: {
                Text("The rule system adds attributes to your pages. You can change it at any time without losing data.")
            }

            ImagesSection(owner: world)

            Section {
                Button("Export World…", systemImage: "square.and.arrow.up", action: export)
            } footer: {
                Text("Saves this world, with its images, as a package you can keep as a backup or import again.")
            }

            Section {
                Button("Delete World…", systemImage: "trash", role: .destructive) { isConfirmingDelete = true }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Home")
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .encounterWorld,
            defaultFilename: exportDocument?.suggestedName
        ) { result in
            if case .failure(let error) = result {
                exportError = error.localizedDescription
            }
        }
        .alert(
            "Couldn’t Export World",
            isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } }),
            presenting: exportError
        ) { _ in
            Button("OK") {}
        } message: { message in
            Text(message)
        }
        .alert("Delete World?", isPresented: $isConfirmingDelete) {
            Button("Delete", role: .destructive) { onDelete(world) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("“\(world.name)” and all of its pages, maps and campaigns will be deleted. This can’t be undone.")
        }
    }

    private func export() {
        exportDocument = WorldExportDocument(world: world)
        isExporting = true
    }
}

#Preview("Home") {
    let container = SampleData.makePreviewContainer()
    let world = (try? container.mainContext.fetch(FetchDescriptor<World>(sortBy: [SortDescriptor(\.name)])))?.first
    return NavigationStack {
        if let world {
            WorldHomeView(world: world) { _ in }
        }
    }
    .frame(width: 900, height: 900)
    .modelContainer(container)
}
