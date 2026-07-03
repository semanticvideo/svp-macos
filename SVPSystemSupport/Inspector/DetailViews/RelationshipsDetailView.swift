import Foundation
import SwiftUI

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
