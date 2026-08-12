import Foundation

public enum EmbeddedSVPITransportProfile {
    public static let identifier = "embedded-svpi-isobmff-v1"
    public static let uuid = Data([0xe2, 0xb6, 0xa2, 0x3c, 0x22, 0xca, 0x56, 0x36, 0xb1, 0x65, 0x99, 0x12, 0x08, 0xc8, 0x37, 0xf1])
    public static let magic = Data([0x53, 0x56, 0x50, 0x49, 0x4d, 0x50, 0x34, 0x00])
    public static let version: UInt16 = 1
    public static let envelopeSize: UInt16 = 64
    public static let supportedFlags: UInt32 = 0
    public static let hashSize = 32
    public static let reservedRange = 56..<64
}

public enum ISOBaseMediaFamily: String, Sendable {
    case mp4 = "MP4"
    case quickTime = "QuickTime MOV"
    case m4v = "M4V"
    case m4a = "M4A"
}
