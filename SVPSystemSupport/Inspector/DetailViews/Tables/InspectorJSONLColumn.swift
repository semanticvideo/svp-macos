import AppKit
import SwiftUI

struct InspectorJSONLColumn {
    let title: String
    let width: CGFloat
    let minWidth: CGFloat
    let text: (SVPInspectorJSONLStore, Int) -> String
    let cellView: ((SVPInspectorJSONLStore, Int) -> NSView?)?
    let sortValue: ((SVPInspectorJSONLStore, Int) -> SVPInspectorJSONLSortValue)?

    static func text(_ title: String, key: String, width: CGFloat, minWidth: CGFloat = 60) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in store.text(at: row, key: key) },
            cellView: nil,
            sortValue: { store, row in store.sortValue(at: row, key: key) }
        )
    }

    static func microseconds(_ title: String, key: String, width: CGFloat, minWidth: CGFloat = 60) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in store.microsecondsText(at: row, key: key) },
            cellView: nil,
            sortValue: { store, row in store.sortValue(at: row, key: key) }
        )
    }

    static func colorBuckets(_ title: String, key: String, width: CGFloat, minWidth: CGFloat = 124) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in
                guard let dict = store.row(at: row) else { return "—" }
                return formatColorBuckets(dict[key] as? [String: Any])
            },
            cellView: { store, row in
                guard let dict = store.row(at: row),
                      let bucketCoverage = dict[key] as? [String: Any] else {
                    let textField = InspectorCenteredTextField(labelWithString: "—")
                    textField.lineBreakMode = .byTruncatingMiddle
                    textField.maximumNumberOfLines = 1
                    textField.cell?.truncatesLastVisibleLine = true
                    textField.isSelectable = true
                    return textField
                }
                let hostingView = NSHostingView(
                    rootView: ColorBucketDots(bucketCoverage: bucketCoverage)
                        .frame(height: InspectorJSONLTableView.colorBucketRowHeight)
                )
                hostingView.translatesAutoresizingMaskIntoConstraints = false
                return hostingView
            },
            sortValue: nil
        )
    }

    static func custom(
        _ title: String,
        width: CGFloat,
        minWidth: CGFloat = 60,
        text: @escaping ([String: Any]) -> String
    ) -> InspectorJSONLColumn {
        InspectorJSONLColumn(
            title: title,
            width: width,
            minWidth: minWidth,
            text: { store, row in
                guard let dict = store.row(at: row) else { return "—" }
                return text(dict)
            },
            cellView: nil,
            sortValue: nil
        )
    }
}
