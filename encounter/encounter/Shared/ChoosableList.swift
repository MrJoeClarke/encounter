//
//  ChoosableList.swift
//  encounter
//

import SwiftUI

/// Whether screens show a list beside what it chose. A Mac always does, and so does an iPad with room for it
/// (regular width). Otherwise, a phone or a narrow iPad window, the chosen screen is pushed on top of the list.
func showsSideBySide(_ sizeClass: UserInterfaceSizeClass?) -> Bool {
    #if os(macOS)
    true
    #else
    sizeClass == .regular
    #endif
}

/// A list beside the screen for what it chose, where `showsSideBySide` allows.
struct ListDetailSplit<List: View, Detail: View>: View {
    @ViewBuilder var list: () -> List
    @ViewBuilder var detail: () -> Detail

    var body: some View {
        #if os(macOS)
        HSplitView {
            list()
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 420, maxHeight: .infinity)
                .layoutPriority(-1)
            detail()
                .frame(minWidth: 360, idealWidth: 800, maxWidth: .infinity, maxHeight: .infinity)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // The paper behind both panes, so no gap between or around them shows the window's own, lighter colour.
        .themedBackground()
        #else
        HStack(spacing: 0) {
            list()
                .frame(width: 300)
                .frame(maxHeight: .infinity)
            Divider()
            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        #endif
    }
}

/// A list in which one row can be chosen. Side by side with what it chose, the choice is the list's selection,
/// which highlights the row. Otherwise rows react to a tap instead, because a phone's list reports its selection
/// only in some layouts, and the screen it opens is pushed by whoever reads the choice.
struct ChoosableList<Choice: Hashable, Content: View>: View {
    @Binding var choice: Choice?
    @ViewBuilder var content: () -> Content

    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        if showsSideBySide(sizeClass) {
            List(selection: $choice) {
                content()
                EndMarkRow()
            }
            .themedScreen()
        } else {
            List {
                content()
                EndMarkRow()
            }
            .themedScreen()
        }
    }
}

private struct Choosable<Choice: Hashable>: ViewModifier {
    let value: Choice
    @Binding var choice: Choice?

    @Environment(\.horizontalSizeClass) private var sizeClass

    func body(content: Content) -> some View {
        if showsSideBySide(sizeClass) {
            content.themedListRow().tag(value)
        } else {
            content
                .contentShape(Rectangle())
                .onTapGesture { choice = value }
                .accessibilityAddTraits(.isButton)
                .themedListRow()
        }
    }
}

extension View {
    /// Makes a row of a `ChoosableList` choosable: tagged where the list is selectable, tappable otherwise.
    func choosable<Choice: Hashable>(_ value: Choice, in choice: Binding<Choice?>) -> some View {
        modifier(Choosable(value: value, choice: choice))
    }
}
