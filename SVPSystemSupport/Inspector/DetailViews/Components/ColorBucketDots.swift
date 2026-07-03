import SwiftUI

private let bucketColors: [String: Color] = [
    "black": .black,
    "blue": .blue,
    "brown": .brown,
    "cyan": .cyan,
    "gray": .gray,
    "green": .green,
    "orange": .orange,
    "pink": .pink,
    "purple": .purple,
    "red": .red,
    "white": .white,
    "yellow": .yellow,
    "other": .secondary,
]

struct ColorBucketDots: View {
    let bucketCoverage: [String: Any]

    private var sortedBuckets: [(name: String, coverage: Double)] {
        bucketCoverage.compactMap { (key, value) in
            if let n = value as? NSNumber {
                return (name: key, coverage: n.doubleValue)
            }
            return nil
        }
        .filter { $0.coverage > 0 }
        .sorted { $0.coverage > $1.coverage }
    }

    private func textColor(for bucket: String) -> Color {
        let lightBuckets: Set<String> = ["white", "yellow", "cyan", "gray", "orange", "pink"]
        return lightBuckets.contains(bucket) ? .black : .white
    }

    var body: some View {
        if sortedBuckets.isEmpty {
            Text("—")
        } else {
            GeometryReader { geo in
                let dotWidth: CGFloat = 28
                let spacing: CGFloat = 4
                let maxDots = max(1, Int((geo.size.width + spacing) / (dotWidth + spacing)))
                HStack(spacing: spacing) {
                    ForEach(sortedBuckets.prefix(maxDots), id: \.name) { bucket in
                        let pct = Int((bucket.coverage * 100).rounded())
                        ZStack {
                            Circle()
                                .fill(bucketColors[bucket.name] ?? .secondary)
                                .frame(width: dotWidth, height: dotWidth)
                            Text("\(pct)%")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(textColor(for: bucket.name))
                        }
                    }
                }
            }
            .frame(height: 28)
        }
    }
}

func formatColorBuckets(_ bucketCoverage: [String: Any]?) -> String {
    guard let bucketCoverage else { return "—" }
    let buckets = bucketCoverage.compactMap { key, value -> (String, Double)? in
        guard let number = value as? NSNumber, number.doubleValue > 0 else { return nil }
        return (key, number.doubleValue)
    }
    .sorted { $0.1 > $1.1 }
    .prefix(4)

    guard !buckets.isEmpty else { return "—" }
    return buckets
        .map { "\($0.0) \(Int(($0.1 * 100).rounded()))%" }
        .joined(separator: ", ")
}
