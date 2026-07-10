import AppKit
import Quartz
import SwiftUI
import SVPReader

// MARK: - Evidence Crops Detail View

struct EvidenceCropsDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var quickLookController: EvidenceCropQuickLookController?

    var body: some View {
        switch viewModel.evidenceCropsState {
        case .idle, .loading:
            LoadingStateView(message: "Loading evidence crops...")
                .onAppear { viewModel.loadSectionIfNeeded(.evidenceCrops) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.evidenceCrops)
            }
        case .loaded(let data):
            cropsContent(data)
        }
    }

    private func cropsContent(_ data: SVPInspectorEvidenceCropsData) -> some View {
        Group {
            if data.crops.isEmpty {
                EmptyStateView(message: "No evidence crops found in this package.")
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 160, maximum: 180), spacing: 16)],
                        spacing: 14
                    ) {
                        ForEach(Array(data.crops.enumerated()), id: \.offset) { index, crop in
                            EvidenceCropCell(
                                packageURL: data.fileURL,
                                package: data.package,
                                crop: crop,
                                index: index
                            ) {
                                showQuickLook(data: data, startIndex: index)
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func showQuickLook(data: SVPInspectorEvidenceCropsData, startIndex: Int) {
        let controller = EvidenceCropQuickLookController(
            packageURL: data.fileURL,
            package: data.package,
            crops: data.crops,
            startIndex: startIndex
        )
        quickLookController = controller

        if let windowController = NSApp.keyWindow?.windowController as? SVPInspectorWindowController {
            windowController.showQuickLook(dataSource: controller)
        }
    }
}

// MARK: - Evidence Crop Cell

struct EvidenceCropCell: View {
    let packageURL: URL
    let package: SVPPackageDescriptor?
    let crop: [String: Any]
    let index: Int
    let onTap: () -> Void
    @State private var imageData: Data?
    @State private var didRequestImage = false

    var body: some View {
        let placeholderSize = thumbnailSize(for: crop)

        VStack(spacing: 4) {
            if let imageData, let nsImage = NSImage(data: imageData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: placeholderSize.width, height: placeholderSize.height)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary, lineWidth: 0.5))
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .frame(width: placeholderSize.width, height: placeholderSize.height)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.caption)
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
        .onAppear {
            loadImageIfNeeded()
        }
    }

    private func loadImageIfNeeded() {
        guard !didRequestImage else { return }
        didRequestImage = true

        guard let cropFilePath = crop["crop_file_path"] as? String, !cropFilePath.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            let data = try? SVPInspectorDataLoader.loadEvidenceCropImage(
                packageURL: packageURL,
                package: package,
                cropFilePath: cropFilePath
            )
            DispatchQueue.main.async {
                imageData = data ?? nil
            }
        }
    }

    private func thumbnailSize(for crop: [String: Any]) -> CGSize {
        let maxWidth: CGFloat = 160
        let maxHeight: CGFloat = 120
        guard let cropSize = cropPixelSize(for: crop),
              cropSize.width > 0,
              cropSize.height > 0 else {
            return CGSize(width: maxWidth, height: maxHeight)
        }

        let scale = min(maxWidth / cropSize.width, maxHeight / cropSize.height)
        return CGSize(width: cropSize.width * scale, height: cropSize.height * scale)
    }

    private func cropPixelSize(for crop: [String: Any]) -> CGSize? {
        guard let bbox = crop["crop_bbox"] as? [Any], bbox.count >= 4,
              let x1 = numberValue(bbox[0]),
              let y1 = numberValue(bbox[1]),
              let x2 = numberValue(bbox[2]),
              let y2 = numberValue(bbox[3]) else { return nil }

        return CGSize(width: abs(x2 - x1), height: abs(y2 - y1))
    }

    private func numberValue(_ value: Any) -> CGFloat? {
        if let number = value as? NSNumber { return CGFloat(truncating: number) }
        if let double = value as? Double { return CGFloat(double) }
        if let int = value as? Int { return CGFloat(int) }
        return nil
    }
}

// MARK: - Quick Look Data Source

final class EvidenceCropQuickLookController: NSObject, QLPreviewPanelDataSource {
    private let packageURL: URL
    private let package: SVPPackageDescriptor?
    private let crops: [[String: Any]]
    let startIndex: Int
    private(set) var tempURLs: [URL] = []

    init(packageURL: URL, package: SVPPackageDescriptor?, crops: [[String: Any]], startIndex: Int) {
        self.packageURL = packageURL
        self.package = package
        self.crops = crops
        self.startIndex = startIndex
        super.init()
        writeTempFiles()
    }

    private func writeTempFiles() {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-evidence-crops", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        guard startIndex >= 0, startIndex < crops.count else { return }
        let crop = crops[startIndex]
        guard let cropFilePath = crop["crop_file_path"] as? String,
              let imageData = try? SVPInspectorDataLoader.loadEvidenceCropImage(
                packageURL: packageURL,
                package: package,
                cropFilePath: cropFilePath
              ) else { return }

        let ext = (cropFilePath as NSString).pathExtension.isEmpty ? "png" : (cropFilePath as NSString).pathExtension
        let url = tempDir.appendingPathComponent("crop_\(String(format: "%05d", startIndex)).\(ext)")
        try? imageData.write(to: url)
        tempURLs.append(url)
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
