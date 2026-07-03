import SwiftUI

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
                    .colorBuckets("Breakdown", key: "bucket_coverage", width: 160),
                    .text("Coverage", key: "coverage_total", width: 80),
                    .text("Quality", key: "quality_score", width: 70)
                ])
            }
        }
    }
}
