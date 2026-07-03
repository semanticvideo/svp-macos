import SwiftUI

struct TranscriptDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

    var body: some View {
        switch viewModel.transcriptState {
        case .idle, .loading:
            LoadingStateView(message: "Loading transcript...")
                .onAppear { viewModel.loadSectionIfNeeded(.transcript) }
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.transcript)
            }
        case .loaded(let data):
            transcriptContent(data)
        }
    }

    @ViewBuilder
    private func transcriptContent(_ data: SVPInspectorTranscriptData) -> some View {
        if data.words.rowCount == 0 && data.summary == nil {
            EmptyStateView(message: "No transcript data found in this package.")
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let ts = data.summary {
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

                InspectorJSONLTableView(store: data.words, columns: [
                    .text("Text", key: "text", width: 200),
                    .microseconds("Start (s)", key: "start_us", width: 80),
                    .microseconds("End (s)", key: "end_us", width: 80),
                    .text("Speaker", key: "speaker_id", width: 120),
                    .text("Confidence", key: "confidence", width: 80)
                ])
            }
        }
    }
}
