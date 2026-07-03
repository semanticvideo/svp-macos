import AppKit
import SwiftUI

// MARK: - Reusable Views

struct LoadingStateView: View {
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            ProgressView()
                .controlSize(.regular)
            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct FailedStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.red)
            Text("Failed to load section")
                .font(.headline)
            Text(message)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry", action: retry)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

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
    case relationships
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
        case .relationships: "Relationships"
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
        case .relationships: "point.3.connected.trianglepath.dotted"
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
    private var viewModel: SVPInspectorViewModel?
    private var selectedSection = SVPInspectorSection.overview {
        didSet {
            viewModel?.loadSectionIfNeeded(selectedSection)
            updateDetail()
        }
    }
    private var sidebarHostingController: NSHostingController<SVPInspectorSidebarView>?
    private var detailHostingController: NSHostingController<AnyView>?
    private var isTornDown = false

    init(viewModel: SVPInspectorViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
        configureSplitView()
        viewModel.loadInitialData()
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
        guard let viewModel else { return }

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
                viewModel: viewModel
            )
        )
        let detailItem = NSSplitViewItem(viewController: detailHostingController)
        addSplitViewItem(detailItem)

        self.sidebarHostingController = sidebarHostingController
        self.detailHostingController = detailHostingController
    }

    private func updateDetail() {
        guard let viewModel, !isTornDown else { return }

        detailHostingController?.rootView = Self.detailView(
            for: selectedSection,
            viewModel: viewModel
        )
    }

    func tearDownForClose() {
        guard !isTornDown else { return }
        isTornDown = true

        sidebarHostingController?.rootView = SVPInspectorSidebarView(selectedSection: .constant(.overview))
        detailHostingController?.rootView = AnyView(EmptyView())
        viewModel = nil

        while !splitViewItems.isEmpty {
            removeSplitViewItem(splitViewItems[0])
        }

        sidebarHostingController = nil
        detailHostingController = nil
    }

    private static func detailView(
        for section: SVPInspectorSection,
        viewModel: SVPInspectorViewModel
    ) -> AnyView {
        switch section {
        case .overview:
            AnyView(OverviewDetailView(viewModel: viewModel))
        case .transcript:
            AnyView(TranscriptDetailView(viewModel: viewModel))
        case .ocr:
            AnyView(OCRDetailView(viewModel: viewModel))
        case .evidenceCrops:
            AnyView(EvidenceCropsDetailView(viewModel: viewModel))
        case .colors:
            AnyView(ColorsDetailView(viewModel: viewModel))
        case .scenes:
            AnyView(ScenesDetailView(viewModel: viewModel))
        case .entities:
            AnyView(EntitiesDetailView(viewModel: viewModel))
        case .relationships:
            AnyView(RelationshipsDetailView(viewModel: viewModel))
        case .provenance:
            AnyView(ProvenanceDetailView(viewModel: viewModel))
        case .index:
            AnyView(IndexDetailView(viewModel: viewModel))
        }
    }
}
