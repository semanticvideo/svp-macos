import AppKit
import Quartz
import SwiftUI

// MARK: - Evidence Crops Detail View

struct EvidenceCropsDetailView: View {
    let data: SVPInspectorData
    @State private var quickLookController: EvidenceCropQuickLookController?

    var body: some View {
        Group {
            if data.evidenceCrops.isEmpty {
                EmptyStateView(message: "No evidence crops found in this package.")
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 12)],
                        spacing: 12
                    ) {
                        ForEach(Array(data.evidenceCrops.enumerated()), id: \.offset) { index, crop in
                            EvidenceCropCell(
                                crop: crop,
                                imageData: data.evidenceCropImages[crop["crop_file_path"] as? String ?? ""],
                                index: index
                            ) {
                                showQuickLook(startIndex: index)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func showQuickLook(startIndex: Int) {
        let controller = EvidenceCropQuickLookController(
            crops: data.evidenceCrops,
            images: data.evidenceCropImages,
            startIndex: startIndex
        )
        quickLookController = controller

        if let windowController = NSApp.keyWindow?.windowController as? SVPInspectorWindowController {
            windowController.showQuickLook(dataSource: controller, startIndex: startIndex)
        }
    }
}

// MARK: - Evidence Crop Cell

struct EvidenceCropCell: View {
    let crop: [String: Any]
    let imageData: Data?
    let index: Int
    let onTap: () -> Void

    var body: some View {
        VStack(spacing: 4) {
            if let imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 160, maxHeight: 120)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: 160, height: 120)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(spacing: 1) {
                Text(displayString(crop, "crop_id"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let textRegion = crop["text_region_id"] as? String, !textRegion.isEmpty {
                    Text(textRegion)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .onTapGesture {
            onTap()
        }
    }
}

// MARK: - Quick Look Data Source

final class EvidenceCropQuickLookController: NSObject, QLPreviewPanelDataSource {
    private let crops: [[String: Any]]
    private let images: [String: Data]
    let startIndex: Int
    private(set) var tempURLs: [URL] = []

    init(crops: [[String: Any]], images: [String: Data], startIndex: Int) {
        self.crops = crops
        self.images = images
        self.startIndex = startIndex
        super.init()
        writeTempFiles()
    }

    private func writeTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-evidence-crops", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        for (index, crop) in crops.enumerated() {
            guard let cropFilePath = crop["crop_file_path"] as? String,
                  let imageData = images[cropFilePath] else { continue }

            let ext = (cropFilePath as NSString).pathExtension.isEmpty ? "png" : (cropFilePath as NSString).pathExtension
            let url = tempDir.appendingPathComponent("crop_\(String(format: "%05d", index)).\(ext)")
            try? imageData.write(to: url)
            tempURLs.append(url)
        }
    }

    // MARK: - QLPreviewPanelDataSource

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        tempURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        guard index >= 0 && index < tempURLs.count else { return nil }
        return tempURLs[index] as QLPreviewItem
    }
}
