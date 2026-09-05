import Foundation

extension Array where Element: Equatable {
  mutating func appendRemovingDuplicates(of newElement: Element) {
    self.removeAll { $0 == newElement }
    self.append(newElement)
  }
}
