//
//  ImageOwner.swift
//  encounter
//

import Foundation
import SwiftData

/// Something that owns an ordered set of images with a single default: a page or a world.
/// The rules for adding, ordering and removing images are shared, in the extension below.
protocol ImageOwner: AnyObject {
    var images: [PageImage]? { get }
    /// Sets the image's inverse relationship to this owner.
    func attach(_ image: PageImage)
}

extension Page: ImageOwner {
    func attach(_ image: PageImage) {
        image.page = self
    }
}

extension World: ImageOwner {
    func attach(_ image: PageImage) {
        image.world = self
    }
}

extension ImageOwner {
    /// Images in display order. Excludes images deleted but not yet saved.
    var sortedImages: [PageImage] {
        (images ?? [])
            .filter { !$0.isDeleted }
            .sorted { $0.sortOrder < $1.sortOrder }
    }

    var defaultImage: PageImage? {
        sortedImages.first { $0.isDefault }
    }

    /// Adds an image at the end. The first image an owner gets becomes its default.
    @discardableResult
    func addImage(_ prepared: PreparedImage, caption: String = "", in context: ModelContext) -> PageImage {
        let existing = sortedImages
        let image = PageImage(
            imageData: prepared.imageData,
            caption: caption,
            sortOrder: (existing.last?.sortOrder ?? -1) + 1,
            isDefault: existing.isEmpty
        )
        image.thumbnailData = prepared.thumbnailData
        context.insert(image)
        attach(image)
        return image
    }

    /// Makes the image the default and clears the flag on every other image.
    func setDefaultImage(_ image: PageImage) {
        for other in sortedImages {
            other.isDefault = (other === image)
        }
    }

    /// Repairs the default flag after bulk changes such as an import: exactly one default if there are any
    /// images, keeping the first flagged one (or the first image if none was flagged).
    func ensureSingleDefaultImage() {
        let images = sortedImages
        guard let first = images.first else { return }
        let flagged = images.filter(\.isDefault)
        if flagged.count != 1 {
            setDefaultImage(flagged.first ?? first)
        }
    }

    /// Deletes the image. If it was the default, the next image in order is promoted.
    func removeImage(_ image: PageImage, in context: ModelContext) {
        let wasDefault = image.isDefault
        context.delete(image)
        if wasDefault, let next = sortedImages.first {
            setDefaultImage(next)
        }
    }

    /// Moves the images with the given IDs, keeping their relative order, to sit before the image
    /// with `targetID`. A nil or unknown target moves them to the end, and a target that is itself being
    /// moved changes nothing. This is what a drag-reorder applies.
    func moveImages(withIDs ids: [UUID], before targetID: UUID?) {
        let moving = Set(ids)
        if let targetID, moving.contains(targetID) { return }
        var ordered = sortedImages
        let moved = ordered.filter { moving.contains($0.id) }
        guard !moved.isEmpty else { return }
        ordered.removeAll { moving.contains($0.id) }
        let index = targetID.flatMap { id in ordered.firstIndex { $0.id == id } } ?? ordered.endIndex
        ordered.insert(contentsOf: moved, at: index)
        for (position, image) in ordered.enumerated() {
            image.sortOrder = position
        }
    }

    /// Moves the image earlier (negative offset) or later (positive). Does nothing at either end.
    func moveImage(_ image: PageImage, by offset: Int) {
        var ordered = sortedImages
        guard let index = ordered.firstIndex(where: { $0 === image }) else { return }
        let target = index + offset
        guard ordered.indices.contains(target) else { return }
        ordered.swapAt(index, target)
        for (position, image) in ordered.enumerated() {
            image.sortOrder = position
        }
    }
}
