import SwiftUI

/// A row with a title and a caption on the leading side and its value on the trailing side.
///
/// Unlike `LabeledContent`, which stacks its value under a label too wide to sit beside it, the
/// caption wraps instead, so values stay aligned down a list.
struct CaptionedRow<Value: View>: View {
  let title: Text
  let caption: Text
  @ViewBuilder let value: () -> Value

  var body: some View {
    HStack {
      VStack(alignment: .leading) {
        title
        caption
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      value()
        .fixedSize()
    }
    .accessibilityElement(children: .combine)
  }
}

#Preview {
  List {
    CaptionedRow(
      title: Text("NASR Cycle"),
      caption: Text("National Airspace System Resources (FAA)")
    ) {
      Text("2026-10-29").bold()
    }
  }
}
