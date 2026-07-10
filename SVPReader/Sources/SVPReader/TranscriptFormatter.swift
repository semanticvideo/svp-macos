import Foundation

struct TranscriptWordRecord {
    let text: String
    let startUS: Int64?
    let endUS: Int64?
}

enum TranscriptFormatter {
    private static let paragraphSilenceThresholdUS: Int64 = 600_000
    private static let trailingSentenceClosers: Set<Character> = ["\"", "'", "”", "’", ")", "]", "}"]
    private static let sentenceTerminators: Set<Character> = [".", "?", "!", "…"]

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

        if endsSentence(previous.text),
           let previousEnd = previous.endUS,
           let currentStart = current.startUS {
            let (paragraphStart, overflow) = previousEnd.addingReportingOverflow(paragraphSilenceThresholdUS)
            if !overflow, currentStart >= paragraphStart {
                return true
            }
        }

        return false
    }

    private static func endsSentence(_ text: String) -> Bool {
        var characters = Array(text.trimmingCharacters(in: .whitespacesAndNewlines))
        while let last = characters.last, trailingSentenceClosers.contains(last) {
            characters.removeLast()
        }
        guard let last = characters.last else { return false }
        return sentenceTerminators.contains(last)
    }

}
