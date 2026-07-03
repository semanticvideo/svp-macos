import SwiftUI
import SVPReader

struct OverviewDetailView: View {
    @ObservedObject var viewModel: SVPInspectorViewModel

    var body: some View {
        switch viewModel.overviewState {
        case .idle, .loading:
            LoadingStateView(message: "Loading overview...")
        case .failed(let message):
            FailedStateView(message: message) {
                viewModel.retrySection(.overview)
            }
        case .loaded(let data):
            overviewContent(data)
        }
    }

    @ViewBuilder
    private func overviewContent(_ data: SVPInspectorOverviewData) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                section("Package") {
                    infoRow("File", data.fileURL.lastPathComponent)
                    infoRow("Path", data.fileURL.path)
                    if let m = data.manifest {
                        infoRow("SVP Version", m.svpVersion)
                        infoRow("Package ID", m.packageID)
                        infoRow("Created UTC", m.createdUTC)
                        infoRow("Primary Media ID", m.primaryMediaID)
                        infoRow("Timebase Unit", m.timebaseUnit)
                        infoRow("Timebase Origin", m.timebaseOrigin)
                    }
                    if let mi = data.mediaInfo {
                        infoRow("Media File", mi.mediaFileName)
                        infoRow("Media Size", "\(mi.uncompressedSize) bytes")
                        infoRow("Compressed", mi.isCompressed ? "Yes" : "No")
                    }
                    infoRow("Media Files", "\(data.mediaEntryCount)")
                }

                section("Section Counts") {
                    infoRow("Total Entries", "\(data.allEntries.count)")
                    infoRow("Transcript", "\(data.entryCounts[.transcript] ?? 0)")
                    infoRow("OCR / Text", "\(data.entryCounts[.ocr] ?? 0)")
                    infoRow("Evidence Crops", "\(data.entryCounts[.evidenceCrops] ?? 0)")
                    infoRow("Colors", "\(data.entryCounts[.colors] ?? 0)")
                    infoRow("Scenes / Timeline", "\(data.entryCounts[.scenes] ?? 0)")
                    infoRow("Entities", "\(data.entryCounts[.entities] ?? 0)")
                    infoRow("Relationships", "\(data.entryCounts[.relationships] ?? 0)")
                    infoRow("Provenance", "\(data.entryCounts[.provenance] ?? 0)")
                    infoRow("Index Summary", "\(data.entryCounts[.index] ?? 0)")
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
