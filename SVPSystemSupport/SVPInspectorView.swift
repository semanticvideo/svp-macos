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

private struct InspectorRow: Identifiable {
    let id: Int
    let dict: [String: Any]
}

private func makeRows(_ array: [[String: Any]]) -> [InspectorRow] {
    array.enumerated().map { InspectorRow(id: $0.offset, dict: $0.element) }
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

// MARK: - Main Inspector View

struct SVPInspectorView: View {
    let data: SVPInspectorData

    var body: some View {
        if let error = data.loadError {
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
        } else {
            TabView {
                OverviewTab(data: data)
                    .tabItem { Label("Overview", systemImage: "info.circle") }

                TranscriptTab(data: data)
                    .tabItem { Label("Transcript", systemImage: "text.bubble") }

                OCRTab(data: data)
                    .tabItem { Label("OCR / Text", systemImage: "text.magnifyingglass") }

                EvidenceCropsTab(data: data)
                    .tabItem { Label("Evidence Crops", systemImage: "crop") }

                ColorsTab(data: data)
                    .tabItem { Label("Colors", systemImage: "paintpalette") }

                ScenesTab(data: data)
                    .tabItem { Label("Scenes / Timeline", systemImage: "film") }

                EntitiesTab(data: data)
                    .tabItem { Label("Entities", systemImage: "person.2") }

                ProvenanceTab(data: data)
                    .tabItem { Label("Provenance / Validation", systemImage: "checkmark.shield") }

                IndexTab(data: data)
                    .tabItem { Label("Index Summary", systemImage: "tablecells") }
            }
            .padding()
        }
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

                let rows = makeRows(data.transcriptWords)
                Table(rows) {
                    TableColumn("Text") { row in
                        Text(displayString(row.dict, "text"))
                            .textSelection(.enabled)
                    }
                    .width(min: 80, ideal: 200)
                    TableColumn("Start (s)") { row in
                        Text(formatMicroseconds(row.dict, "start_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("End (s)") { row in
                        Text(formatMicroseconds(row.dict, "end_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Speaker") { row in
                        Text(displayString(row.dict, "speaker_id"))
                    }
                    .width(min: 80, ideal: 120)
                    TableColumn("Confidence") { row in
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

                let rows = makeRows(data.textObservations)
                Table(rows) {
                    TableColumn("Raw Text") { row in
                        Text(displayString(row.dict, "raw_text"))
                            .textSelection(.enabled)
                    }
                    .width(min: 80, ideal: 200)
                    TableColumn("Normalized") { row in
                        Text(displayString(row.dict, "normalized_text"))
                    }
                    .width(min: 80, ideal: 150)
                    TableColumn("Start (s)") { row in
                        Text(formatMicroseconds(row.dict, "start_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Confidence") { row in
                        Text(displayString(row.dict, "confidence"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Region ID") { row in
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

    var body: some View {
        if data.evidenceCrops.isEmpty {
            EmptyStateView(message: "No evidence crops found in this package.")
        } else {
            let rows = makeRows(data.evidenceCrops)
            Table(rows) {
                TableColumn("ID") { row in
                    Text(displayString(row.dict, "id"))
                }
                .width(min: 80, ideal: 160)
                TableColumn("Start (s)") { row in
                    Text(formatMicroseconds(row.dict, "start_us"))
                }
                .width(min: 60, ideal: 80)
                TableColumn("Text Region") { row in
                    Text(displayString(row.dict, "text_region_id"))
                }
                .width(min: 80, ideal: 140)
                TableColumn("Image Ref") { row in
                    Text(displayString(row.dict, "image_ref"))
                }
                .width(min: 80, ideal: 200)
            }
        }
    }
}

// MARK: - Colors Tab

private struct ColorsTab: View {
    let data: SVPInspectorData

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

                let rows = makeRows(data.colorObservations)
                Table(rows) {
                    TableColumn("Target Type") { row in
                        Text(displayString(row.dict, "target_type"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Target ID") { row in
                        Text(displayString(row.dict, "target_id"))
                    }
                    .width(min: 80, ideal: 140)
                    TableColumn("Start (s)") { row in
                        Text(formatMicroseconds(row.dict, "start_us"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Dominant") { row in
                        Text(displayString(row.dict, "dominant_bucket"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Coverage") { row in
                        Text(displayString(row.dict, "coverage_total"))
                    }
                    .width(min: 60, ideal: 80)
                    TableColumn("Quality") { row in
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

    var body: some View {
        if data.scenes.isEmpty && data.shots.isEmpty {
            EmptyStateView(message: "No scenes or shots found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 12) {
                if !data.scenes.isEmpty {
                    Text("Scenes (\(data.scenes.count))")
                        .font(.headline)

                    let sceneRows = makeRows(data.scenes)
                    Table(sceneRows) {
                        TableColumn("ID") { row in
                            Text(displayString(row.dict, "id"))
                        }
                        .width(min: 80, ideal: 140)
                        TableColumn("Start (s)") { row in
                            Text(formatMicroseconds(row.dict, "start_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("End (s)") { row in
                            Text(formatMicroseconds(row.dict, "end_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("Shots") { row in
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

                    let shotRows = makeRows(data.shots)
                    Table(shotRows) {
                        TableColumn("ID") { row in
                            Text(displayString(row.dict, "id"))
                        }
                        .width(min: 80, ideal: 140)
                        TableColumn("Start (s)") { row in
                            Text(formatMicroseconds(row.dict, "start_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("End (s)") { row in
                            Text(formatMicroseconds(row.dict, "end_us"))
                        }
                        .width(min: 60, ideal: 80)
                        TableColumn("Cut In") { row in
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

                let rows = makeRows(data.entities)
                Table(rows) {
                    TableColumn("ID") { row in
                        Text(displayString(row.dict, "id"))
                    }
                    .width(min: 80, ideal: 140)
                    TableColumn("Type") { row in
                        Text(displayString(row.dict, "entity_type"))
                    }
                    .width(min: 60, ideal: 120)
                    TableColumn("First Seen (s)") { row in
                        Text(formatMicroseconds(row.dict, "first_seen_us"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Last Seen (s)") { row in
                        Text(formatMicroseconds(row.dict, "last_seen_us"))
                    }
                    .width(min: 60, ideal: 100)
                    TableColumn("Avg Visibility") { row in
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
                        let procRows = makeRows(data.provenanceProcessors)
                        Table(procRows) {
                            TableColumn("ID") { row in
                                Text(displayString(row.dict, "id"))
                            }
                            .width(min: 80, ideal: 180)
                            TableColumn("Name") { row in
                                Text(displayString(row.dict, "name"))
                            }
                            .width(min: 60, ideal: 150)
                            TableColumn("Version") { row in
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
