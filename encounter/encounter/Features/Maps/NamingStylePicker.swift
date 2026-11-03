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

/// Chooses the root languages of each realm and how much of each, so the names in a realm mix the influences it has.
struct RealmLanguagesEditor: View {
    @Binding var options: WorldOptions

    var body: some View {
        ForEach(0..<options.realms, id: \.self) { realm in
            DisclosureGroup {
                ForEach(RootLanguages.all) { language in
                    languageRow(language, realm: realm)
                }
            } label: {
                LabeledContent("Realm \(realm + 1)", value: summary(realm))
            }
        }
    }

    private func weight(of language: RootLanguage, realm: Int) -> Int? {
        options.languages(forRealm: realm).first { RootLanguages.aliasedID($0.id) == language.id }?.weight
    }

    private func summary(_ realm: Int) -> String {
        RootLanguages.mix(options.languages(forRealm: realm)).map(\.language.title).formatted(.list(type: .and, width: .narrow))
    }

    @ViewBuilder
    private func languageRow(_ language: RootLanguage, realm: Int) -> some View {
        let current = weight(of: language, realm: realm)
        Toggle(language.title, isOn: Binding(
            get: { current != nil },
            set: { options.setLanguage(language.id, on: $0, forRealm: realm) }
        ))
        .help(language.summary)
        if let current {
            Stepper(
                "Share: \(current)",
                value: Binding(get: { current }, set: { options.setWeight($0, of: language.id, forRealm: realm) }),
                in: 1...100, step: 10
            )
            .padding(.leading)
        }
    }
}
