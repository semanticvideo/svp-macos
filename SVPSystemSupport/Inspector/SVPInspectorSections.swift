import AppKit
import SwiftUI

// MARK: - Reusable Views

struct EmptyStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Inspector Sections

enum SVPInspectorSection: String, CaseIterable, Identifiable {
    case overview
    case transcript
    case ocr
    case evidenceCrops
    case colors
    case scenes
    case entities
    case provenance
    case index

    var id: Self { self }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .transcript: "Transcript"
        case .ocr: "OCR / Text"
        case .evidenceCrops: "Evidence Crops"
        case .colors: "Colors"
        case .scenes: "Scenes / Timeline"
        case .entities: "Entities"
        case .provenance: "Provenance"
        case .index: "Index Summary"
        }
    }

    var symbolName: String {
        switch self {
        case .overview: "info.circle"
        case .transcript: "text.bubble"
        case .ocr: "text.magnifyingglass"
        case .evidenceCrops: "crop"
        case .colors: "paintpalette"
        case .scenes: "film"
        case .entities: "person.2"
        case .provenance: "checkmark.shield"
        case .index: "tablecells"
        }
    }
}

// MARK: - Sidebar View

struct SVPInspectorSidebarView: View {
    @Binding var selectedSection: SVPInspectorSection?

    var body: some View {
        List(SVPInspectorSection.allCases, selection: $selectedSection) { section in
            Label(section.title, systemImage: section.symbolName)
                .font(.system(.body, weight: .medium))
                .tag(section)
        }
        .scrollContentBackground(.hidden)
        .navigationTitle("SVP Inspector")
    }
}

// MARK: - Split View Controller

final class SVPInspectorSplitViewController: NSSplitViewController {
    private let data: SVPInspectorData
    private var selectedSection = SVPInspectorSection.overview {
        didSet {
            updateDetail()
        }
    }
    private var sidebarHostingController: NSHostingController<SVPInspectorSidebarView>?
    private var detailHostingController: NSHostingController<AnyView>?

    init(data: SVPInspectorData) {
        self.data = data
        super.init(nibName: nil, bundle: nil)
        configureSplitView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SVPInspectorSplitViewController does not support storyboards.")
    }

    private var selectionBinding: Binding<SVPInspectorSection?> {
        Binding {
            self.selectedSection
        } set: { selectedSection in
            self.selectedSection = selectedSection ?? .overview
        }
    }

    private func configureSplitView() {
        splitView.dividerStyle = .thin

        let sidebarHostingController = NSHostingController(
            rootView: SVPInspectorSidebarView(selectedSection: selectionBinding)
        )
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarHostingController)
        sidebarItem.minimumThickness = 180
        sidebarItem.maximumThickness = 280
        addSplitViewItem(sidebarItem)

        let detailHostingController = NSHostingController(
            rootView: Self.detailView(
                for: selectedSection,
                data: data
            )
        )
        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        addSplitViewItem(detailItem)

        self.sidebarHostingController = sidebarHostingController
        self.detailHostingController = detailHostingController
    }

    private func updateDetail() {
        detailHostingController?.rootView = Self.detailView(
            for: selectedSection,
            data: data
        )
    }

    private static func detailView(
        for section: SVPInspectorSection,
        data: SVPInspectorData
    ) -> AnyView {
        switch section {
        case .overview:
            AnyView(OverviewDetailView(data: data))
        case .transcript:
            AnyView(TranscriptDetailView(data: data))
        case .ocr:
            AnyView(OCRDetailView(data: data))
        case .evidenceCrops:
            AnyView(EvidenceCropsDetailView(data: data))
        case .colors:
            AnyView(ColorsDetailView(data: data))
        case .scenes:
            AnyView(ScenesDetailView(data: data))
        case .entities:
            AnyView(EntitiesDetailView(data: data))
        case .provenance:
            AnyView(ProvenanceDetailView(data: data))
        case .index:
            AnyView(IndexDetailView(data: data))
        }
    }
}

// MARK: - Error View

struct SVPInspectorErrorView: View {
    let error: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Failed to open SVP package")
                .font(.headline)
            Text(error)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
