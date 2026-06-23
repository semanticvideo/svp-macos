import AppKit

enum SVPPasteboardReader {
    static func svpURL(from pasteboard: NSPasteboard) -> URL? {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [
            .urlReadingFileURLsOnly: true,
            .urlReadingContentsConformToTypes: ["com.semanticvideo.svp"]
        ]

        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL]
        return urls?.first { $0.pathExtension.lowercased() == "svp" }
    }
}
