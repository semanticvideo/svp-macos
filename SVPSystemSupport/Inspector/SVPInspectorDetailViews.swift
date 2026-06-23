import SwiftUI
import SVPReader

// MARK: - Overview Detail View

struct OverviewDetailView: View {
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

// MARK: - Transcript Detail View

struct TranscriptDetailView: View {
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

// MARK: - OCR / Text Detail View

struct OCRDetailView: View {
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

// MARK: - Colors Detail View

struct ColorsDetailView: View {
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

// MARK: - Scenes / Timeline Detail View

struct ScenesDetailView: View {
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

// MARK: - Entities Detail View

struct EntitiesDetailView: View {
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

// MARK: - Provenance / Validation Detail View

struct ProvenanceDetailView: View {
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

// MARK: - Index Summary Detail View

struct IndexDetailView: View {
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
