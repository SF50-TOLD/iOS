import SwiftUI

/// Tells the pilot the NOTAM editor was filled in from a downloaded NOTAM, and to check it.
struct IntelligenceBanner: View {

  // MARK: - Type Properties

  private static let borderWidth: CGFloat = 1.5,
    tintOpacity = 0.12

  // MARK: - Instance Properties

  /// The identifiers of the NOTAMs the values came from.
  let notamIDs: [String]

  let onUndo: () -> Void
  let onDismiss: () -> Void

  // MARK: - Body

  var body: some View {
    HStack(alignment: .firstTextBaseline) {
      Label {
        VStack(alignment: .leading) {
          if notamIDs.count == 1 {
            Text(
              "Filled in from NOTAM \(notamIDs, format: .list(type: .and)). Check each value against the NOTAM’s text."
            )
          } else {
            Text(
              "Filled in from NOTAMs \(notamIDs, format: .list(type: .and)). Check each value against the NOTAMs’ text."
            )
          }

          Button("Undo", action: onUndo)
            .fontWeight(.medium)
            .buttonStyle(.borderless)
            .accessibilityIdentifier("undoFillButton")
        }
      } icon: {
        Image(systemName: "wand.and.sparkles")
          .foregroundStyle(IntelligenceGradient.linear)
      }
      .labelStyle(FirstLineLabelStyle())
      .font(.subheadline)

      Spacer(minLength: 0)

      Button(action: onDismiss) {
        Image(systemName: "xmark")
          .imageScale(.small)
          .fontWeight(.semibold)
          .foregroundStyle(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Dismiss")
    }
    .padding()
    .background {
      // Concentric, so the banner's corners follow the list row it sits in.
      let shape = ConcentricRectangle()
      shape
        .fill(IntelligenceGradient.linear.opacity(Self.tintOpacity))
        // A concentric shape can't inset its border, so the stroke is doubled and its outer half
        // clipped away.
        .overlay {
          shape.stroke(IntelligenceGradient.linear, lineWidth: Self.borderWidth * 2).clipShape(
            shape
          )
        }
    }
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("fillBanner")
  }
}

/// A label whose icon sits on its title's first line, however many lines the title runs to.
private struct FirstLineLabelStyle: LabelStyle {
  func makeBody(configuration: Configuration) -> some View {
    HStack(alignment: .firstTextBaseline) {
      configuration.icon
      configuration.title
    }
  }
}

#Preview("One NOTAM") {
  List {
    Section {
      IntelligenceBanner(notamIDs: ["A1234/26"], onUndo: {}, onDismiss: {})
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
    }
  }
}

#Preview("Several NOTAMs") {
  List {
    Section {
      IntelligenceBanner(notamIDs: ["A1234/26", "A1240/26"], onUndo: {}, onDismiss: {})
        .listRowInsets(.init())
        .listRowBackground(Color.clear)
    }
  }
}
