import AppKit

enum SVPPasteboardReader {
    static let systemMediaUTIs = [
        "public.mpeg-4", "com.apple.quicktime-movie", "com.apple.m4v-video",
        "public.mpeg-4-audio", "com.apple.m4a-audio"
    ]
    static func svpURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["com.semanticvideo.svp"]
        ]

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first { $0.pathExtension.lowercased() == "svp" }
    }

    static func svpiURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["com.semanticvideo.svpi"]
        ]

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first { $0.pathExtension.lowercased() == "svpi" }
    }

    static func semanticMediaURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: systemMediaUTIs
        ]
        return (pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL])?.first
    }
}
