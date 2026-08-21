import Foundation
import ServiceManagement

@MainActor
class LaunchAtLoginManager: ObservableObject {
    static let shared = LaunchAtLoginManager()

    /// A checkout/build artifact must not register itself as a second login
    /// item alongside the installed app in ~/Applications or /Applications.
    var canManageLaunchAtLogin: Bool {
        Bundle.main.bundleURL.pathComponents.contains("Applications")
    }
    
    @Published var isEnabled: Bool {
        didSet {
            if isEnabled {
                enableLaunchAtLogin()
            } else {
                disableLaunchAtLogin()
            }
        }
    }
    
    private init() {
        // Check current status
        let isInstalledCopy = Bundle.main.bundleURL.pathComponents.contains("Applications")
        if isInstalledCopy, #available(macOS 13.0, *) {
            isEnabled = SMAppService.mainApp.status == .enabled
        } else {
            isEnabled = false
        }
    }
    
    private func enableLaunchAtLogin() {
        guard canManageLaunchAtLogin else { return }
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
            } catch {
                print("Failed to enable launch at login: \(error)")
                // Revert the toggle if registration fails
                DispatchQueue.main.async {
                    self.isEnabled = false
                }
            }
        }
    }
    
    private func disableLaunchAtLogin() {
        guard canManageLaunchAtLogin else { return }
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
            } catch {
                print("Failed to disable launch at login: \(error)")
            }
        }
    }
    
    func refresh() {
        guard canManageLaunchAtLogin else { return }
        if #available(macOS 13.0, *) {
            let newStatus = SMAppService.mainApp.status == .enabled
            if newStatus != isEnabled {
                // Update without triggering didSet
                _isEnabled = Published(wrappedValue: newStatus)
            }
        }
    }
}
