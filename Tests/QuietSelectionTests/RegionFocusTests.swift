import AppKit

@MainActor
private final class FocusBackend: RegionFocusBackend {
    var front: Int? = 1
    let owner = 2
    var restored: [Int] = []
    func captureTarget() -> Int? { front }
    var ownsFocus: Bool { front == owner }
    func restore(_ target: Int) { restored.append(target); front = target }
}

@main
@MainActor
struct RegionFocusTests {
    static func main() {
        let backend = FocusBackend()
        let focus = RegionFocus(backend: backend)
        // Both successful selection and Esc use the same completion path.
        for _ in 0..<2 {
            backend.front = 1
            focus.begin()
            backend.front = backend.owner
            focus.finish()
            precondition(backend.front == 1)
        }
        precondition(backend.restored == [1, 1])
        print("focus=PASS return_after_selection_and_cancel")

        focus.finish()
        precondition(backend.restored == [1, 1])
        backend.front = 1
        focus.begin()
        backend.front = 3
        focus.finish()
        precondition(backend.front == 3 && backend.restored == [1, 1])
        backend.front = backend.owner
        focus.finish()
        precondition(backend.restored == [1, 1])
        print("focus=PASS no_repeated_restore_or_late_focus_steal")

        backend.front = 1
        focus.begin()
        backend.front = backend.owner
        focus.finish(restore: false)
        focus.finish()
        precondition(backend.restored == [1, 1])
        print("focus=PASS app_switch_cancellation_consumes_target")

        backend.front = nil
        focus.begin()
        backend.front = backend.owner
        focus.finish()
        precondition(backend.restored == [1, 1])
        backend.front = 4
        focus.begin()
        backend.front = backend.owner
        focus.finish()
        precondition(backend.front == 4 && backend.restored == [1, 1, 4])
        print("focus=PASS missing_target_and_new_session")

        backend.front = backend.owner
        focus.begin()
        focus.finish()
        precondition(backend.restored.last == backend.owner)
        print("focus=PASS own_settings_target; real_app_activation=not_tested external_content_queries=0")
    }
}
