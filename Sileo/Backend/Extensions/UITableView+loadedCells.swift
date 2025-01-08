import Foundation

extension UITableView {
    public var loadedCells : [UITableViewCell] {
        var loadedCells = [UITableViewCell]()
        for section in 0..<self.numberOfSections {
            for row in 0..<self.numberOfRows(inSection: section) {
                let indexPath = IndexPath(row: row, section: section)
                if let cell = self.cellForRow(at: indexPath) {
                    loadedCells.append(cell)
                }
            }
        }
        return loadedCells
    }
}
