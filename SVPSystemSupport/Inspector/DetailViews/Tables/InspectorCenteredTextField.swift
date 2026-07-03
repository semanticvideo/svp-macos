import AppKit

final class InspectorCenteredTextField: NSTextField {
    override func draw(_ dirtyRect: NSRect) {
        guard let cell else {
            super.draw(dirtyRect)
            return
        }

        let cellHeight = cell.cellSize(forBounds: bounds).height
        var centeredBounds = bounds
        centeredBounds.origin.y += max(0, (bounds.height - cellHeight) / 2)
        centeredBounds.size.height = min(bounds.height, cellHeight)
        cell.draw(withFrame: centeredBounds, in: self)
    }
}
