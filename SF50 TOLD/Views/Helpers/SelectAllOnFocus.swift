import SwiftUI

#if canImport(UIKit)
  private class Delegate: NSObject, UITextFieldDelegate {
    func textFieldDidBeginEditing(_ textField: UITextField) {
      textField.selectAll(nil)
    }
  }
#endif

struct SelectAllOnFocus: ViewModifier {
  #if canImport(UIKit)
    private var delegate = Delegate()

    func body(content: Content) -> some View {
      return content.onReceive(
        NotificationCenter.default.publisher(for: UITextField.textDidBeginEditingNotification)
      ) { obj in
        guard let textField = obj.object as? UITextField else { return }
        // Defer to the next run loop: selecting synchronously inside
        // textDidBeginEditing is undone by SwiftUI's focus re-render of a
        // value-formatted field, which deselects and parks the caret at the end, so
        // a fast typist — or a UI test — appends instead of replacing the value.
        DispatchQueue.main.async {
          textField.selectAll(nil)
        }
      }
    }
  #else
    func body(content: Content) -> some View { content }
  #endif
}

extension View {
  func selectAllOnFocus() -> some View {
    modifier(SelectAllOnFocus())
  }
}
