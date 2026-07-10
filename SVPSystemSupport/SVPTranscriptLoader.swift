import Foundation
import SVPReader

final class SVPTranscriptLoader {
    func loadTranscript(from svpURL: URL) throws -> String {
        SVPAppLogger.log("App loading transcript from: \(svpURL.path)")
        let reader = try SVPReader(url: svpURL)
        try reader.validateSVP()
        let transcript = try reader.readTranscriptText()
        SVPAppLogger.log("App loaded transcript: \(transcript.count) characters")
        return transcript
    }

    func loadTranscript(from package: SVPPackageDescriptor) throws -> String {
        SVPAppLogger.log("App loading embedded transcript from: \(package.mediaURL.path)")
        let reader = try SVPReader(package: package)
        try reader.validateSVP()
        return try reader.readTranscriptText()
    }
}
