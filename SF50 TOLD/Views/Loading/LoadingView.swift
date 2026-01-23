import SF50_Shared
import SwiftData
import SwiftUI

struct LoadingView: View {
  @Environment(DataLoaderViewModel.self)
  private var loader

  @State private var errorSheetIsPresented = false

  var body: some View {
    content
      .withErrorSheet(state: loader)
  }

  @ViewBuilder private var content: some View {
    switch loader.state {
      case .idle:
        LoadingConsentView()
      default:
        LoadingProgressView()
    }
  }
}

#Preview {
  PreviewView { preview in
    return LoadingView()
      .environment(DataLoaderViewModel(container: preview.container))
  }
}
