import SwiftUI

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
