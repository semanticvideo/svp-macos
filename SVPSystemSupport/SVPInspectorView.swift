import AppKit
import Quartz
import QuickLook
import SwiftUI
import SVPReader

// MARK: - Value Formatting Helpers

private func displayString(_ dict: [String: Any], _ key: String) -> String {
    guard let value = dict[key] else { return "—" }
    return formatValue(value)
}

private func formatValue(_ value: Any) -> String {
    if let s = value as? String { return s.isEmpty ? "—" : s }
    if let n = value as? NSNumber { return n.stringValue }
    if let arr = value as? [Any] { return "\(arr.count) items" }
    if let dict = value as? [String: Any] {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) { return str }
        return String(describing: dict)
    }
    return String(describing: value)
}

private func formatMicroseconds(_ dict: [String: Any], _ key: String) -> String {
    guard let value = dict[key] else { return "—" }
    if let n = value as? NSNumber {
        return String(format: "%.3f", n.doubleValue / 1_000_000)
    }
    return "—"
}

private func prettyJSON(_ dict: [String: Any]?) -> String {
    guard let dict else { return "—" }
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) { return str }
    return String(describing: dict)
}

// MARK: - Table Row Wrapper

private struct SortValue: Comparable {
    let value: Any?

    static func < (lhs: SortValue, rhs: SortValue) -> Bool {
        if lhs.value == nil && rhs.value == nil { return false }
        if lhs.value == nil { return true }
        if rhs.value == nil { return false }

        if let la = lhs.value as? [Any], let ra = rhs.value as? [Any] {
            return la.count < ra.count
        }
        if let ln = lhs.value as? NSNumber, let rn = rhs.value as? NSNumber {
            return ln.doubleValue < rn.doubleValue
        }

        let ls = String(describing: lhs.value!)
        let rs = String(describing: rhs.value!)
        return ls < rs
    }

    static func == (lhs: SortValue, rhs: SortValue) -> Bool {
        if let ln = lhs.value as? NSNumber, let rn = rhs.value as? NSNumber {
            return ln.doubleValue == rn.doubleValue
        }
        return String(describing: lhs.value ?? "") == String(describing: rhs.value ?? "")
    }
}

@dynamicMemberLookup
private struct InspectorRow: Identifiable {
    let id: Int
    let dict: [String: Any]

    subscript(dynamicMember key: String) -> SortValue {
        SortValue(value: dict[key])
    }

    var id_string: SortValue { SortValue(value: dict["id"]) }
}

private func makeRows(_ array: [[String: Any]]) -> [InspectorRow] {
    array.enumerated().map { InspectorRow(id: $0.offset, dict: $0.element) }
}

private func sortedRows(_ rows: [InspectorRow], sortOrder: [KeyPathComparator<InspectorRow>]) -> [InspectorRow] {
    guard !sortOrder.isEmpty else { return rows }
    return rows.sorted(using: sortOrder)
}

// MARK: - Reusable Views

private struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inspector Sections

enum SVPInspectorSection: String, CaseIterable, Identifiable {
    case overview
    case transcript
    case ocr
    case evidenceCrops
    case colors
    case scenes
    case entities
    case provenance
    case index

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .transcript: "Transcript"
        case .ocr: "OCR / Text"
        case .evidenceCrops: "Evidence Crops"
        case .colors: "Colors"
        case .scenes: "Scenes / Timeline"
        case .entities: "Entities"
        case .provenance: "Provenance"
        case .index: "Index Summary"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "info.circle"
        case .transcript: "text.bubble"
        case .ocr: "text.magnifyingglass"
        case .evidenceCrops: "crop"
        case .colors: "paintpalette"
        case .scenes: "film"
        case .entities: "person.2"
        case .provenance: "checkmark.shield"
        case .index: "tablecells"
        }
    }
}

// MARK: - Sidebar View

struct SVPInspectorSidebarView: View {
    @Binding var selectedSection: SVPInspectorSection?

    var body: some View {
        List(SVPInspectorSection.allCases, selection: $selectedSection) { section in
            Label(section.title, systemImage: section.symbolName)
                .font(.system(.body, weight: .medium))
                .tag(section)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("SVP Inspector")
    }
}

// MARK: - Split View Controller

final class SVPInspectorSplitViewController: NSSplitViewController {
    private let data: SVPInspectorData
    private var selectedSection = SVPInspectorSection.overview {
        didSet {
            updateDetail()
        }
    }
    private var sidebarHostingController: NSHostingController<SVPInspectorSidebarView>?
    private var detailHostingController: NSHostingController<AnyView>?

    init(data: SVPInspectorData) {
        self.data = data
        super.init(nibName: nil, bundle: nil)
        configureSplitView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SVPInspectorSplitViewController does not support storyboards.")
    }

    private var selectionBinding: Binding<SVPInspectorSection?> {
        Binding {
            self.selectedSection
        } set: { selectedSection in
            self.selectedSection = selectedSection ?? .overview
        }
    }

    private func configureSplitView() {
        splitView.dividerStyle = .thin

        let sidebarHostingController = NSHostingController(
            rootView: SVPInspectorSidebarView(selectedSection: selectionBinding)
        )
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHostingController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 280
        addSplitViewItem(sidebarItem)

        let detailHostingController = NSHostingController(
            rootView: Self.detailView(
                for: selectedSection,
                data: data
            )
        )
        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        addSplitViewItem(detailItem)

        self.sidebarHostingController = sidebarHostingController
        self.detailHostingController = detailHostingController
    }

    private func updateDetail() {
        detailHostingController?.rootView = Self.detailView(
            for: selectedSection,
            data: data
        )
    }

    private static func detailView(
        for section: SVPInspectorSection,
        data: SVPInspectorData
    ) -> AnyView {
        switch section {
        case .overview:
            AnyView(OverviewTab(data: data))
        case .transcript:
            AnyView(TranscriptTab(data: data))
        case .ocr:
            AnyView(OCRTab(data: data))
        case .evidenceCrops:
            AnyView(EvidenceCropsTab(data: data))
        case .colors:
            AnyView(ColorsTab(data: data))
        case .scenes:
            AnyView(ScenesTab(data: data))
        case .entities:
            AnyView(EntitiesTab(data: data))
        case .provenance:
            AnyView(ProvenanceTab(data: data))
        case .index:
            AnyView(IndexTab(data: data))
        }
    }
}

// MARK: - Error View

struct SVPInspectorErrorView: View {
    let error: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Failed to open SVP package")
                .font(.headline)
            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Overview Tab

private struct OverviewTab: View {
    let data: SVPInspectorData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Package") {
                    infoRow("File", data.fileURL.lastPathComponent)
                    infoRow("Path", data.fileURL.path)
                    if let m = data.manifest {
                        infoRow("SVP Version", m.svpVersion)
                        infoRow("Package ID", m.packageID)
                        infoRow("Created UTC", m.createdUTC)
                        infoRow("Primary Media ID", m.primaryMediaID)
                        infoRow("Timebase Unit", m.timebaseUnit)
                        infoRow("Timebase Origin", m.timebaseOrigin)
                    }
                    if let mi = data.mediaInfo {
                        infoRow("Media File", mi.mediaFileName)
                        infoRow("Media Size", "\(mi.uncompressedSize) bytes")
                        infoRow("Compressed", mi.isCompressed ? "Yes" : "No")
                    }
                    infoRow("Media Files", "\(data.mediaEntryCount)")
                }

                section("Section Counts") {
                    infoRow("Total Entries", "\(data.allEntries.count)")
                    infoRow("Transcript Words", "\(data.transcriptWords.count)")
                    infoRow("Speakers", "\(data.speakers.count)")
                    infoRow("Speaker Segments", "\(data.speakerSegments.count)")
                    infoRow("Text Regions", "\(data.textRegions.count)")
                    infoRow("Text Observations", "\(data.textObservations.count)")
                    infoRow("Numeric Values", "\(data.numericValues.count)")
                    infoRow("Evidence Crops", "\(data.evidenceCrops.count)")
                    infoRow("Color Observations", "\(data.colorObservations.count)")
                    infoRow("Shots", "\(data.shots.count)")
                    infoRow("Scenes", "\(data.scenes.count)")
                    infoRow("Frames", "\(data.frames.count)")
                    infoRow("Entities", "\(data.entities.count)")
                    infoRow("Entity Tracks", "\(data.entityTracks.count)")
                    infoRow("Relationships", "\(data.relationships.count)")
                    infoRow("Processors", "\(data.provenanceProcessors.count)")
                }

                if let vr = data.validationReport {
                    section("Validation") {
                        infoRow("Status", displayString(vr, "status"))
                        infoRow("Core Status", displayString(vr, "core_status"))
                        infoRow("Authenticity", displayString(vr, "authenticity_status"))
                    }
                }
            }
            .padding()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Transcript Tab

private struct TranscriptTab: View {
    let data: SVPInspectorData
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        if data.transcriptWords.isEmpty && data.transcriptSummary == nil {
            EmptyStateView(message: "No transcript data found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let ts = data.transcriptSummary {
                    HStack(spacing: 16) {
                        Label("\(displayString(ts, "word_count")) words", systemImage: "text.alignleft")
                        Label("\(displayString(ts, "speaker_count")) speakers", systemImage: "person.2")
                        if let dur = ts["duration_us"] as? NSNumber {
                            Label(String(format: "%.1f s", dur.doubleValue / 1_000_000), systemImage: "clock")
                        }
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                }

                let rows = sortedRows(makeRows(data.transcriptWords), sortOrder: sortOrder)
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Text", value: \InspectorRow.text) { row in
                        Text(displayString(row.dict, "text"))
                            .textSelection(.enabled)
                    }
                    .width(min: 80, ideal: 200)
                    TableColumn("Start (s)", value: \InspectorRow.start_us) { row in
                        Text(formatMicroseconds(row.dict, "start_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("End (s)", value: \InspectorRow.end_us) { row in
                        Text(formatMicroseconds(row.dict, "end_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Speaker", value: \InspectorRow.speaker_id) { row in
                        Text(displayString(row.dict, "speaker_id"))
                    }
                    .width(min: 80, ideal: 120)
                    TableColumn("Confidence", value: \InspectorRow.confidence) { row in
                        Text(displayString(row.dict, "confidence"))
                    }
                    .width(min: 60, ideal: 80)
                }
            }
        }
    }
}

// MARK: - OCR / Text Tab

private struct OCRTab: View {
    let data: SVPInspectorData
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        if data.textObservations.isEmpty && data.textRegions.isEmpty {
            if let absence = data.textAbsence {
                VStack(alignment: .leading, spacing: 8) {
                    EmptyStateView(message: "No text observations found.")
                        .frame(maxHeight: .infinity)
                    Text("Absence record: \(displayString(absence, "reason"))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)
                }
            } else {
                EmptyStateView(message: "No OCR / text data found in this package.")
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Label("\(data.textRegions.count) regions", systemImage: "rectangle.dashed")
                    Label("\(data.textObservations.count) observations", systemImage: "text.magnifyingglass")
                    Label("\(data.numericValues.count) numeric values", systemImage: "number")
                }
                .font(.caption)
                .padding(.horizontal, 4)

                let rows = sortedRows(makeRows(data.textObservations), sortOrder: sortOrder)
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Raw Text", value: \InspectorRow.raw_text) { row in
                        Text(displayString(row.dict, "raw_text"))
                            .textSelection(.enabled)
                    }
                    .width(min: 80, ideal: 200)
                    TableColumn("Normalized", value: \InspectorRow.normalized_text) { row in
                        Text(displayString(row.dict, "normalized_text"))
                    }
                    .width(min: 80, ideal: 150)
                    TableColumn("Start (s)", value: \InspectorRow.start_us) { row in
                        Text(formatMicroseconds(row.dict, "start_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Confidence", value: \InspectorRow.confidence) { row in
                        Text(displayString(row.dict, "confidence"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Region ID", value: \InspectorRow.text_region_id) { row in
                        Text(displayString(row.dict, "text_region_id"))
                    }
                    .width(min: 80, ideal: 140)
                }
            }
        }
    }
}

// MARK: - Evidence Crops Tab

private struct EvidenceCropsTab: View {
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

private struct EvidenceCropCell: View {
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

// MARK: - Colors Tab

private struct ColorsTab: View {
    let data: SVPInspectorData
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        if data.colorObservations.isEmpty {
            EmptyStateView(message: "No color observations found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = data.colorSummary {
                    HStack(spacing: 16) {
                        Label("\(displayString(summary, "color_observation_count")) observations", systemImage: "paintpalette")
                        Label(displayString(summary, "color_space"), systemImage: "circle.hexagongrid")
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                }

                let rows = sortedRows(makeRows(data.colorObservations), sortOrder: sortOrder)
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("Target Type", value: \InspectorRow.target_type) { row in
                        Text(displayString(row.dict, "target_type"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Target ID", value: \InspectorRow.target_id) { row in
                        Text(displayString(row.dict, "target_id"))
                    }
                    .width(min: 80, ideal: 140)
                    TableColumn("Start (s)", value: \InspectorRow.start_us) { row in
                        Text(formatMicroseconds(row.dict, "start_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Dominant", value: \InspectorRow.dominant_bucket) { row in
                        Text(displayString(row.dict, "dominant_bucket"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Coverage", value: \InspectorRow.coverage_total) { row in
                        Text(displayString(row.dict, "coverage_total"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Quality", value: \InspectorRow.quality_score) { row in
                        Text(displayString(row.dict, "quality_score"))
                    }
                    .width(min: 50, ideal: 70)
                }
            }
        }
    }
}

// MARK: - Scenes / Timeline Tab

private struct ScenesTab: View {
    let data: SVPInspectorData
    @State private var sceneSortOrder: [KeyPathComparator<InspectorRow>] = []
    @State private var shotSortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        if data.scenes.isEmpty && data.shots.isEmpty {
            EmptyStateView(message: "No scenes or shots found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !data.scenes.isEmpty {
                    Text("Scenes (\(data.scenes.count))")
                        .font(.headline)

                    let sceneRows = sortedRows(makeRows(data.scenes), sortOrder: sceneSortOrder)
                    Table(sceneRows, sortOrder: $sceneSortOrder) {
                        TableColumn("ID", value: \InspectorRow.id_string) { row in
                            Text(displayString(row.dict, "id"))
                        }
                        .width(min: 80, ideal: 140)
                        TableColumn("Start (s)", value: \InspectorRow.start_us) { row in
                            Text(formatMicroseconds(row.dict, "start_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("End (s)", value: \InspectorRow.end_us) { row in
                            Text(formatMicroseconds(row.dict, "end_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("Shots", value: \InspectorRow.shot_ids) { row in
                            if let shots = row.dict["shot_ids"] as? [Any] {
                                Text("\(shots.count)")
                            } else {
                                Text("—")
                            }
                        }
                        .width(min: 50, ideal: 60)
                    }
                }

                if !data.shots.isEmpty {
                    Text("Shots (\(data.shots.count))")
                        .font(.headline)

                    let shotRows = sortedRows(makeRows(data.shots), sortOrder: shotSortOrder)
                    Table(shotRows, sortOrder: $shotSortOrder) {
                        TableColumn("ID", value: \InspectorRow.id_string) { row in
                            Text(displayString(row.dict, "id"))
                        }
                        .width(min: 80, ideal: 140)
                        TableColumn("Start (s)", value: \InspectorRow.start_us) { row in
                            Text(formatMicroseconds(row.dict, "start_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("End (s)", value: \InspectorRow.end_us) { row in
                            Text(formatMicroseconds(row.dict, "end_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("Cut In", value: \InspectorRow.cut_type_in) { row in
                            Text(displayString(row.dict, "cut_type_in"))
                        }
                        .width(min: 60, ideal: 100)
                    }
                }
            }
        }
    }
}

// MARK: - Entities Tab

private struct EntitiesTab: View {
    let data: SVPInspectorData
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        if data.entities.isEmpty {
            EmptyStateView(message: "No entities found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Label("\(data.entities.count) entities", systemImage: "person.2")
                    Label("\(data.entityTracks.count) tracks", systemImage: "arrow.triangle.branch")
                }
                .font(.caption)
                .padding(.horizontal, 4)

                let rows = sortedRows(makeRows(data.entities), sortOrder: sortOrder)
                Table(rows, sortOrder: $sortOrder) {
                    TableColumn("ID", value: \InspectorRow.id_string) { row in
                        Text(displayString(row.dict, "id"))
                    }
                    .width(min: 80, ideal: 140)
                    TableColumn("Type", value: \InspectorRow.entity_type) { row in
                        Text(displayString(row.dict, "entity_type"))
                    }
                    .width(min: 60, ideal: 120)
                    TableColumn("First Seen (s)", value: \InspectorRow.first_seen_us) { row in
                        Text(formatMicroseconds(row.dict, "first_seen_us"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Last Seen (s)", value: \InspectorRow.last_seen_us) { row in
                        Text(formatMicroseconds(row.dict, "last_seen_us"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Avg Visibility", value: \InspectorRow.average_visibility) { row in
                        Text(displayString(row.dict, "average_visibility"))
                    }
                    .width(min: 60, ideal: 90)
                }
            }
        }
    }
}

// MARK: - Provenance / Validation Tab

private struct ProvenanceTab: View {
    let data: SVPInspectorData
    @State private var procSortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let vr = data.validationReport {
                    section("Validation Report") {
                        infoRow("Status", displayString(vr, "status"))
                        infoRow("Core Status", displayString(vr, "core_status"))
                        infoRow("Authenticity", displayString(vr, "authenticity_status"))
                        infoRow("Validator", displayString(vr, "validator"))
                        infoRow("Checked UTC", displayString(vr, "checked_utc"))
                        infoRow("Package Hash", displayString(vr, "package_hash"))

                        if let errors = vr["errors"] as? [Any], !errors.isEmpty {
                            Text("Errors: \(errors.count)")
                                .font(.body)
                                .foregroundStyle(.red)
                        }
                        if let warnings = vr["warnings"] as? [Any], !warnings.isEmpty {
                            Text("Warnings: \(warnings.count)")
                                .font(.body)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                if let build = data.provenanceBuild {
                    section("Build Info") {
                        infoRow("Builder", displayString(build, "builder"))
                        infoRow("Build UTC", displayString(build, "build_utc"))
                        infoRow("FFmpeg Version", displayString(build, "ffmpeg_version"))
                        infoRow("Source Media", displayString(build, "source_media_path"))
                    }
                }

                if !data.provenanceProcessors.isEmpty {
                    section("Processors (\(data.provenanceProcessors.count))") {
                        let procRows = sortedRows(makeRows(data.provenanceProcessors), sortOrder: procSortOrder)
                        Table(procRows, sortOrder: $procSortOrder) {
                            TableColumn("ID", value: \InspectorRow.id_string) { row in
                                Text(displayString(row.dict, "id"))
                            }
                            .width(min: 80, ideal: 180)
                            TableColumn("Name", value: \InspectorRow.name) { row in
                                Text(displayString(row.dict, "name"))
                            }
                            .width(min: 60, ideal: 150)
                            TableColumn("Version", value: \InspectorRow.version) { row in
                                Text(displayString(row.dict, "version"))
                            }
                            .width(min: 50, ideal: 80)
                        }
                        .frame(height: CGFloat(max(100, data.provenanceProcessors.count * 25)))
                    }
                }

                if data.validationReport != nil {
                    section("Validation JSON") {
                        Text(prettyJSON(data.validationReport))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(6)
                    }
                }

                if data.validationReport == nil && data.provenanceBuild == nil && data.provenanceProcessors.isEmpty {
                    EmptyStateView(message: "No provenance or validation data found.")
                }
            }
            .padding()
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Index Summary Tab

private struct IndexTab: View {
    let data: SVPInspectorData

    var body: some View {
        if !data.hasIndex && data.indexManifest == nil {
            EmptyStateView(message: "No search index found in this package.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Index Status") {
                        infoRow("SQLite Present", data.hasIndex ? "Yes" : "No")
                        infoRow("Manifest Present", data.indexManifest != nil ? "Yes" : "No")
                    }

                    if let im = data.indexManifest {
                        section("Index Manifest") {
                            infoRow("Schema Version", displayString(im, "schema_version"))
                            infoRow("Index Schema", displayString(im, "index_schema_version"))
                            infoRow("SQLite File", displayString(im, "sqlite_file"))
                            infoRow("Table Count", displayString(im, "table_count"))
                            infoRow("Row Count", displayString(im, "row_count"))
                            infoRow("SQLite BLAKE3", displayString(im, "sqlite_file_blake3"))
                            infoRow("Logical Rows BLAKE3", displayString(im, "logical_rows_blake3"))
                        }
                    }

                    section("All Package Entries") {
                        Text(data.allEntries.joined(separator: "\n"))
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(6)
                    }
                }
                .padding()
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.headline)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func infoRow(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(value)
                .font(.body)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
