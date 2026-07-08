import AppKit
import SwiftUI

struct InspectorJSONLTableView: NSViewRepresentable {
    static let colorBucketRowHeight: CGFloat = 34

    let store: SVPInspectorJSONLStore
    let columns: [InspectorJSONLColumn]
    let defaultRowOrder: ((SVPInspectorJSONLStore) -> [Int])?

    init(
        store: SVPInspectorJSONLStore,
        columns: [InspectorJSONLColumn],
        defaultRowOrder: ((SVPInspectorJSONLStore) -> [Int])? = nil
    ) {
        self.store = store
        self.columns = columns
        self.defaultRowOrder = defaultRowOrder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(store: store, columns: columns, defaultRowOrder: defaultRowOrder)
    }

    func makeNSView(context: Context) -> NSView {
        let containerView = NSView()
        containerView.translatesAutoresizingMaskIntoConstraints = false

        let scrollView = NSScrollView()
        scrollView.identifier = NSUserInterfaceItemIdentifier("jsonlTableScrollView")
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.borderType = .noBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let tableView = NSTableView()
        tableView.usesAlternatingRowBackgroundColors = true
        tableView.allowsColumnReordering = true
        tableView.allowsColumnResizing = true
        tableView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
        context.coordinator.defaultRowHeight = tableView.rowHeight
        context.coordinator.defaultIntercellSpacing = tableView.intercellSpacing
        applyRowMetrics(to: tableView, coordinator: context.coordinator)
        tableView.delegate = context.coordinator
        tableView.dataSource = context.coordinator

        for (index, column) in columns.enumerated() {
            addColumn(index: index, column: column, to: tableView)
        }

        scrollView.documentView = tableView

        let overlayView = makeSortOverlayView()

        containerView.addSubview(scrollView)
        containerView.addSubview(overlayView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: containerView.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),

            overlayView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            overlayView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            overlayView.topAnchor.constraint(equalTo: containerView.topAnchor),
            overlayView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])

        return containerView
    }

    func updateNSView(_ containerView: NSView, context: Context) {
        context.coordinator.store = store
        context.coordinator.columns = columns
        context.coordinator.defaultRowOrder = defaultRowOrder
        if let tableView = Self.tableView(in: containerView) {
            applyRowMetrics(to: tableView, coordinator: context.coordinator)
            context.coordinator.applySortDescriptors(tableView.sortDescriptors, tableView: tableView)
            tableView.reloadData()
        }
    }

    private func applyRowMetrics(to tableView: NSTableView, coordinator: Coordinator) {
        guard columns.contains(where: { $0.cellView != nil }) else {
            tableView.rowHeight = coordinator.defaultRowHeight
            tableView.intercellSpacing = coordinator.defaultIntercellSpacing
            return
        }

        tableView.rowHeight = Self.colorBucketRowHeight
        tableView.intercellSpacing = NSSize(width: 3, height: 4)
    }

    private func addColumn(index: Int, column: InspectorJSONLColumn, to tableView: NSTableView) {
        let tableColumn = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("\(index)"))
        tableColumn.title = column.title
        tableColumn.width = column.width
        tableColumn.minWidth = column.minWidth
        if column.sortValue != nil {
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: "\(index)", ascending: true)
        }
        tableView.addTableColumn(tableColumn)
    }

    private func makeSortOverlayView() -> NSView {
        let overlayView = NSVisualEffectView()
        overlayView.identifier = NSUserInterfaceItemIdentifier("sortOverlayView")
        overlayView.blendingMode = .withinWindow
        overlayView.material = .contentBackground
        overlayView.state = .active
        overlayView.wantsLayer = true
        overlayView.layer?.backgroundColor = NSColor.clear.cgColor
        overlayView.isHidden = true
        overlayView.translatesAutoresizingMaskIntoConstraints = false

        let progressIndicator = NSProgressIndicator()
        progressIndicator.identifier = NSUserInterfaceItemIdentifier("sortProgressIndicator")
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "Sorting...")
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        let stackView = NSStackView(views: [progressIndicator, label])
        stackView.identifier = NSUserInterfaceItemIdentifier("sortOverlayStackView")
        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 10
        stackView.edgeInsets = NSEdgeInsets(top: 18, left: 24, bottom: 18, right: 24)
        stackView.wantsLayer = true
        stackView.layer?.backgroundColor = NSColor.clear.cgColor
        stackView.translatesAutoresizingMaskIntoConstraints = false

        overlayView.addSubview(stackView)
        NSLayoutConstraint.activate([
            stackView.centerXAnchor.constraint(equalTo: overlayView.centerXAnchor),
            stackView.centerYAnchor.constraint(equalTo: overlayView.centerYAnchor)
        ])

        return overlayView
    }

    private static func tableView(in containerView: NSView) -> NSTableView? {
        guard let scrollView = containerView.subviews.first(where: {
            $0.identifier == NSUserInterfaceItemIdentifier("jsonlTableScrollView")
        }) as? NSScrollView else { return nil }

        return scrollView.documentView as? NSTableView
    }

    final class Coordinator: NSObject, NSTableViewDataSource, NSTableViewDelegate {
        private struct SortSignature: Equatable {
            let storeID: ObjectIdentifier
            let columnIndex: Int
            let ascending: Bool
            let rowCount: Int
        }

        var store: SVPInspectorJSONLStore
        var columns: [InspectorJSONLColumn]
        var defaultRowOrder: ((SVPInspectorJSONLStore) -> [Int])?
        var defaultRowHeight: CGFloat = 17
        var defaultIntercellSpacing = NSSize(width: 3, height: 2)
        private var defaultRowIndexes: [Int]?
        private var sortedRowIndexes: [Int]?
        private var sortGeneration = 0
        private var activeSortSignature: SortSignature?
        private let sortQueue = DispatchQueue(label: "com.cueit.svp-system-support.inspector-jsonl-sort", qos: .userInitiated)

        init(
            store: SVPInspectorJSONLStore,
            columns: [InspectorJSONLColumn],
            defaultRowOrder: ((SVPInspectorJSONLStore) -> [Int])?
        ) {
            self.store = store
            self.columns = columns
            self.defaultRowOrder = defaultRowOrder
        }

        func numberOfRows(in tableView: NSTableView) -> Int {
            store.rowCount
        }

        func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
            let identifier = tableColumn?.identifier ?? NSUserInterfaceItemIdentifier("cell")
            let textField = tableView.makeView(withIdentifier: identifier, owner: self) as? NSTextField
                ?? makeTextField(identifier: identifier)
            guard let columnIndex = Int(identifier.rawValue), columns.indices.contains(columnIndex) else {
                textField.stringValue = "—"
                return textField
            }

            let sourceRow = sourceRow(for: row)
            if let cellView = columns[columnIndex].cellView?(store, sourceRow) {
                return cellView
            }

            textField.stringValue = columns[columnIndex].text(store, sourceRow)
            return textField
        }

        func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
            applySortDescriptors(tableView.sortDescriptors, tableView: tableView)
            tableView.reloadData()
        }

        private func makeTextField(identifier: NSUserInterfaceItemIdentifier) -> NSTextField {
            let textField = InspectorCenteredTextField(labelWithString: "")
            textField.identifier = identifier
            textField.lineBreakMode = .byTruncatingMiddle
            textField.maximumNumberOfLines = 1
            textField.cell?.truncatesLastVisibleLine = true
            textField.isSelectable = true
            return textField
        }

        private func sourceRow(for visibleRow: Int) -> Int {
            if let sortedRowIndexes, sortedRowIndexes.indices.contains(visibleRow) {
                return sortedRowIndexes[visibleRow]
            }
            if let defaultRowIndexes, defaultRowIndexes.indices.contains(visibleRow) {
                return defaultRowIndexes[visibleRow]
            }
            return visibleRow
        }

        func applySortDescriptors(_ descriptors: [NSSortDescriptor], tableView: NSTableView?) {
            guard let descriptor = descriptors.first,
                  let key = descriptor.key,
                  let columnIndex = Int(key),
                  columns.indices.contains(columnIndex),
                  let sortValue = columns[columnIndex].sortValue else {
                sortedRowIndexes = nil
                defaultRowIndexes = validatedDefaultRowOrder()
                activeSortSignature = nil
                sortGeneration += 1
                setSortInProgress(false, tableView: tableView)
                return
            }

            let ascending = descriptor.ascending
            let signature = SortSignature(
                storeID: ObjectIdentifier(store),
                columnIndex: columnIndex,
                ascending: ascending,
                rowCount: store.rowCount
            )
            guard activeSortSignature != signature else { return }

            sortGeneration += 1
            let generation = sortGeneration
            activeSortSignature = signature
            defaultRowIndexes = nil
            sortedRowIndexes = nil
            setSortInProgress(true, tableView: tableView)

            let store = store
            let rowCount = store.rowCount
            sortQueue.async { [weak self, weak tableView] in
                let sortedIndexes = (0..<rowCount)
                    .map { (index: $0, value: sortValue(store, $0)) }
                    .sorted { lhs, rhs in
                    if lhs.value == rhs.value {
                        return lhs.index < rhs.index
                    }
                    return ascending ? lhs.value < rhs.value : rhs.value < lhs.value
                }
                .map(\.index)

                DispatchQueue.main.async {
                    guard let self, self.sortGeneration == generation else { return }
                    self.sortedRowIndexes = sortedIndexes
                    self.setSortInProgress(false, tableView: tableView)
                    tableView?.reloadData()
                }
            }
        }

        private func validatedDefaultRowOrder() -> [Int]? {
            guard let rowIndexes = defaultRowOrder?(store),
                  rowIndexes.count == store.rowCount else { return nil }

            var seen = Set<Int>()
            for rowIndex in rowIndexes {
                guard rowIndex >= 0, rowIndex < store.rowCount, seen.insert(rowIndex).inserted else {
                    return nil
                }
            }
            return rowIndexes
        }

        private func setSortInProgress(_ isInProgress: Bool, tableView: NSTableView?) {
            guard let scrollView = tableView?.enclosingScrollView,
                  let containerView = scrollView.superview,
                  let overlayView = containerView.subviews.first(where: {
                      $0.identifier == NSUserInterfaceItemIdentifier("sortOverlayView")
                  }) else { return }

            let progressIndicator = overlayView.subviews
                .compactMap { $0 as? NSStackView }
                .flatMap(\.views)
                .first { $0.identifier == NSUserInterfaceItemIdentifier("sortProgressIndicator") } as? NSProgressIndicator

            overlayView.isHidden = !isInProgress
            if isInProgress {
                overlayView.alphaValue = 1
                progressIndicator?.startAnimation(nil)
            } else {
                progressIndicator?.stopAnimation(nil)
            }
        }
    }
}
