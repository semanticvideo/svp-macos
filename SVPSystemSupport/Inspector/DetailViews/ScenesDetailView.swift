import SwiftUI

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
