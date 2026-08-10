import Foundation
import SVPReader

final class SVPTranscriptLoader {
    func loadTranscript(from svpURL: URL) throws -> String {
        let reader = try SVPReader(url: svpURL)
        try reader.validateSVP()
        return try reader.readTranscriptText()
    }

    func loadTranscript(from package: SVPPackageDescriptor) throws -> String {
        let reader = try SVPReader(package: package)
        try reader.validateSVP()
        return try reader.readTranscriptText()
    }
}
