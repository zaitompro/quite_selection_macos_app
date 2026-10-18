import Foundation

private final class FocusSource: FocusedElementSource {
    var app: Int? = 10
    var system: Int? = 20
    var owner: Int32 = 100
    var front = true
    var switchAfterApp = false
    var switchAfterSystem = false
    var error: SelectionFailure?
    var calls: [String] = []
    var allowsAccessibilityPreparation = false
    var preparationSucceeds = true
    var preparedApp: Int? = 30
    var preparedSystem: Int?
    var preparationError: SelectionFailure?
    var foreignElement: Int?
    var switchAfterPreparation = false
    var isTargetFrontmost: Bool { front }
    func applicationFocus() throws -> Int? {
        calls.append("application")
        if let error { throw error }
        if switchAfterApp { front = false }
        return app
    }
    func systemFocus() -> Int? {
        calls.append("system")
        if switchAfterSystem { front = false }
        return system
    }
    func processID(of element: Int) -> Int32 {
        calls.append("pid")
        return element == foreignElement ? 999 : owner
    }
    func prepareApplicationAccessibility() throws -> Bool {
        calls.append("prepare")
        if let preparationError { throw preparationError }
        if switchAfterPreparation { front = false }
        app = preparedApp; system = preparedSystem
        return preparationSucceeds
    }
}

@main
struct FocusedElementTests {
    static func main() throws {
        func resolve(_ source: FocusSource) throws -> Int? {
            try FocusedElementResolver(source: source, targetPID: 100).resolve()
        }
        func expectFailure(_ source: FocusSource, _ expected: SelectionFailure) {
            do { _ = try resolve(source); fatalError("Expected rejection") }
            catch { precondition(error as? SelectionFailure == expected) }
        }
        let direct = FocusSource(); direct.allowsAccessibilityPreparation = true
        let first = try resolve(direct)
        precondition(first == 10 && direct.calls == ["application"])
        print("focus_resolver=PASS existing_path_no_extra_queries")

        let fallback = FocusSource(); fallback.app = nil; fallback.allowsAccessibilityPreparation = true
        let second = try resolve(fallback)
        precondition(second == 20 && fallback.calls == ["application", "system", "pid"])
        let missing = FocusSource(); missing.app = nil; missing.system = nil
        let absent = try resolve(missing)
        precondition(absent == nil && missing.calls == ["application", "system"])
        print("focus_resolver=PASS system_fallback_and_missing_focus")

        let wrong = FocusSource(); wrong.app = nil; wrong.owner = 999
        expectFailure(wrong, .changedApplication)
        let before = FocusSource(); before.front = false
        expectFailure(before, .changedApplication)
        precondition(before.calls.isEmpty)
        let during = FocusSource(); during.app = nil; during.switchAfterApp = true
        expectFailure(during, .changedApplication)
        precondition(during.calls == ["application"])
        let after = FocusSource(); after.app = nil; after.switchAfterSystem = true
        expectFailure(after, .changedApplication)
        print("focus_resolver=PASS reject_other_process_and_focus_changes")

        let timeout = FocusSource(); timeout.error = .accessibility(-25204)
        expectFailure(timeout, .accessibility(-25204))
        precondition(timeout.calls == ["application"])
        print("focus_resolver=PASS no_retry_after_error; real_AX_queries=0")

        func preparationSource() -> FocusSource {
            let source = FocusSource()
            source.app = nil; source.system = nil; source.allowsAccessibilityPreparation = true
            return source
        }
        let prepared = preparationSource()
        let third = try resolve(prepared)
        precondition(third == 30)
        precondition(prepared.calls == ["application", "system", "prepare", "application", "pid"])
        let systemPrepared = preparationSource(); systemPrepared.preparedApp = nil; systemPrepared.preparedSystem = 40
        let fourth = try resolve(systemPrepared)
        precondition(fourth == 40)
        precondition(systemPrepared.calls == ["application", "system", "prepare", "application", "system", "pid"])
        let unavailable = preparationSource(); unavailable.preparationSucceeds = false
        let unavailableResult = try resolve(unavailable)
        precondition(unavailableResult == nil && unavailable.calls == ["application", "system", "prepare"])
        let stillMissing = preparationSource(); stillMissing.preparedApp = nil
        let missingResult = try resolve(stillMissing)
        precondition(missingResult == nil && stillMissing.calls == ["application", "system", "prepare", "application", "system"])
        print("focus_resolver=PASS role_preparation_then_single_bounded_retry")

        let foreignFocus = preparationSource(); foreignFocus.foreignElement = 30
        expectFailure(foreignFocus, .changedApplication)
        let foreignSystem = preparationSource(); foreignSystem.preparedApp = nil
        foreignSystem.preparedSystem = 40; foreignSystem.foreignElement = 40
        expectFailure(foreignSystem, .changedApplication)
        let switched = preparationSource(); switched.switchAfterPreparation = true
        expectFailure(switched, .changedApplication)
        precondition(switched.calls == ["application", "system", "prepare"])
        let failedPreparation = preparationSource(); failedPreparation.preparationError = .accessibility(-25204)
        expectFailure(failedPreparation, .accessibility(-25204))
        precondition(failedPreparation.calls == ["application", "system", "prepare"])
        print("focus_resolver=PASS prepared_focus_owner_frontmost_and_error_guards")
    }
}
