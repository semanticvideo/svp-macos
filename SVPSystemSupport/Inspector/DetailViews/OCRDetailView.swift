import SwiftUI

struct OCRDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

    var body: some View {
        switch viewModel.textState {
        case .idle, .loading:
            LoadingStateView(message: "Loading OCR / text...")
                .onAppear { viewModel.loadSectionIfNeeded(.ocr) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.ocr)
            }
        case .loaded(let data):
            ocrContent(data)
        }
    }

    @ViewBuilder
    private func ocrContent(_ data: SVPInspectorTextData) -> some View {
        if data.observations.rowCount == 0 && data.regions.rowCount == 0 {
            if let absence = data.absence {
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
                    Label("\(data.regions.rowCount) regions", systemImage: "rectangle.dashed")
                    Label("\(data.observations.rowCount) observations", systemImage: "text.magnifyingglass")
                    Label("\(data.numericValues.rowCount) numeric values", systemImage: "number")
                }
                .font(.caption)
                .padding(.horizontal, 4)

                InspectorJSONLTableView(store: data.observations, columns: [
                    .text("Raw Text", key: "raw_text", width: 200),
                    .text("Normalized", key: "normalized_text", width: 150),
                    .microseconds("Start (s)", key: "start_us", width: 80),
                    .text("Confidence", key: "confidence", width: 80),
                    .text("Region ID", key: "text_region_id", width: 140)
                ])
            }
        }
    }
}
