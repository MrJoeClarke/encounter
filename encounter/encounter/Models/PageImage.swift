//
//  PageImage.swift
//  encounter
//

import Foundation
import SwiftData

/// An image attached to a page or to a world. Either can have many; one is flagged as the default.
/// The rules that keep exactly one default live in `ImageOwner.swift`.
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
    /// Set when the image belongs to a page. At most one of `page` and `world` is set.
    var page: Page?
    /// Set when the image belongs to a world.
    var world: World?

    init(imageData: Data? = nil, caption: String = "", sortOrder: Int = 0, isDefault: Bool = false) {
        self.imageData = imageData
        self.caption = caption
        self.sortOrder = sortOrder
        self.isDefault = isDefault
    }
}
