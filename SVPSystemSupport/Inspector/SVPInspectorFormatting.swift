import Foundation

// MARK: - Value Formatting Helpers

func displayString(_ dict: [String: Any], _ key: String) -> String {
    guard let value = dict[key] else { return "—" }
    return formatValue(value)
}

func formatValue(_ value: Any) -> String {
    if let s = value as? String { return s.isEmpty ? "—" : s }
    if let n = value as? NSNumber { return n.stringValue }
    if let arr = value as? [Any] { return "\(arr.count) items" }
    if let dict = value as? [String: Any] {
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) { return str }
        return String(describing: dict)
    }
    return String(describing: value)
}

func formatMicroseconds(_ dict: [String: Any], _ key: String) -> String {
    guard let value = dict[key] else { return "—" }
    if let n = value as? NSNumber {
        return String(format: "%.3f", n.doubleValue / 1_000_000)
    }
    return "—"
}

func prettyJSON(_ dict: [String: Any]?) -> String {
    guard let dict else { return "—" }
    if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys]),
       let str = String(data: data, encoding: .utf8) { return str }
    return String(describing: dict)
}

// MARK: - Table Row Wrapper

struct SortValue: Comparable {
    let value: Any?

    static func < (lhs: SortValue, rhs: SortValue) -> Bool {
        if lhs.value == nil && rhs.value == nil { return false }
        if lhs.value == nil { return true }
        if rhs.value == nil { return false }

        if let la = lhs.value as? [Any], let ra = rhs.value as? [Any] {
            return la.count < ra.count
        }
        if let ln = lhs.value as? NSNumber, let rn = rhs.value as? NSNumber {
            return ln.doubleValue < rn.doubleValue
        }

        let ls = String(describing: lhs.value!)
        let rs = String(describing: rhs.value!)
        return ls < rs
    }

    static func == (lhs: SortValue, rhs: SortValue) -> Bool {
        if let ln = lhs.value as? NSNumber, let rn = rhs.value as? NSNumber {
            return ln.doubleValue == rn.doubleValue
        }
        return String(describing: lhs.value ?? "") == String(describing: rhs.value ?? "")
    }
}

@dynamicMemberLookup
struct InspectorRow: Identifiable {
    let id: Int
    let dict: [String: Any]

    subscript(dynamicMember key: String) -> SortValue {
        SortValue(value: dict[key])
    }

    var id_string: SortValue { SortValue(value: dict["id"]) }
}

func makeRows(_ array: [[String: Any]]) -> [InspectorRow] {
    array.enumerated().map { InspectorRow(id: $0.offset, dict: $0.element) }
}

func sortedRows(_ rows: [InspectorRow], sortOrder: [KeyPathComparator<InspectorRow>]) -> [InspectorRow] {
    guard !sortOrder.isEmpty else { return rows }
    return rows.sorted(using: sortOrder)
}
