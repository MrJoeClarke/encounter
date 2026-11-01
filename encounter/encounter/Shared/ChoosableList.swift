//
//  ChoosableList.swift
//  encounter
//

import SwiftUI

/// A list in which one row can be chosen. On a Mac the choice is the list's selection, which highlights the row.
/// On iOS rows react to a tap instead, because a phone's list reports its selection only in some layouts, and
/// the screen it opens is pushed by whoever reads the choice.
struct ChoosableList<Choice: Hashable, Content: View>: View {
    @Binding var choice: Choice?
    @ViewBuilder var content: () -> Content

    var body: some View {
        #if os(macOS)
        List(selection: $choice, content: content)
        #else
        List(content: content)
        #endif
    }
}

extension View {
    /// Makes a row of a `ChoosableList` choosable: tagged on a Mac, tappable on iOS.
    @ViewBuilder
    func choosable<Choice: Hashable>(_ value: Choice, in choice: Binding<Choice?>) -> some View {
        #if os(macOS)
        tag(value)
        #else
        contentShape(Rectangle())
            .onTapGesture { choice.wrappedValue = value }
            .accessibilityAddTraits(.isButton)
        #endif
    }
}
