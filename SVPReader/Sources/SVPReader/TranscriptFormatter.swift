import Foundation

struct TranscriptWordRecord {
    let text: String
    let startUS: Int64?
    let endUS: Int64?
    let speakerID: String?
    let chunkOrdinal: Int?
}

enum TranscriptFormatter {
    static func format(_ words: [TranscriptWordRecord]) -> String {
        var paragraphs: [String] = []
        var currentWords: [String] = []
        var previousWord: TranscriptWordRecord?

        for word in words {
            if shouldStartNewParagraph(after: previousWord, before: word) {
                appendParagraph(from: &currentWords, to: &paragraphs)
            }

            currentWords.append(word.text)

            previousWord = word
        }

        appendParagraph(from: &currentWords, to: &paragraphs)
        return paragraphs.joined(separator: "\n\n")
    }

    private static func appendParagraph(from words: inout [String], to paragraphs: inout [String]) {
        guard !words.isEmpty else { return }
        paragraphs.append(words.joined(separator: " "))
        words.removeAll(keepingCapacity: true)
    }

    private static func shouldStartNewParagraph(
        after previous: TranscriptWordRecord?,
        before current: TranscriptWordRecord
    ) -> Bool {
        guard let previous else { return false }

        if let previousChunk = previous.chunkOrdinal,
           let currentChunk = current.chunkOrdinal,
           previousChunk != currentChunk {
            return true
        }

        if let previousSpeaker = previous.speakerID,
           let currentSpeaker = current.speakerID,
           previousSpeaker != currentSpeaker {
            return true
        }

        if let previousEnd = previous.endUS,
           let currentStart = current.startUS,
           currentStart - previousEnd >= 1_500_000 {
            return true
        }

        return false
    }

}
