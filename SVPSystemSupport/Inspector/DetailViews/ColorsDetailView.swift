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
                ], defaultRowOrder: colorObservationAppearanceRowIndexes)
            }
        }
    }
}

func colorObservationAppearanceRowIndexes(for store: SVPInspectorJSONLStore) -> [Int] {
    (0..<store.rowCount).sorted { lhs, rhs in
        let lhsRow = store.row(at: lhs)
        let rhsRow = store.row(at: rhs)

        let lhsStart = colorObservationMicroseconds(lhsRow, key: "start_us")
        let rhsStart = colorObservationMicroseconds(rhsRow, key: "start_us")
        if lhsStart != rhsStart {
            return lhsStart < rhsStart
        }

        let lhsRank = colorObservationTargetRank(lhsRow?["target_type"] as? String)
        let rhsRank = colorObservationTargetRank(rhsRow?["target_type"] as? String)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank
        }

        let lhsEnd = colorObservationMicroseconds(lhsRow, key: "end_us")
        let rhsEnd = colorObservationMicroseconds(rhsRow, key: "end_us")
        if lhsEnd != rhsEnd {
            return lhsEnd < rhsEnd
        }

        let lhsID = lhsRow?["target_id"] as? String ?? ""
        let rhsID = rhsRow?["target_id"] as? String ?? ""
        if lhsID != rhsID {
            return lhsID < rhsID
        }

        return lhs < rhs
    }
}

private func colorObservationMicroseconds(_ row: [String: Any]?, key: String) -> Int64 {
    guard let number = row?[key] as? NSNumber else { return Int64.max }
    return number.int64Value
}

private func colorObservationTargetRank(_ targetType: String?) -> Int {
    switch targetType {
    case "scene": 0
    case "shot": 1
    case "frame": 2
    default: 3
    }
}
