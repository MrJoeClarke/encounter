//
//  DataImage.swift
//  encounter
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Shows an image from encoded data, or a neutral placeholder if there's none or it can't be decoded.
struct DataImage: View {
    let data: Data?
    var contentMode: ContentMode = .fill

    var body: some View {
        if let image = platformImage {
            image
                .resizable()
                .aspectRatio(contentMode: contentMode)
        } else {
            Color.secondary.opacity(0.15)
        }
    }

    private var platformImage: Image? {
        guard let data else { return nil }
        #if canImport(UIKit)
        return UIImage(data: data).map(Image.init(uiImage:))
        #else
        return NSImage(data: data).map(Image.init(nsImage:))
        #endif
    }
}
