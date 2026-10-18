import Foundation

protocol FocusedElementSource {
    associatedtype Element
    var isTargetFrontmost: Bool { get }
    func applicationFocus() throws -> Element?
    func systemFocus() throws -> Element?
    func processID(of element: Element) throws -> Int32
    var allowsAccessibilityPreparation: Bool { get }
    func prepareApplicationAccessibility() throws -> Bool
}

struct FocusedElementResolver<Source: FocusedElementSource> {
    let source: Source
    let targetPID: Int32

    func resolve() throws -> Source.Element? {
        guard source.isTargetFrontmost else { throw SelectionFailure.changedApplication }
        // Keep the established application path unchanged when it succeeds.
        if let element = try source.applicationFocus() { return element }
        guard source.isTargetFrontmost else { throw SelectionFailure.changedApplication }
        if let element = try source.systemFocus() { return try checked(element) }
        guard source.isTargetFrontmost else { throw SelectionFailure.changedApplication }
        guard source.allowsAccessibilityPreparation,
              try source.prepareApplicationAccessibility() else { return nil }
        // One retry after a standard application-role query. No window traversal,
        // focus mutation, screen-reader flags, or retries following AX errors.
        guard source.isTargetFrontmost else { throw SelectionFailure.changedApplication }
        if let element = try source.applicationFocus() { return try checked(element) }
        guard source.isTargetFrontmost else { throw SelectionFailure.changedApplication }
        guard let element = try source.systemFocus() else { return nil }
        return try checked(element)
    }

    private func checked(_ element: Source.Element) throws -> Source.Element {
        // A global focus may have moved elsewhere. Inspect only its process ID
        // before allowing any role, selection, or text queries on that object.
        guard try source.processID(of: element) == targetPID, source.isTargetFrontmost else {
            throw SelectionFailure.changedApplication
        }
        return element
    }
}
