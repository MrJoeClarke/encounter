//
//  AboutView.swift
//  encounter
//

import SwiftUI

/// About Encounter, including the attribution statements the content library's licence requires.
struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Encounter") {
                    Text("A world building tool for tabletop role-playing games.")
                }

                Section {
                    ForEach(LibraryEdition.allCases) { edition in
                        if let attribution = Library.shared.attribution(for: edition) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(edition.title)
                                    .font(.headline)
                                Text(attribution)
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                } header: {
                    Text("Content Library")
                } footer: {
                    Text("The text of the library has been reformatted for display. Its wording is unchanged.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("About")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 480, minHeight: 420)
        #endif
    }
}

#Preview {
    AboutView()
}
