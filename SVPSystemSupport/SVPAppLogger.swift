import Foundation

enum SVPAppLogger {
    nonisolated static let appGroupID = "group.com.cueit.svp-system-support"
    nonisolated static let logFileName = "svp_extract.log"

    nonisolated static func log(_ message: String) {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }

        let logURL = containerURL.appendingPathComponent(logFileName)
        let line = "\(Date()) \(message)\n"
        guard let data = line.data(using: .utf8) else { return }

        if FileManager.default.fileExists(atPath: logURL.path),
           let handle = try? FileHandle(forWritingTo: logURL) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            _ = try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: logURL, options: .atomic)
        }
    }
}
