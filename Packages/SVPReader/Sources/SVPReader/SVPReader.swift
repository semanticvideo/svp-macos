import Foundation
import os

public enum SVPLog {
    private static let subsystem = "com.cueit.svp-system-support"
    private static let logger = Logger(subsystem: subsystem, category: "SVPReader")

    static func debug(_ message: String) {
        #if DEBUG
        logger.debug("\(message, privacy: .public)")
        #endif
    }

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}

public final class SVPReader: @unchecked Sendable {
    private let url: URL
    private let zipReader: ZipReader

    public init(url: URL) throws {
        self.url = url
        self.zipReader = try ZipReader(url: url)
    }

    public init(package: SVPPackageDescriptor) throws {
        self.url = package.mediaURL
        self.zipReader = try ZipReader(source: package.source)
    }

    public func validateSVP() throws {
        guard zipReader.hasEntry("mimetype") else {
            throw SVPError.notSVPFile("No mimetype entry found")
        }

        let mimeData = try zipReader.readEntry("mimetype")
        guard let mime = String(data: mimeData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw SVPError.notSVPFile("Cannot read mimetype")
        }

        let validMimetypes: Set<String> = [
            "application/vnd.svp+zip",
            "application/vnd.svp.interlace+zip"
        ]
        guard validMimetypes.contains(mime) else {
            throw SVPError.notSVPFile("Unexpected mimetype: \(mime)")
        }

        guard zipReader.hasEntry("manifest.json") else {
            throw SVPError.manifestReadFailed("No manifest.json found")
        }

    }

    public func readManifest() throws -> SVPManifestInfo {
        let data = try zipReader.readEntry("manifest.json")
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SVPError.manifestParseFailed("JSON parse failed")
        }

        let svpVersion = json["svp_version"] as? String ?? ""
        let packageID = json["package_id"] as? String ?? ""
        let createdUTC = json["created_utc"] as? String ?? ""
        let primaryMediaID = json["primary_media_id"] as? String
        let primaryMediaBindingID = json["primary_media_binding_id"] as? String
        let resolvedPrimaryMediaID = primaryMediaBindingID.flatMap(resolvePrimaryMediaID)

        var timebaseUnit = ""
        var timebaseOrigin = ""
        if let timebase = json["timebase"] as? [String: Any] {
            timebaseUnit = timebase["unit"] as? String ?? ""
            timebaseOrigin = timebase["origin"] as? String ?? ""
        }

        return SVPManifestInfo(
            svpVersion: svpVersion,
            packageID: packageID,
            createdUTC: createdUTC,
            primaryMediaID: primaryMediaID,
            primaryMediaBindingID: primaryMediaBindingID,
            resolvedPrimaryMediaID: resolvedPrimaryMediaID,
            timebaseUnit: timebaseUnit,
            timebaseOrigin: timebaseOrigin
        )
    }

    private func resolvePrimaryMediaID(bindingID: String) -> String? {
        guard zipReader.hasEntry("media_binding.json"),
              let data = try? zipReader.readEntry("media_binding.json"),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bindings = json["bindings"] as? [[String: Any]],
              let primaryBinding = bindings.first(where: { $0["binding_id"] as? String == bindingID })
        else {
            return nil
        }

        return primaryBinding["media_id"] as? String
    }

    public func locatePrimaryMediaAsset() throws -> SVPMediaInfo {
        let _ = try readManifest()

        let mediaEntries = zipReader.entryNames.filter { name in
            name.hasPrefix("media/original/") && !name.hasSuffix("/")
        }

        guard !mediaEntries.isEmpty else {
            throw SVPError.noMediaFound("No files in media/original/")
        }

        let primaryEntry: String
        if mediaEntries.count == 1 {
            primaryEntry = mediaEntries[0]
        } else {
            let candidates = mediaEntries.sorted()
            primaryEntry = candidates[0]
            SVPLog.info("Multiple media files found, selecting first: \(primaryEntry)")
        }

        guard let entryInfo = zipReader.entryInfo(primaryEntry) else {
            throw SVPError.noMediaFound("Cannot get info for \(primaryEntry)")
        }

        let fileName = (primaryEntry as NSString).lastPathComponent
        let ext = (fileName as NSString).pathExtension

        return SVPMediaInfo(
            mediaPath: primaryEntry,
            mediaFileName: fileName,
            fileExtension: ext,
            uncompressedSize: entryInfo.uncompressedSize,
            compressionMethod: entryInfo.compressionMethod,
            localHeaderOffset: entryInfo.localHeaderOffset
        )
    }

    public func readMediaData(_ mediaInfo: SVPMediaInfo) throws -> Data {
        return try zipReader.readEntry(mediaInfo.mediaPath)
    }

    public func extractMediaData(_ mediaInfo: SVPMediaInfo, to destinationURL: URL) throws {
        try zipReader.extractEntry(mediaInfo.mediaPath, to: destinationURL)
    }

    public func mediaDataOffset(_ mediaInfo: SVPMediaInfo) throws -> UInt64 {
        try zipReader.entryDataOffset(mediaInfo.mediaPath)
    }

    public func readMediaDataRange(_ mediaInfo: SVPMediaInfo, offset: UInt64, length: Int) throws -> Data {
        try zipReader.readStoredEntryRange(mediaInfo.mediaPath, offset: offset, length: length)
    }

    public func readTranscriptText() throws -> String {
        let entryName = "transcript/words.jsonl"
        guard zipReader.hasEntry(entryName) else {
            throw SVPError.ioError("No transcript words found")
        }

        let data = try zipReader.readEntry(entryName)
        guard let jsonLines = String(data: data, encoding: .utf8) else {
            throw SVPError.ioError("Transcript words are not UTF-8")
        }

        let words = jsonLines
            .split(whereSeparator: \.isNewline)
            .compactMap { line -> TranscriptWordRecord? in
                guard let data = String(line).data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let text = object["text"] as? String
                else {
                    return nil
                }
                return TranscriptWordRecord(
                    text: text,
                    startUS: Self.int64Value(object["start_us"]),
                    endUS: Self.int64Value(object["end_us"])
                )
            }

        guard !words.isEmpty else {
            throw SVPError.ioError("Transcript is empty")
        }

        return TranscriptFormatter.format(words)
    }

    public func materializePrimaryMedia(to directory: URL? = nil) throws -> URL {
        let mediaInfo = try locatePrimaryMediaAsset()

        let tempDir: URL
        if let directory {
            tempDir = directory
        } else {
            tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("svp-media-\(UUID().uuidString)", isDirectory: true)
        }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destURL = tempDir.appendingPathComponent(mediaInfo.mediaFileName)

        SVPLog.info("Materializing \(mediaInfo.mediaPath) to \(destURL.path)")

        try zipReader.extractEntry(mediaInfo.mediaPath, to: destURL)

        SVPLog.info("Materialization complete: \(destURL.path)")

        return destURL
    }

    public func returnMediaInfo() throws -> (SVPManifestInfo?, SVPMediaInfo) {
        let manifest = try? readManifest()
        let mediaInfo = try locatePrimaryMediaAsset()
        return (manifest, mediaInfo)
    }

    public func openAndMaterialize() throws -> SVPReadResult {
        try validateSVP()

        let manifest = try? readManifest()
        let mediaInfo = try locatePrimaryMediaAsset()

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("svp-media-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let destURL = tempDir.appendingPathComponent(mediaInfo.mediaFileName)
        try zipReader.extractEntry(mediaInfo.mediaPath, to: destURL)

        SVPLog.info("SVP opened and materialized: \(destURL.path)")

        return SVPReadResult(
            manifest: manifest,
            mediaInfo: mediaInfo,
            mediaURL: destURL,
            isMaterialized: true,
            tempDir: tempDir
        )
    }

    public static func cleanupMaterializedMedia(at tempDir: URL) {
        try? FileManager.default.removeItem(at: tempDir)
        SVPLog.debug("Cleaned up temp dir: \(tempDir.path)")
    }

    // MARK: - Inspector Support

    public func hasEntry(_ name: String) -> Bool {
        zipReader.hasEntry(name)
    }

    public var allEntryNames: [String] {
        zipReader.entryNames
    }

    public func readEntryData(_ name: String) throws -> Data {
        try zipReader.readEntry(name)
    }

    @_spi(Inspector) public func extractEntry(_ name: String, to destinationURL: URL) throws {
        try zipReader.extractEntry(name, to: destinationURL)
    }

    @_spi(Inspector) public func entryUncompressedSize(_ name: String) -> UInt64? {
        zipReader.entryInfo(name)?.uncompressedSize
    }

    public func readJSONEntry(_ name: String) throws -> [String: Any] {
        let data = try zipReader.readEntry(name)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SVPError.manifestParseFailed("JSON parse failed for \(name)")
        }
        return json
    }

    public func readJSONLEntry(_ name: String) throws -> [[String: Any]] {
        let data = try zipReader.readEntry(name)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SVPError.ioError("\(name) is not UTF-8")
        }
        return text.split(whereSeparator: \.isNewline).compactMap { line in
            guard let lineData = String(line).data(using: .utf8) else { return nil }
            return (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
        }
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

}
