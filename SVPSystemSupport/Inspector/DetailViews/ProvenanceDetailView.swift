import SwiftUI

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
