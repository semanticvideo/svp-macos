import Foundation
import MediaExtension
import AVFoundation
import CoreMedia
import SVPReader
import os

let svpMEReaderLogger = Logger(subsystem: "com.cueit.svp-system-support", category: "MediaExtension")

@objc(SVPFormatReaderExtension)
final class SVPFormatReaderExtension: NSObject, MEFormatReaderExtension {

    override init() {
        super.init()
        svpMEReaderLogger.info("SVPFormatReaderExtension instantiated")
    }

    func formatReader(with primaryByteSource: MEByteSource,
                      options: MEFormatReaderInstantiationOptions?) throws -> any MEFormatReader {
        svpMEReaderLogger.info("formatReader called, fileName: \(primaryByteSource.fileName, privacy: .public)")

        let reader = try SVPFormatReader(byteSource: primaryByteSource)
        return reader
    }
}
