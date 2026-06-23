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
}
