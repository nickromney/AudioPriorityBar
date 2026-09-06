import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    var canManageLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathComponents.contains("Applications")
    }

    @Published private(set) var isEnabled = false
    @Published private(set) var requiresApproval = false
    @Published private(set) var errorMessage: String?

    private init() {
        refresh()
    }

    func setEnabled(_ enabled: Bool) {
        guard canManageLaunchAtLogin else { return }
        errorMessage = nil
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Could not change Open at Login. \(error.localizedDescription)"
        }
        refresh()
    }

    func refresh() {
        guard canManageLaunchAtLogin else { return }
        let status = SMAppService.mainApp.status
        requiresApproval = status == .requiresApproval
        isEnabled = status == .enabled || requiresApproval
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
