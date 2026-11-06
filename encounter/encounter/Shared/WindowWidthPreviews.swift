//
//  WindowWidthPreviews.swift
//  encounter
//

import SwiftUI

#if DEBUG
/// The widths an iPad window can have when it shares the screen: the strip of Slide Over and the narrowest Split View (320), a half of
/// the screen (507), and just wide enough for the menu to sit beside the screen (678).
enum WindowWidth: Double, CaseIterable {
    case strip = 320
    case half = 507
    case wide = 678
    case full = 1024

    /// Whether a window this wide is compact, as iPad windows of up to about half the screen are.
    var isCompact: Bool { rawValue <= 507 }
}

extension View {
    /// Shows this view as it would be in an iPad window of that width: the width, and the size class that goes with it, so it takes the
    /// layout a narrow window takes. For previews, where there is no real window to shrink.
    func inWindow(_ width: WindowWidth, height: Double = 800) -> some View {
        environment(\.horizontalSizeClass, width.isCompact ? .compact : .regular)
            .frame(width: width.rawValue, height: height)
    }
}
#endif
