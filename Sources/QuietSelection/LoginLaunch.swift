import ServiceManagement

enum LoginLaunch {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var statusCode: String {
        switch status {
        case .enabled: return "enabled"
        case .notRegistered: return "not_registered"
        case .requiresApproval: return "requires_approval"
        case .notFound: return "not_found"
        @unknown default: return "unknown"
        }
    }

    static func enable() throws {
        if status == .enabled || status == .requiresApproval { return }
        try SMAppService.mainApp.register()
    }

    static func disable() throws {
        if status == .notRegistered { return }
        try SMAppService.mainApp.unregister()
    }

    static func openSettings() { SMAppService.openSystemSettingsLoginItems() }
}
