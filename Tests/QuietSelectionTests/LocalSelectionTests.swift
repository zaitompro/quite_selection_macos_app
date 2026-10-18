import AppKit

@main
@MainActor
struct LocalSelectionTests {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 480, height: 200))
        view.string = "Before Тест 🧪 after"
        window.contentView = view
        precondition(window.makeFirstResponder(view))
        view.setSelectedRange(NSRange(location: 7, length: 7))
        let selectedView = try LocalSelection.read(from: window)
        precondition(selectedView == "Тест 🧪")
        view.setSelectedRange(NSRange(location: 7, length: 0))
        do { _ = try LocalSelection.read(from: window); fatalError("Expected no selection") }
        catch { precondition(error as? SelectionFailure == .noSelection) }

        let label = NSTextField(wrappingLabelWithString: "Before Тест 🧪 after")
        label.frame = NSRect(x: 0, y: 0, width: 480, height: 100)
        label.isSelectable = true
        window.contentView = label
        label.selectText(nil)
        guard let editor = window.firstResponder as? NSTextView else { fatalError("No label field editor") }
        editor.setSelectedRange(NSRange(location: 7, length: 7))
        let selectedLabel = try LocalSelection.read(from: window)
        precondition(selectedLabel == "Тест 🧪")

        let secure = NSSecureTextField(string: "synthetic-test-value")
        secure.frame = label.frame
        window.contentView = secure
        secure.selectText(nil)
        do { _ = try LocalSelection.read(from: window); fatalError("Secure field must be rejected") }
        catch { precondition(error as? SelectionFailure == .secureInput) }
        print("local_selection=PASS native_text_view, selectable_label, UTF16, empty_range, secure_field; external_queries=0")
    }
}
