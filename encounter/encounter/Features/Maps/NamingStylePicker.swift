//
//  NamingStylePicker.swift
//  encounter
//

import SwiftUI

/// Chooses the root language the proper names a generator makes come from.
struct NamingStylePicker: View {
    @Binding var styleID: String

    var body: some View {
        Picker("Names", selection: $styleID) {
            ForEach(RootLanguages.all) { language in Text(language.title).tag(language.id) }
        }
        .help(RootLanguages.language(styleID).summary)
    }
}
