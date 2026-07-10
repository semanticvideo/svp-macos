import Foundation
import SVPReader

enum SVPInspectorLoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(String)
}

struct SVPInspectorOverviewData {
    let fileURL: URL
    let manifest: SVPManifestInfo?
    let mediaInfo: SVPMediaInfo?
    let mediaEntryCount: Int
    let allEntries: [String]
    let entryCounts: [SVPInspectorSection: Int]
}

struct SVPInspectorTranscriptData {
    let words: SVPInspectorJSONLStore
    let summary: [String: Any]?
    let speakers: SVPInspectorJSONLStore
    let speakerSegments: SVPInspectorJSONLStore
}

struct SVPInspectorTextData {
    let regions: SVPInspectorJSONLStore
    let observations: SVPInspectorJSONLStore
    let numericValues: SVPInspectorJSONLStore
    let absence: [String: Any]?
}

struct SVPInspectorEvidenceCropsData {
    let fileURL: URL
    let package: SVPPackageDescriptor?
    let crops: [[String: Any]]
}

struct SVPInspectorColorsData {
    let observations: SVPInspectorJSONLStore
    let summary: [String: Any]?
    let absence: [String: Any]?
}

struct SVPInspectorTimelineData {
    let shots: SVPInspectorJSONLStore
    let scenes: SVPInspectorJSONLStore
    let frames: SVPInspectorJSONLStore
}

struct SVPInspectorEntitiesData {
    let entities: SVPInspectorJSONLStore
    let entityTracks: SVPInspectorJSONLStore
}

struct SVPInspectorRelationshipsData {
    let store: SVPInspectorJSONLStore
}

struct SVPInspectorProvenanceData {
    let build: [String: Any]?
    let processors: SVPInspectorJSONLStore
    let validationReport: [String: Any]?
}

struct SVPInspectorIndexData {
    let allEntries: [String]
    let manifest: [String: Any]?
    let hasIndex: Bool
}

enum SVPInspectorDataLoader {
    nonisolated static func loadOverview(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorOverviewData {
        try timed("overview") {
            let reader = try validatedReader(for: url, package: package)
            let allEntries = reader.allEntryNames
            let manifest = try? reader.readManifest()
            let mediaInfo = try? reader.locatePrimaryMediaAsset()
            let mediaEntryCount = allEntries.filter { $0.hasPrefix("media/original/") && !$0.hasSuffix("/") }.count

            return SVPInspectorOverviewData(
                fileURL: url,
                manifest: manifest,
                mediaInfo: mediaInfo,
                mediaEntryCount: mediaEntryCount,
                allEntries: allEntries,
                entryCounts: entryCounts(from: allEntries)
            )
        }
    }

    nonisolated static func loadTranscript(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorTranscriptData {
        try timed("transcript section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorTranscriptData(
                words: try readJSONLStore("transcript/words.jsonl", from: reader),
                summary: readJSON("transcript/transcript.json", from: reader),
                speakers: try readJSONLStore("transcript/speakers.jsonl", from: reader),
                speakerSegments: try readJSONLStore("transcript/speaker_segments.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadText(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorTextData {
        try timed("text section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorTextData(
                regions: try readJSONLStore("text/text_regions.jsonl", from: reader),
                observations: try readJSONLStore("text/text_observations.jsonl", from: reader),
                numericValues: try readJSONLStore("text/numeric_values.jsonl", from: reader),
                absence: readJSON("text/text_absence.json", from: reader)
            )
        }
    }

    nonisolated static func loadEvidenceCrops(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorEvidenceCropsData {
        try timed("evidence crops section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorEvidenceCropsData(
                fileURL: url,
                package: package,
                crops: readJSONL("text/evidence_crops.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadEvidenceCropImage(packageURL: URL, package: SVPPackageDescriptor? = nil, cropFilePath: String) throws -> Data? {
        try timed("evidence crop image \(cropFilePath)") {
            let reader = try validatedReader(for: packageURL, package: package)
            guard reader.hasEntry(cropFilePath) else { return nil }
            return try reader.readEntryData(cropFilePath)
        }
    }

    nonisolated static func loadColors(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorColorsData {
        try timed("colors section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorColorsData(
                observations: try readJSONLStore("colors/color_observations.jsonl", from: reader),
                summary: readJSON("colors/color_summary.json", from: reader),
                absence: readJSON("colors/color_absence.json", from: reader)
            )
        }
    }

    nonisolated static func loadTimeline(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorTimelineData {
        try timed("timeline section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorTimelineData(
                shots: try readJSONLStore("timeline/shots.jsonl", from: reader),
                scenes: try readJSONLStore("timeline/scenes.jsonl", from: reader),
                frames: try readJSONLStore("timeline/frames.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadEntities(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorEntitiesData {
        try timed("entities section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorEntitiesData(
                entities: try readJSONLStore("entities/entities.jsonl", from: reader),
                entityTracks: try readJSONLStore("entities/entity_tracks.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadRelationships(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorRelationshipsData {
        try timed("relationships section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorRelationshipsData(
                store: try readJSONLStore("relationships/relationships.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadProvenance(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorProvenanceData {
        try timed("provenance section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorProvenanceData(
                build: readJSON("provenance/build.json", from: reader),
                processors: try readJSONLStore("provenance/processors.jsonl", from: reader),
                validationReport: readJSON("provenance/validation.json", from: reader)
            )
        }
    }

    nonisolated static func loadIndex(from url: URL, package: SVPPackageDescriptor? = nil) throws -> SVPInspectorIndexData {
        try timed("index section") {
            let reader = try validatedReader(for: url, package: package)
            return SVPInspectorIndexData(
                allEntries: reader.allEntryNames,
                manifest: readJSON("index/index_manifest.json", from: reader),
                hasIndex: reader.hasEntry("index/index.sqlite")
            )
        }
    }

    private nonisolated static func validatedReader(for url: URL, package: SVPPackageDescriptor?) throws -> SVPReader {
        let reader: SVPReader
        if let package { reader = try SVPReader(package: package) }
        else { reader = try SVPReader(url: url) }
        try reader.validateSVP()
        return reader
    }

    private nonisolated static func readJSONL(_ entryName: String, from reader: SVPReader) -> [[String: Any]] {
        guard reader.hasEntry(entryName) else { return [] }
        return (try? reader.readJSONLEntry(entryName)) ?? []
    }

    private nonisolated static func readJSONLStore(_ entryName: String, from reader: SVPReader) throws -> SVPInspectorJSONLStore {
        try SVPInspectorJSONLStore(reader: reader, entryName: entryName)
    }

    private nonisolated static func readJSON(_ entryName: String, from reader: SVPReader) -> [String: Any]? {
        guard reader.hasEntry(entryName) else { return nil }
        return try? reader.readJSONEntry(entryName)
    }

    private nonisolated static func entryCounts(from allEntries: [String]) -> [SVPInspectorSection: Int] {
        [
            .transcript: countEntries(allEntries, prefixes: ["transcript/"], suffixes: [".jsonl", ".json"]),
            .ocr: countEntries(allEntries, prefixes: ["text/"], suffixes: [".jsonl", ".json"]),
            .evidenceCrops: countEntries(allEntries, prefixes: ["text/evidence_crops/"], suffixes: [".jpg", ".jpeg", ".png"]),
            .colors: countEntries(allEntries, prefixes: ["colors/"], suffixes: [".jsonl", ".json"]),
            .scenes: countEntries(allEntries, prefixes: ["timeline/"], suffixes: [".jsonl", ".json"]),
            .entities: countEntries(allEntries, prefixes: ["entities/"], suffixes: [".jsonl", ".json"]),
            .relationships: countEntries(allEntries, prefixes: ["relationships/"], suffixes: [".jsonl", ".json"]),
            .provenance: countEntries(allEntries, prefixes: ["provenance/"], suffixes: [".jsonl", ".json"]),
            .index: countEntries(allEntries, prefixes: ["index/"], suffixes: [".sqlite", ".json"])
        ]
    }

    private nonisolated static func countEntries(
        _ entries: [String],
        prefixes: [String],
        suffixes: [String]
    ) -> Int {
        entries.filter { entry in
            prefixes.contains { entry.hasPrefix($0) }
                && suffixes.contains { entry.lowercased().hasSuffix($0) }
        }.count
    }

    private nonisolated static func timed<Value>(_ label: String, _ work: () throws -> Value) throws -> Value {
        let start = Date()
        SVPAppLogger.log("Inspector loading \(label) started")
        do {
            let value = try work()
            let elapsed = Date().timeIntervalSince(start)
            SVPAppLogger.log(String(format: "Inspector loading %@ finished in %.3fs", label, elapsed))
            return value
        } catch {
            let elapsed = Date().timeIntervalSince(start)
            SVPAppLogger.log(String(format: "Inspector loading %@ failed in %.3fs: %@", label, elapsed, String(describing: error)))
            throw error
        }
    }
}
