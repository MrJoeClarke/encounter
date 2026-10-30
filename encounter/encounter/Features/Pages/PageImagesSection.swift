//
//  PageImagesSection.swift
//  encounter
//

import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

/// The Images section of the page editor: a thumbnail strip with add, default, reorder and delete.
struct PageImagesSection: View {
    @Bindable var page: Page

    @Environment(\.modelContext) private var modelContext
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var isChoosingFiles = false
    @State private var isImporting = false
    @State private var failedImportCount = 0
    @State private var imageToShow: PageImage?
    @State private var imageToDelete: PageImage?
    @State private var isDropTargeted = false

    private let tileSize: CGFloat = 96

    var body: some View {
        Section("Images") {
            let images = page.sortedImages
            Group {
                if images.isEmpty {
                    Text("No images yet. Drop image files here, or use the buttons below.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: tileSize / 2, alignment: .leading)
                } else {
                    ScrollView(.horizontal) {
                        HStack(spacing: 12) {
                            ForEach(images) { image in
                                tile(for: image, in: images)
                            }
                            .reorderable()
                        }
                        .reorderContainer(for: PageImage.self) { difference in
                            let before: UUID? = if case .before(let id) = difference.destination.position { id } else { nil }
                            page.moveImages(withIDs: difference.sources, before: before)
                        }
                        .padding(.vertical, 4)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            // Accepts image files dragged in from Finder (or any app that provides file URLs).
            .dropDestination(for: URL.self) { urls, _ in
                Task { await importFiles(urls) }
                return !urls.isEmpty
            } isTargeted: { isDropTargeted = $0 }
            .overlay {
                if isDropTargeted {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }

            HStack {
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Add Photos", systemImage: "photo.on.rectangle")
                }
                Button("Add Files…", systemImage: "folder") { isChoosingFiles = true }
                if isImporting {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .fileImporter(isPresented: $isChoosingFiles, allowedContentTypes: [.image], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            Task { await importFiles(urls) }
        }
        .onChange(of: photoSelection) {
            let items = photoSelection
            guard !items.isEmpty else { return }
            photoSelection = []
            Task { await importPhotos(items) }
        }
        .sheet(item: $imageToShow) { image in
            PageImageDetailSheet(page: page, image: image) {
                imageToDelete = image
            }
        }
        .alert(
            "Delete Image?",
            isPresented: Binding(get: { imageToDelete != nil }, set: { if !$0 { imageToDelete = nil } }),
            presenting: imageToDelete
        ) { image in
            Button("Delete", role: .destructive) { page.removeImage(image, in: modelContext) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This image will be removed from the page. This can’t be undone.")
        }
        .alert(
            "Some Images Couldn’t Be Added",
            isPresented: Binding(get: { failedImportCount > 0 }, set: { if !$0 { failedImportCount = 0 } })
        ) {
            Button("OK") {}
        } message: {
            Text("^[\(failedImportCount) file](inflect: true) couldn’t be read as an image.")
        }
    }

    private func tile(for image: PageImage, in images: [PageImage]) -> some View {
        let index = images.firstIndex { $0 === image } ?? 0
        return Button {
            imageToShow = image
        } label: {
            DataImage(data: image.thumbnailData ?? image.imageData)
                .frame(width: tileSize, height: tileSize)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topLeading) {
                    if image.isDefault {
                        Image(systemName: "star.fill")
                            .font(.caption)
                            .padding(5)
                            .background(.thinMaterial, in: Circle())
                            .padding(4)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(image.caption.isEmpty ? String(localized: "Image") : image.caption)
        .accessibilityValue(image.isDefault ? String(localized: "Default image") : "")
        .contextMenu {
            Button("Make Default", systemImage: "star") { page.setDefaultImage(image) }
                .disabled(image.isDefault)
            Button("Move Earlier", systemImage: "arrow.left") { page.moveImage(image, by: -1) }
                .disabled(index == 0)
            Button("Move Later", systemImage: "arrow.right") { page.moveImage(image, by: 1) }
                .disabled(index == images.count - 1)
            Button("Edit Caption…", systemImage: "text.cursor") { imageToShow = image }
            Button("Delete…", systemImage: "trash", role: .destructive) { imageToDelete = image }
        }
    }

    private func importPhotos(_ items: [PhotosPickerItem]) async {
        isImporting = true
        defer { isImporting = false }
        for item in items {
            let data = try? await item.loadTransferable(type: Data.self)
            await addImage(from: data)
        }
    }

    private func importFiles(_ urls: [URL]) async {
        isImporting = true
        defer { isImporting = false }
        for url in urls {
            await addImage(from: await ImageProcessing.loadData(from: url))
        }
    }

    private func addImage(from data: Data?) async {
        guard let data, let prepared = await ImageProcessing.prepare(data) else {
            failedImportCount += 1
            return
        }
        page.addImage(prepared, in: modelContext)
    }
}

/// A large view of one image, with caption editing and the per-image actions.
private struct PageImageDetailSheet: View {
    @Bindable var page: Page
    @Bindable var image: PageImage
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DataImage(data: image.imageData, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(image.caption.isEmpty ? String(localized: "Image") : image.caption)
                TextField("Caption", text: $image.caption, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Button(image.isDefault ? "Default Image" : "Make Default", systemImage: "star") {
                        page.setDefaultImage(image)
                    }
                    .disabled(image.isDefault)
                    Spacer()
                    Button("Delete…", systemImage: "trash", role: .destructive) {
                        dismiss()
                        onDelete()
                    }
                }
            }
            .padding()
            .navigationTitle("Image")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 520)
        #endif
    }
}
