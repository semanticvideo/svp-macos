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
        if data.words.rowCount == 0 && data.summary == nil {
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

                InspectorJSONLTableView(store: data.words, columns: [
                    .text("Text", key: "text", width: 200),
                    .microseconds("Start (s)", key: "start_us", width: 80),
                    .microseconds("End (s)", key: "end_us", width: 80),
                    .text("Speaker", key: "speaker_id", width: 120),
                    .text("Confidence", key: "confidence", width: 80)
                ])
            }
        }
    }
}

// MARK: - OCR / Text Detail View

struct OCRDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

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
        if data.observations.rowCount == 0 && data.regions.rowCount == 0 {
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
                    Label("\(data.regions.rowCount) regions", systemImage: "rectangle.dashed")
                    Label("\(data.observations.rowCount) observations", systemImage: "text.magnifyingglass")
                    Label("\(data.numericValues.rowCount) numeric values", systemImage: "number")
                }
                .font(.caption)
                .padding(.horizontal, 4)

                InspectorJSONLTableView(store: data.observations, columns: [
                    .text("Raw Text", key: "raw_text", width: 200),
                    .text("Normalized", key: "normalized_text", width: 150),
                    .microseconds("Start (s)", key: "start_us", width: 80),
                    .text("Confidence", key: "confidence", width: 80),
                    .text("Region ID", key: "text_region_id", width: 140)
                ])
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

private func formatColorBuckets(_ bucketCoverage: [String: Any]?) -> String {
    guard let bucketCoverage else { return "—" }
    let buckets = bucketCoverage.compactMap { key, value -> (String, Double)? in
        guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
        return (key, number.doubleValue)
    }
    .sorted { $0.1 > $1.1 }
    .prefix(4)

    guard !buckets.isEmpty else { return "—" }
    return buckets
        .map { "\($0.0) \(Int(($0.1 * 100).rounded()))%" }
        .joined(separator: ", ")
}

// MARK: - Colors Detail View

struct ColorsDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

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
        if data.observations.rowCount == 0 {
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

                InspectorJSONLTableView(store: data.observations, columns: [
                    .text("Target Type", key: "target_type", width: 100),
                    .text("Target ID", key: "target_id", width: 140),
                    .microseconds("Start (s)", key: "start_us", width: 80),
                    .text("Dominant", key: "dominant_bucket", width: 100),
                    .custom("Breakdown", width: 160) { row in
                        formatColorBuckets(row["bucket_coverage"] as? [String: Any])
                    },
                    .text("Coverage", key: "coverage_total", width: 80),
                    .text("Quality", key: "quality_score", width: 70)
                ])
            }
        }
    }
}

// MARK: - Scenes / Timeline Detail View

struct ScenesDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

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
        if data.scenes.rowCount == 0 && data.shots.rowCount == 0 {
            EmptyStateView(message: "No scenes or shots found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if data.scenes.rowCount > 0 {
                    Text("Scenes (\(data.scenes.rowCount))")
                        .font(.headline)

                    InspectorJSONLTableView(store: data.scenes, columns: [
                        .text("ID", key: "id", width: 140),
                        .microseconds("Start (s)", key: "start_us", width: 80),
                        .microseconds("End (s)", key: "end_us", width: 80),
                        .custom("Shots", width: 60) { row in
                            if let shots = row["shot_ids"] as? [Any] { return "\(shots.count)" }
                            return "—"
                        }
                    ])
                }

                if data.shots.rowCount > 0 {
                    Text("Shots (\(data.shots.rowCount))")
                        .font(.headline)

                    InspectorJSONLTableView(store: data.shots, columns: [
                        .text("ID", key: "id", width: 140),
                        .microseconds("Start (s)", key: "start_us", width: 80),
                        .microseconds("End (s)", key: "end_us", width: 80),
                        .text("Cut In", key: "cut_type_in", width: 100)
                    ])
                }
            }
        }
    }
}

// MARK: - Entities Detail View

struct EntitiesDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

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
        if data.entities.rowCount == 0 {
            EmptyStateView(message: "No entities found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 16) {
                    Label("\(data.entities.rowCount) entities", systemImage: "person.2")
                    Label("\(data.entityTracks.rowCount) tracks", systemImage: "arrow.triangle.branch")
                }
                .font(.caption)
                .padding(.horizontal, 4)

                InspectorJSONLTableView(store: data.entities, columns: [
                    .text("ID", key: "id", width: 140),
                    .text("Type", key: "entity_type", width: 120),
                    .microseconds("First Seen (s)", key: "first_seen_us", width: 100),
                    .microseconds("Last Seen (s)", key: "last_seen_us", width: 100),
                    .text("Avg Visibility", key: "average_visibility", width: 90)
                ])
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

                InspectorJSONLTableView(store: data.store, columns: [
                    .text("Source", key: "source_id", width: 170),
                    .text("Type", key: "type", width: 190),
                    .text("Target", key: "target_id", width: 170),
                    .microseconds("Start (s)", key: "start_us", width: 80),
                    .microseconds("End (s)", key: "end_us", width: 80),
                    .text("Confidence", key: "confidence", width: 90)
                ])
            }
        }
    }
}

private struct InspectorJSONLColumn {
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
    let text: (SVPInspectorJSONLStore, Int) -> String
    let sortValue: ((SVPInspectorJSONLStore, Int) -> SVPInspectorJSONLSortValue)?

    static func text(_ title: String, key: String, width: CGFloat, minWidth: CGFloat = 60) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in store.text(at: row, key: key) },
            sortValue: { store, row in store.sortValue(at: row, key: key) }
        )
    }

    static func microseconds(_ title: String, key: String, width: CGFloat, minWidth: CGFloat = 60) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in store.microsecondsText(at: row, key: key) },
            sortValue: { store, row in store.sortValue(at: row, key: key) }
        )
    }

    static func custom(
        _ title: String,
        width: CGFloat,
        minWidth: CGFloat = 60,
        text: @escaping ([String: Any]) -> String
    ) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in
                guard let dict = store.row(at: row) else { return "—" }
                return text(dict)
            },
            sortValue: nil
        )
    }
}

private struct InspectorJSONLTableView: NSViewRepresentable {
    let store: SVPInspectorJSONLStore
    let columns: [InspectorJSONLColumn]

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, columns: columns)
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

        for (index, column) in columns.enumerated() {
            addColumn(index: index, column: column, to: tableView)
        }

        scrollView.documentView = tableView
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        context.coordinator.store = store
        context.coordinator.columns = columns
        if let tableView = scrollView.documentView as? NSTableView {
            context.coordinator.applySortDescriptors(tableView.sortDescriptors)
            tableView.reloadData()
        }
    }

    private func addColumn(index: Int, column: InspectorJSONLColumn, to tableView: NSTableView) {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
        tableColumn.title = column.title
        tableColumn.width = column.width
        tableColumn.minWidth = column.minWidth
        if column.sortValue != nil {
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "\(index)", ascending: true)
        }
        tableView.addTableColumn(tableColumn)
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        var store: SVPInspectorJSONLStore
        var columns: [InspectorJSONLColumn]
        private var sortedRowIndexes: [Int]?

        init(store: SVPInspectorJSONLStore, columns: [InspectorJSONLColumn]) {
            self.store = store
            self.columns = columns
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            store.rowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
            let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
                ?? makeTextField(identifier: identifier)
            guard let columnIndex = Int(identifier.rawValue), columns.indices.contains(columnIndex) else {
                textField.stringValue = "—"
                return textField
            }

            textField.stringValue = columns[columnIndex].text(store, sourceRow(for: row))
            return textField
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            applySortDescriptors(tableView.sortDescriptors)
            tableView.reloadData()
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

        private func sourceRow(for visibleRow: Int) -> Int {
            sortedRowIndexes?[visibleRow] ?? visibleRow
        }

        func applySortDescriptors(_ descriptors: [NSSortDescriptor]) {
            guard let descriptor = descriptors.first,
                  let key = descriptor.key,
                  let columnIndex = Int(key),
                  columns.indices.contains(columnIndex),
                  let sortValue = columns[columnIndex].sortValue else {
                sortedRowIndexes = nil
                return
            }

            let ascending = descriptor.ascending
            sortedRowIndexes = (0..<store.rowCount)
                .map { (index: $0, value: sortValue(store, $0)) }
                .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.index < rhs.index
                    }
                    return ascending ? lhs.value < rhs.value : rhs.value < lhs.value
                }
                .map(\.index)
        }
    }
}

// MARK: - Provenance / Validation Detail View

struct ProvenanceDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

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

                if data.processors.rowCount > 0 {
                    section("Processors (\(data.processors.rowCount))") {
                        InspectorJSONLTableView(store: data.processors, columns: [
                            .text("ID", key: "id", width: 180),
                            .text("Name", key: "name", width: 150),
                            .text("Version", key: "version", width: 80)
                        ])
                        .frame(height: CGFloat(max(100, data.processors.rowCount * 25)))
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

                if data.validationReport == nil && data.build == nil && data.processors.rowCount == 0 {
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
