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
    colorObservationAppearanceRowIndexes(rowCount: store.rowCount, rowAt: store.row)
}

func colorObservationAppearanceRowIndexes(
    rowCount: Int,
    rowAt: (Int) -> [String: Any]?
) -> [Int] {
    (0..<rowCount)
        .map { rowIndex in
            let row = rowAt(rowIndex)
            return ColorObservationAppearanceKey(
                rowIndex: rowIndex,
                startUS: colorObservationMicroseconds(row, key: "start_us"),
                targetRank: colorObservationTargetRank(row?["target_type"] as? String),
                endUS: colorObservationMicroseconds(row, key: "end_us"),
                targetID: row?["target_id"] as? String ?? ""
            )
        }
        .sorted()
        .map(\.rowIndex)
}

private struct ColorObservationAppearanceKey: Comparable {
    let rowIndex: Int
    let startUS: Int64
    let targetRank: Int
    let endUS: Int64
    let targetID: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        if lhs.startUS != rhs.startUS { return lhs.startUS < rhs.startUS }
        if lhs.targetRank != rhs.targetRank { return lhs.targetRank < rhs.targetRank }
        if lhs.endUS != rhs.endUS { return lhs.endUS < rhs.endUS }
        if lhs.targetID != rhs.targetID { return lhs.targetID < rhs.targetID }
        return lhs.rowIndex < rhs.rowIndex
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
