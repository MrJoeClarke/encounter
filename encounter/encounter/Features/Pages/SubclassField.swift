//
//  SubclassField.swift
//  encounter
//

import SwiftUI

/// Picks a character's subclass. It only appears once the character has a library class that has subclasses,
/// and only offers that class's own. A class from the world has no subclass to pick: a custom version of a
/// library class carries its subclasses' features with it.
struct SubclassField: View {
    let label: LocalizedStringResource
    let role: String
    let classRole: String
    @Bindable var page: Page

    var body: some View {
        let options = subclasses
        Group {
            if !options.isEmpty {
                Picker(selection: selection(among: options)) {
                    Text("None").tag("")
                    ForEach(options) { subclass in
                        Text(subclass.name).tag(subclass.key)
                    }
                } label: {
                    Text(label)
                }
            }
        }
        // Changing class drops a subclass that belongs to the old one.
        .onChange(of: page.libraryKey(role: classRole)) {
            if let key = page.libraryKey(role: role), !subclasses.contains(where: { $0.key == key }) {
                page.setLibraryKey(nil, role: role)
            }
        }
    }

    /// The subclasses of the character's library class.
    private var subclasses: [LibraryEntry] {
        guard let classKey = page.libraryKey(role: classRole),
              let entry = Library.shared.entry(forKey: classKey),
              let edition = LibraryEdition(key: classKey)
        else { return [] }
        return Library.shared.children(of: entry, in: edition)
    }

    private func selection(among options: [LibraryEntry]) -> Binding<String> {
        Binding(
            get: {
                let key = page.libraryKey(role: role) ?? ""
                return options.contains { $0.key == key } ? key : ""
            },
            set: { page.setLibraryKey($0.isEmpty ? nil : $0, role: role) }
        )
    }
}
