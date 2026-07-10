import Combine
import Foundation
import SVPReader

final class SVPInspectorViewModel: ObservableObject {
    let fileURL: URL
    let formatLabel: String
    let package: SVPPackageDescriptor?

    @Published private(set) var overviewState: SVPInspectorLoadState<SVPInspectorOverviewData> = .idle
    @Published private(set) var transcriptState: SVPInspectorLoadState<SVPInspectorTranscriptData> = .idle
    @Published private(set) var textState: SVPInspectorLoadState<SVPInspectorTextData> = .idle
    @Published private(set) var evidenceCropsState: SVPInspectorLoadState<SVPInspectorEvidenceCropsData> = .idle
    @Published private(set) var colorsState: SVPInspectorLoadState<SVPInspectorColorsData> = .idle
    @Published private(set) var timelineState: SVPInspectorLoadState<SVPInspectorTimelineData> = .idle
    @Published private(set) var entitiesState: SVPInspectorLoadState<SVPInspectorEntitiesData> = .idle
    @Published private(set) var relationshipsState: SVPInspectorLoadState<SVPInspectorRelationshipsData> = .idle
    @Published private(set) var provenanceState: SVPInspectorLoadState<SVPInspectorProvenanceData> = .idle
    @Published private(set) var indexState: SVPInspectorLoadState<SVPInspectorIndexData> = .idle
    private var scheduledSections = Set<SVPInspectorSection>()

    init(fileURL: URL, formatLabel: String, package: SVPPackageDescriptor? = nil) {
        self.fileURL = fileURL
        self.formatLabel = formatLabel
        self.package = package
    }

    var windowTitle: String {
        "\(fileURL.deletingPathExtension().lastPathComponent) — \(formatLabel) Inspector"
    }

    func loadInitialData() {
        loadOverviewIfNeeded()
    }

    func loadSectionIfNeeded(_ section: SVPInspectorSection) {
        guard isSectionIdle(section), !scheduledSections.contains(section) else { return }
        scheduledSections.insert(section)

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            scheduledSections.remove(section)
            startLoadingSectionIfNeeded(section)
        }
    }

    private func startLoadingSectionIfNeeded(_ section: SVPInspectorSection) {
        switch section {
        case .overview:
            loadOverviewIfNeeded()
        case .transcript:
            loadTranscriptIfNeeded()
        case .ocr:
            loadTextIfNeeded()
        case .evidenceCrops:
            loadEvidenceCropsIfNeeded()
        case .colors:
            loadColorsIfNeeded()
        case .scenes:
            loadTimelineIfNeeded()
        case .entities:
            loadEntitiesIfNeeded()
        case .relationships:
            loadRelationshipsIfNeeded()
        case .provenance:
            loadProvenanceIfNeeded()
        case .index:
            loadIndexIfNeeded()
        }
    }

    func retrySection(_ section: SVPInspectorSection) {
        resetSection(section)
        loadSectionIfNeeded(section)
    }

    private func loadOverviewIfNeeded() {
        guard case .idle = overviewState else { return }
        overviewState = .loading
        load(
            sectionName: "overview",
            work: { try SVPInspectorDataLoader.loadOverview(from: self.fileURL, package: self.package) },
            assign: { self.overviewState = $0 }
        )
    }

    private func loadTranscriptIfNeeded() {
        guard case .idle = transcriptState else { return }
        transcriptState = .loading
        load(
            sectionName: "transcript",
            work: { try SVPInspectorDataLoader.loadTranscript(from: self.fileURL, package: self.package) },
            assign: { self.transcriptState = $0 }
        )
    }

    private func loadTextIfNeeded() {
        guard case .idle = textState else { return }
        textState = .loading
        load(
            sectionName: "text",
            work: { try SVPInspectorDataLoader.loadText(from: self.fileURL, package: self.package) },
            assign: { self.textState = $0 }
        )
    }

    private func loadEvidenceCropsIfNeeded() {
        guard case .idle = evidenceCropsState else { return }
        evidenceCropsState = .loading
        load(
            sectionName: "evidence crops",
            work: { try SVPInspectorDataLoader.loadEvidenceCrops(from: self.fileURL, package: self.package) },
            assign: { self.evidenceCropsState = $0 }
        )
    }

    private func loadColorsIfNeeded() {
        guard case .idle = colorsState else { return }
        colorsState = .loading
        load(
            sectionName: "colors",
            work: { try SVPInspectorDataLoader.loadColors(from: self.fileURL, package: self.package) },
            assign: { self.colorsState = $0 }
        )
    }

    private func loadTimelineIfNeeded() {
        guard case .idle = timelineState else { return }
        timelineState = .loading
        load(
            sectionName: "timeline",
            work: { try SVPInspectorDataLoader.loadTimeline(from: self.fileURL, package: self.package) },
            assign: { self.timelineState = $0 }
        )
    }

    private func loadEntitiesIfNeeded() {
        guard case .idle = entitiesState else { return }
        entitiesState = .loading
        load(
            sectionName: "entities",
            work: { try SVPInspectorDataLoader.loadEntities(from: self.fileURL, package: self.package) },
            assign: { self.entitiesState = $0 }
        )
    }

    private func loadRelationshipsIfNeeded() {
        guard case .idle = relationshipsState else { return }
        relationshipsState = .loading
        load(
            sectionName: "relationships",
            work: { try SVPInspectorDataLoader.loadRelationships(from: self.fileURL, package: self.package) },
            assign: { self.relationshipsState = $0 }
        )
    }

    private func loadProvenanceIfNeeded() {
        guard case .idle = provenanceState else { return }
        provenanceState = .loading
        load(
            sectionName: "provenance",
            work: { try SVPInspectorDataLoader.loadProvenance(from: self.fileURL, package: self.package) },
            assign: { self.provenanceState = $0 }
        )
    }

    private func loadIndexIfNeeded() {
        guard case .idle = indexState else { return }
        indexState = .loading
        load(
            sectionName: "index",
            work: { try SVPInspectorDataLoader.loadIndex(from: self.fileURL, package: self.package) },
            assign: { self.indexState = $0 }
        )
    }

    private func resetSection(_ section: SVPInspectorSection) {
        scheduledSections.remove(section)
        switch section {
        case .overview:
            overviewState = .idle
        case .transcript:
            transcriptState = .idle
        case .ocr:
            textState = .idle
        case .evidenceCrops:
            evidenceCropsState = .idle
        case .colors:
            colorsState = .idle
        case .scenes:
            timelineState = .idle
        case .entities:
            entitiesState = .idle
        case .relationships:
            relationshipsState = .idle
        case .provenance:
            provenanceState = .idle
        case .index:
            indexState = .idle
        }
    }

    private func isSectionIdle(_ section: SVPInspectorSection) -> Bool {
        switch section {
        case .overview:
            if case .idle = overviewState { true } else { false }
        case .transcript:
            if case .idle = transcriptState { true } else { false }
        case .ocr:
            if case .idle = textState { true } else { false }
        case .evidenceCrops:
            if case .idle = evidenceCropsState { true } else { false }
        case .colors:
            if case .idle = colorsState { true } else { false }
        case .scenes:
            if case .idle = timelineState { true } else { false }
        case .entities:
            if case .idle = entitiesState { true } else { false }
        case .relationships:
            if case .idle = relationshipsState { true } else { false }
        case .provenance:
            if case .idle = provenanceState { true } else { false }
        case .index:
            if case .idle = indexState { true } else { false }
        }
    }

    private func load<Value>(
        sectionName: String,
        work: @escaping () throws -> Value,
        assign: @escaping (SVPInspectorLoadState<Value>) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async {
            let result: SVPInspectorLoadState<Value>
            do {
                result = .loaded(try work())
            } catch {
                SVPAppLogger.log("Inspector \(sectionName) load failed: \(error)")
                result = .failed(String(describing: error))
            }

            DispatchQueue.main.async {
                assign(result)
            }
        }
    }
}
