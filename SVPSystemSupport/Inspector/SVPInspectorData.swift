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
    let words: [[String: Any]]
    let summary: [String: Any]?
    let speakers: [[String: Any]]
    let speakerSegments: [[String: Any]]
}

struct SVPInspectorTextData {
    let regions: [[String: Any]]
    let observations: [[String: Any]]
    let numericValues: [[String: Any]]
    let absence: [String: Any]?
}

struct SVPInspectorEvidenceCropsData {
    let fileURL: URL
    let crops: [[String: Any]]
}

struct SVPInspectorColorsData {
    let observations: [[String: Any]]
    let summary: [String: Any]?
    let absence: [String: Any]?
}

struct SVPInspectorTimelineData {
    let shots: [[String: Any]]
    let scenes: [[String: Any]]
    let frames: [[String: Any]]
}

struct SVPInspectorEntitiesData {
    let entities: [[String: Any]]
    let entityTracks: [[String: Any]]
}

struct SVPInspectorRelationshipsData {
    let relationships: [[String: Any]]
}

struct SVPInspectorProvenanceData {
    let build: [String: Any]?
    let processors: [[String: Any]]
    let validationReport: [String: Any]?
}

struct SVPInspectorIndexData {
    let allEntries: [String]
    let manifest: [String: Any]?
    let hasIndex: Bool
}

enum SVPInspectorDataLoader {
    nonisolated static func loadOverview(from url: URL) throws -> SVPInspectorOverviewData {
        try timed("overview") {
            let reader = try validatedReader(for: url)
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

    nonisolated static func loadTranscript(from url: URL) throws -> SVPInspectorTranscriptData {
        try timed("transcript section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorTranscriptData(
                words: readJSONL("transcript/words.jsonl", from: reader),
                summary: readJSON("transcript/transcript.json", from: reader),
                speakers: readJSONL("transcript/speakers.jsonl", from: reader),
                speakerSegments: readJSONL("transcript/speaker_segments.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadText(from url: URL) throws -> SVPInspectorTextData {
        try timed("text section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorTextData(
                regions: readJSONL("text/text_regions.jsonl", from: reader),
                observations: readJSONL("text/text_observations.jsonl", from: reader),
                numericValues: readJSONL("text/numeric_values.jsonl", from: reader),
                absence: readJSON("text/text_absence.json", from: reader)
            )
        }
    }

    nonisolated static func loadEvidenceCrops(from url: URL) throws -> SVPInspectorEvidenceCropsData {
        try timed("evidence crops section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorEvidenceCropsData(
                fileURL: url,
                crops: readJSONL("text/evidence_crops.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadEvidenceCropImage(packageURL: URL, cropFilePath: String) throws -> Data? {
        try timed("evidence crop image \(cropFilePath)") {
            let reader = try validatedReader(for: packageURL)
            guard reader.hasEntry(cropFilePath) else { return nil }
            return try reader.readEntryData(cropFilePath)
        }
    }

    nonisolated static func loadColors(from url: URL) throws -> SVPInspectorColorsData {
        try timed("colors section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorColorsData(
                observations: readJSONL("colors/color_observations.jsonl", from: reader),
                summary: readJSON("colors/color_summary.json", from: reader),
                absence: readJSON("colors/color_absence.json", from: reader)
            )
        }
    }

    nonisolated static func loadTimeline(from url: URL) throws -> SVPInspectorTimelineData {
        try timed("timeline section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorTimelineData(
                shots: readJSONL("timeline/shots.jsonl", from: reader),
                scenes: readJSONL("timeline/scenes.jsonl", from: reader),
                frames: readJSONL("timeline/frames.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadEntities(from url: URL) throws -> SVPInspectorEntitiesData {
        try timed("entities section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorEntitiesData(
                entities: readJSONL("entities/entities.jsonl", from: reader),
                entityTracks: readJSONL("entities/entity_tracks.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadRelationships(from url: URL) throws -> SVPInspectorRelationshipsData {
        try timed("relationships section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorRelationshipsData(
                relationships: readJSONL("relationships/relationships.jsonl", from: reader)
            )
        }
    }

    nonisolated static func loadProvenance(from url: URL) throws -> SVPInspectorProvenanceData {
        try timed("provenance section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorProvenanceData(
                build: readJSON("provenance/build.json", from: reader),
                processors: readJSONL("provenance/processors.jsonl", from: reader),
                validationReport: readJSON("provenance/validation.json", from: reader)
            )
        }
    }

    nonisolated static func loadIndex(from url: URL) throws -> SVPInspectorIndexData {
        try timed("index section") {
            let reader = try validatedReader(for: url)
            return SVPInspectorIndexData(
                allEntries: reader.allEntryNames,
                manifest: readJSON("index/index_manifest.json", from: reader),
                hasIndex: reader.hasEntry("index/index.sqlite")
            )
        }
    }

    private nonisolated static func validatedReader(for url: URL) throws -> SVPReader {
        let reader = try SVPReader(url: url)
        try reader.validateSVP()
        return reader
    }

    private nonisolated static func readJSONL(_ entryName: String, from reader: SVPReader) -> [[String: Any]] {
        guard reader.hasEntry(entryName) else { return [] }
        return (try? reader.readJSONLEntry(entryName)) ?? []
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
