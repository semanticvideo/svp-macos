import Foundation
import SVPReader

struct SVPInspectorData {
    let fileURL: URL
    let manifest: SVPManifestInfo?
    let mediaInfo: SVPMediaInfo?
    let mediaEntryCount: Int
    let allEntries: [String]

    let transcriptWords: [[String: Any]]
    let transcriptSummary: [String: Any]?
    let speakers: [[String: Any]]
    let speakerSegments: [[String: Any]]

    let textRegions: [[String: Any]]
    let textObservations: [[String: Any]]
    let numericValues: [[String: Any]]
    let textAbsence: [String: Any]?
    let evidenceCrops: [[String: Any]]
    let evidenceCropImages: [String: Data]

    let colorObservations: [[String: Any]]
    let colorSummary: [String: Any]?
    let colorAbsence: [String: Any]?

    let shots: [[String: Any]]
    let scenes: [[String: Any]]
    let frames: [[String: Any]]

    let entities: [[String: Any]]
    let entityTracks: [[String: Any]]

    let relationships: [[String: Any]]

    let provenanceBuild: [String: Any]?
    let provenanceProcessors: [[String: Any]]
    let validationReport: [String: Any]?

    let indexManifest: [String: Any]?
    let hasIndex: Bool

    let loadError: String?

    static func load(from url: URL) -> SVPInspectorData {
        SVPAppLogger.log("Inspector loading data from: \(url.path)")

        var manifest: SVPManifestInfo?
        var mediaInfo: SVPMediaInfo?
        var mediaEntryCount = 0
        var allEntries: [String] = []
        var loadError: String?

        var transcriptWords: [[String: Any]] = []
        var transcriptSummary: [String: Any]?
        var speakers: [[String: Any]] = []
        var speakerSegments: [[String: Any]] = []

        var textRegions: [[String: Any]] = []
        var textObservations: [[String: Any]] = []
        var numericValues: [[String: Any]] = []
        var textAbsence: [String: Any]?
        var evidenceCrops: [[String: Any]] = []
        var evidenceCropImages: [String: Data] = [:]

        var colorObservations: [[String: Any]] = []
        var colorSummary: [String: Any]?
        var colorAbsence: [String: Any]?

        var shots: [[String: Any]] = []
        var scenes: [[String: Any]] = []
        var frames: [[String: Any]] = []

        var entities: [[String: Any]] = []
        var entityTracks: [[String: Any]] = []

        var relationships: [[String: Any]] = []

        var provenanceBuild: [String: Any]?
        var provenanceProcessors: [[String: Any]] = []
        var validationReport: [String: Any]?

        var indexManifest: [String: Any]?
        var hasIndex = false

        do {
            let reader = try SVPReader(url: url)
            try reader.validateSVP()

            allEntries = reader.allEntryNames
            SVPAppLogger.log("Inspector found \(allEntries.count) entries in package")

            manifest = try? reader.readManifest()

            if let mi = try? reader.locatePrimaryMediaAsset() {
                mediaInfo = mi
            }
            mediaEntryCount = allEntries.filter { $0.hasPrefix("media/original/") && !$0.hasSuffix("/") }.count

            if reader.hasEntry("transcript/words.jsonl") {
                transcriptWords = (try? reader.readJSONLEntry("transcript/words.jsonl")) ?? []
            }
            if reader.hasEntry("transcript/transcript.json") {
                transcriptSummary = try? reader.readJSONEntry("transcript/transcript.json")
            }
            if reader.hasEntry("transcript/speakers.jsonl") {
                speakers = (try? reader.readJSONLEntry("transcript/speakers.jsonl")) ?? []
            }
            if reader.hasEntry("transcript/speaker_segments.jsonl") {
                speakerSegments = (try? reader.readJSONLEntry("transcript/speaker_segments.jsonl")) ?? []
            }

            if reader.hasEntry("text/text_regions.jsonl") {
                textRegions = (try? reader.readJSONLEntry("text/text_regions.jsonl")) ?? []
            }
            if reader.hasEntry("text/text_observations.jsonl") {
                textObservations = (try? reader.readJSONLEntry("text/text_observations.jsonl")) ?? []
            }
            if reader.hasEntry("text/numeric_values.jsonl") {
                numericValues = (try? reader.readJSONLEntry("text/numeric_values.jsonl")) ?? []
            }
            if reader.hasEntry("text/text_absence.json") {
                textAbsence = try? reader.readJSONEntry("text/text_absence.json")
            }
            if reader.hasEntry("text/evidence_crops.jsonl") {
                evidenceCrops = (try? reader.readJSONLEntry("text/evidence_crops.jsonl")) ?? []
                for crop in evidenceCrops {
                    if let cropFilePath = crop["crop_file_path"] as? String,
                       !cropFilePath.isEmpty,
                       reader.hasEntry(cropFilePath),
                       evidenceCropImages[cropFilePath] == nil {
                        evidenceCropImages[cropFilePath] = try? reader.readEntryData(cropFilePath)
                    }
                }
            }

            if reader.hasEntry("colors/color_observations.jsonl") {
                colorObservations = (try? reader.readJSONLEntry("colors/color_observations.jsonl")) ?? []
            }
            if reader.hasEntry("colors/color_summary.json") {
                colorSummary = try? reader.readJSONEntry("colors/color_summary.json")
            }
            if reader.hasEntry("colors/color_absence.json") {
                colorAbsence = try? reader.readJSONEntry("colors/color_absence.json")
            }

            if reader.hasEntry("timeline/shots.jsonl") {
                shots = (try? reader.readJSONLEntry("timeline/shots.jsonl")) ?? []
            }
            if reader.hasEntry("timeline/scenes.jsonl") {
                scenes = (try? reader.readJSONLEntry("timeline/scenes.jsonl")) ?? []
            }
            if reader.hasEntry("timeline/frames.jsonl") {
                frames = (try? reader.readJSONLEntry("timeline/frames.jsonl")) ?? []
            }

            if reader.hasEntry("entities/entities.jsonl") {
                entities = (try? reader.readJSONLEntry("entities/entities.jsonl")) ?? []
            }
            if reader.hasEntry("entities/entity_tracks.jsonl") {
                entityTracks = (try? reader.readJSONLEntry("entities/entity_tracks.jsonl")) ?? []
            }

            if reader.hasEntry("relationships/relationships.jsonl") {
                relationships = (try? reader.readJSONLEntry("relationships/relationships.jsonl")) ?? []
            }

            if reader.hasEntry("provenance/build.json") {
                provenanceBuild = try? reader.readJSONEntry("provenance/build.json")
            }
            if reader.hasEntry("provenance/processors.jsonl") {
                provenanceProcessors = (try? reader.readJSONLEntry("provenance/processors.jsonl")) ?? []
            }
            if reader.hasEntry("provenance/validation.json") {
                validationReport = try? reader.readJSONEntry("provenance/validation.json")
            }

            hasIndex = reader.hasEntry("index/index.sqlite")
            if reader.hasEntry("index/index_manifest.json") {
                indexManifest = try? reader.readJSONEntry("index/index_manifest.json")
            }

        } catch {
            SVPAppLogger.log("Inspector load error: \(error)")
            loadError = String(describing: error)
        }

        return SVPInspectorData(
            fileURL: url,
            manifest: manifest,
            mediaInfo: mediaInfo,
            mediaEntryCount: mediaEntryCount,
            allEntries: allEntries,
            transcriptWords: transcriptWords,
            transcriptSummary: transcriptSummary,
            speakers: speakers,
            speakerSegments: speakerSegments,
            textRegions: textRegions,
            textObservations: textObservations,
            numericValues: numericValues,
            textAbsence: textAbsence,
            evidenceCrops: evidenceCrops,
            evidenceCropImages: evidenceCropImages,
            colorObservations: colorObservations,
            colorSummary: colorSummary,
            colorAbsence: colorAbsence,
            shots: shots,
            scenes: scenes,
            frames: frames,
            entities: entities,
            entityTracks: entityTracks,
            relationships: relationships,
            provenanceBuild: provenanceBuild,
            provenanceProcessors: provenanceProcessors,
            validationReport: validationReport,
            indexManifest: indexManifest,
            hasIndex: hasIndex,
            loadError: loadError
        )
    }
}
