import SwiftUI

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
