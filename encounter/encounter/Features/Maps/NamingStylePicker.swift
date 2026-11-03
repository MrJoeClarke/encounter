//
//  NamingStylePicker.swift
//  encounter
//

import SwiftUI

/// Chooses how the names a generator makes sound, with a line about the choice under it.
struct NamingStylePicker: View {
    @Binding var styleID: String

    var body: some View {
        Picker("Names", selection: $styleID) {
            ForEach(NamingStyles.all) { style in Text(style.title).tag(style.id) }
        }
        .help(NamingStyles.style(styleID).summary)
    }
}
