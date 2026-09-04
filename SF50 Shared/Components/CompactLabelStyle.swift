public import SwiftUI

public struct CompactLabelStyle: LabelStyle {
  #if canImport(UIKit)
    @Environment(\.horizontalSizeClass)
    private var sizeClass
  #endif

  let compact: String?

  public init(compact: String? = nil) {
    self.compact = compact
  }

  @ViewBuilder
  public func makeBody(configuration: LabelStyleConfiguration) -> some View {
    HStack(spacing: 8) {
      configuration.icon

      #if canImport(UIKit)
        if sizeClass == .compact && compact != nil {
          Text(compact!).lineLimit(1).minimumScaleFactor(0.5)
        } else {
          configuration.title.lineLimit(1)
        }
      #else
        configuration.title.lineLimit(1)
      #endif
    }
  }
}
