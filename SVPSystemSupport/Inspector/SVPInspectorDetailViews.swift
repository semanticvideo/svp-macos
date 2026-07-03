import AppKit
import SwiftUI
import SVPReader

// MARK: - Overview Detail View

struct OverviewDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

    var body: some View {
        switch viewModel.overviewState {
        case .idle, .loading:
            LoadingStateView(message: "Loading overview...")
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.overview)
            }
        case .loaded(let data):
            overviewContent(data)
        }
    }

    @ViewBuilder
    private func overviewContent(_ data: SVPInspectorOverviewData) -> some View {
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
                    infoRow("Transcript", "\(data.entryCounts[.transcript] ?? 0)")
                    infoRow("OCR / Text", "\(data.entryCounts[.ocr] ?? 0)")
                    infoRow("Evidence Crops", "\(data.entryCounts[.evidenceCrops] ?? 0)")
                    infoRow("Colors", "\(data.entryCounts[.colors] ?? 0)")
                    infoRow("Scenes / Timeline", "\(data.entryCounts[.scenes] ?? 0)")
                    infoRow("Entities", "\(data.entryCounts[.entities] ?? 0)")
                    infoRow("Relationships", "\(data.entryCounts[.relationships] ?? 0)")
                    infoRow("Provenance", "\(data.entryCounts[.provenance] ?? 0)")
                    infoRow("Index Summary", "\(data.entryCounts[.index] ?? 0)")
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

// MARK: - Transcript Detail View

struct TranscriptDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        switch viewModel.transcriptState {
        case .idle, .loading:
            LoadingStateView(message: "Loading transcript...")
                .onAppear { viewModel.loadSectionIfNeeded(.transcript) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.transcript)
            }
        case .loaded(let data):
            transcriptContent(data)
        }
    }

    @ViewBuilder
    private func transcriptContent(_ data: SVPInspectorTranscriptData) -> some View {
        if data.words.isEmpty && data.summary == nil {
            EmptyStateView(message: "No transcript data found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let ts = data.summary {
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

                let rows = sortedRows(makeRows(data.words), sortOrder: sortOrder)
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

// MARK: - OCR / Text Detail View

struct OCRDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        switch viewModel.textState {
        case .idle, .loading:
            LoadingStateView(message: "Loading OCR / text...")
                .onAppear { viewModel.loadSectionIfNeeded(.ocr) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.ocr)
            }
        case .loaded(let data):
            ocrContent(data)
        }
    }

    @ViewBuilder
    private func ocrContent(_ data: SVPInspectorTextData) -> some View {
        if data.observations.isEmpty && data.regions.isEmpty {
            if let absence = data.absence {
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
                    Label("\(data.regions.count) regions", systemImage: "rectangle.dashed")
                    Label("\(data.observations.count) observations", systemImage: "text.magnifyingglass")
                    Label("\(data.numericValues.count) numeric values", systemImage: "number")
                }
                .font(.caption)
                .padding(.horizontal, 4)

                let rows = sortedRows(makeRows(data.observations), sortOrder: sortOrder)
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

// MARK: - Color Bucket Dots

private let bucketColors: [String: Color] = [
    "black": .black,
    "blue": .blue,
    "brown": .brown,
    "cyan": .cyan,
    "gray": .gray,
    "green": .green,
    "orange": .orange,
    "pink": .pink,
    "purple": .purple,
    "red": .red,
    "white": .white,
    "yellow": .yellow,
    "other": .secondary,
]

private struct ColorBucketDots: View {
    let bucketCoverage: [String: Any]

    private var sortedBuckets: [(name: String, coverage: Double)] {
        bucketCoverage.compactMap { (key, value) in
            if let n = value as? NSNumber {
                return (name: key, coverage: n.doubleValue)
            }
            return nil
        }
        .filter { $0.coverage > 0 }
        .sorted { $0.coverage > $1.coverage }
    }

    private func textColor(for bucket: String) -> Color {
        let lightBuckets: Set<String> = ["white", "yellow", "cyan", "gray", "orange", "pink"]
        return lightBuckets.contains(bucket) ? .black : .white
    }

    var body: some View {
        if sortedBuckets.isEmpty {
            Text("—")
        } else {
            GeometryReader { geo in
                let dotWidth: CGFloat = 28
                let spacing: CGFloat = 4
                let maxDots = max(1, Int((geo.size.width + spacing) / (dotWidth + spacing)))
                HStack(spacing: spacing) {
                    ForEach(sortedBuckets.prefix(maxDots), id: \.name) { bucket in
                        let pct = Int((bucket.coverage * 100).rounded())
                        ZStack {
                            Circle()
                                .fill(bucketColors[bucket.name] ?? .secondary)
                                .frame(width: dotWidth, height: dotWidth)
                            Text("\(pct)%")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(textColor(for: bucket.name))
                        }
                    }
                }
            }
            .frame(height: 28)
        }
    }
}

// MARK: - Colors Detail View

struct ColorsDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        switch viewModel.colorsState {
        case .idle, .loading:
            LoadingStateView(message: "Loading colors...")
                .onAppear { viewModel.loadSectionIfNeeded(.colors) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.colors)
            }
        case .loaded(let data):
            colorsContent(data)
        }
    }

    @ViewBuilder
    private func colorsContent(_ data: SVPInspectorColorsData) -> some View {
        if data.observations.isEmpty {
            EmptyStateView(message: "No color observations found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let summary = data.summary {
                    HStack(spacing: 16) {
                        Label("\(displayString(summary, "color_observation_count")) observations", systemImage: "paintpalette")
                        Label(displayString(summary, "color_space"), systemImage: "circle.hexagongrid")
                    }
                    .font(.caption)
                    .padding(.horizontal, 4)
                }

                let rows = sortedRows(makeRows(data.observations), sortOrder: sortOrder)
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
                    TableColumn("Breakdown") { row in
                        if let buckets = row.dict["bucket_coverage"] as? [String: Any] {
                            ColorBucketDots(bucketCoverage: buckets)
                        } else {
                            Text("—")
                        }
                    }
                    .width(min: 124, ideal: 124)
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

// MARK: - Scenes / Timeline Detail View

struct ScenesDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var sceneSortOrder: [KeyPathComparator<InspectorRow>] = []
    @State private var shotSortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        switch viewModel.timelineState {
        case .idle, .loading:
            LoadingStateView(message: "Loading scenes / timeline...")
                .onAppear { viewModel.loadSectionIfNeeded(.scenes) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.scenes)
            }
        case .loaded(let data):
            timelineContent(data)
        }
    }

    @ViewBuilder
    private func timelineContent(_ data: SVPInspectorTimelineData) -> some View {
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

// MARK: - Entities Detail View

struct EntitiesDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var sortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        switch viewModel.entitiesState {
        case .idle, .loading:
            LoadingStateView(message: "Loading entities...")
                .onAppear { viewModel.loadSectionIfNeeded(.entities) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.entities)
            }
        case .loaded(let data):
            entitiesContent(data)
        }
    }

    @ViewBuilder
    private func entitiesContent(_ data: SVPInspectorEntitiesData) -> some View {
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

// MARK: - Relationships Detail View

struct RelationshipsDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

    var body: some View {
        switch viewModel.relationshipsState {
        case .idle, .loading:
            LoadingStateView(message: "Loading relationships...")
                .onAppear { viewModel.loadSectionIfNeeded(.relationships) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.relationships)
            }
        case .loaded(let data):
            relationshipsContent(data)
        }
    }

    @ViewBuilder
    private func relationshipsContent(_ data: SVPInspectorRelationshipsData) -> some View {
        if data.store.rowCount == 0 {
            EmptyStateView(message: "No relationships found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Label("\(data.store.rowCount) relationships", systemImage: "point.3.connected.trianglepath.dotted")
                    if let size = data.store.uncompressedSize {
                        Label(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file), systemImage: "doc.text")
                    }
                }
                .font(.caption)
                .padding(.horizontal, 4)

                RelationshipsTableView(store: data.store)
            }
        }
    }
}

private struct RelationshipsTableView: NSViewRepresentable {
    let store: SVPRelationshipJSONLStore

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder

        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        addColumn("source", title: "Source", width: 170, to: tableView)
        addColumn("type", title: "Type", width: 190, to: tableView)
        addColumn("target", title: "Target", width: 170, to: tableView)
        addColumn("start", title: "Start (s)", width: 80, to: tableView)
        addColumn("end", title: "End (s)", width: 80, to: tableView)
        addColumn("confidence", title: "Confidence", width: 90, to: tableView)

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.store = store
        if let tableView = scrollView.documentView as? NSTableView {
            tableView.reloadData()
        }
    }

    private func addColumn(_ identifier: String, title: String, width: CGFloat, to tableView: NSTableView) {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(identifier))
        column.title = title
        column.width = width
        column.minWidth = 60
        tableView.addTableColumn(column)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var store: SVPRelationshipJSONLStore

        init(store: SVPRelationshipJSONLStore) {
            self.store = store
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            store.rowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
            let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
                ?? makeTextField(identifier: identifier)
            let relationship = store.row(at: row)

            switch identifier.rawValue {
            case "source":
                textField.stringValue = relationship?.sourceID ?? "—"
            case "type":
                textField.stringValue = relationship?.type ?? "—"
            case "target":
                textField.stringValue = relationship?.targetID ?? "—"
            case "start":
                textField.stringValue = relationship?.startText ?? "—"
            case "end":
                textField.stringValue = relationship?.endText ?? "—"
            case "confidence":
                textField.stringValue = relationship?.confidence ?? "—"
            default:
                textField.stringValue = "—"
            }

            return textField
        }

        private func makeTextField(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
            let textField = NSTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingMiddle
            textField.maximumNumberOfLines = 1
            textField.cell?.truncatesLastVisibleLine = true
            textField.isSelectable = true
            return textField
        }
    }
}

// MARK: - Provenance / Validation Detail View

struct ProvenanceDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel
    @State private var procSortOrder: [KeyPathComparator<InspectorRow>] = []

    var body: some View {
        switch viewModel.provenanceState {
        case .idle, .loading:
            LoadingStateView(message: "Loading provenance...")
                .onAppear { viewModel.loadSectionIfNeeded(.provenance) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.provenance)
            }
        case .loaded(let data):
            provenanceContent(data)
        }
    }

    @ViewBuilder
    private func provenanceContent(_ data: SVPInspectorProvenanceData) -> some View {
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

                if let build = data.build {
                    section("Build Info") {
                        infoRow("Builder", displayString(build, "builder"))
                        infoRow("Build UTC", displayString(build, "build_utc"))
                        infoRow("FFmpeg Version", displayString(build, "ffmpeg_version"))
                        infoRow("Source Media", displayString(build, "source_media_path"))
                    }
                }

                if !data.processors.isEmpty {
                    section("Processors (\(data.processors.count))") {
                        let procRows = sortedRows(makeRows(data.processors), sortOrder: procSortOrder)
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
                        .frame(height: CGFloat(max(100, data.processors.count * 25)))
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

                if data.validationReport == nil && data.build == nil && data.processors.isEmpty {
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

// MARK: - Index Summary Detail View

struct IndexDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

    var body: some View {
        switch viewModel.indexState {
        case .idle, .loading:
            LoadingStateView(message: "Loading index summary...")
                .onAppear { viewModel.loadSectionIfNeeded(.index) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.index)
            }
        case .loaded(let data):
            indexContent(data)
        }
    }

    @ViewBuilder
    private func indexContent(_ data: SVPInspectorIndexData) -> some View {
        if !data.hasIndex && data.manifest == nil {
            EmptyStateView(message: "No search index found in this package.")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    section("Index Status") {
                        infoRow("SQLite Present", data.hasIndex ? "Yes" : "No")
                        infoRow("Manifest Present", data.manifest != nil ? "Yes" : "No")
                    }

                    if let im = data.manifest {
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
