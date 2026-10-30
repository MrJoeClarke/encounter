//
//  PageImage.swift
//  encounter
//

import Foundation
import SwiftData

/// An image attached to a page. A page can have many; one is flagged as the default.
/// The rules that keep exactly one default live in `Page+Images.swift`.
@Model
final class PageImage {
    var id: UUID = UUID()
    @Attribute(.externalStorage)
    var imageData: Data?
    /// Small version for lists, so they never decode the full-size image.
    var thumbnailData: Data?
    var caption: String = ""
    var sortOrder: Int = 0
    var isDefault: Bool = false
    var page: Page?

    init(imageData: Data? = nil, caption: String = "", sortOrder: Int = 0, isDefault: Bool = false) {
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
        self.isDefault = isDefault
    }
}
