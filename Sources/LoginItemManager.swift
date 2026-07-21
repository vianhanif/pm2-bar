import Foundation
import ServiceManagement

enum LoginItemManager {
    private static let userDefaultsKey = "launchAtLoginEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: userDefaultsKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: userDefaultsKey)
            apply(newValue)
        }
    }

    static var requiresApproval: Bool {
        if #available(macOS 14.0, *) {
            return SMAppService.mainApp.status == .requiresApproval
        }
        return false
    }

    static func refreshStatus() {
        let enabled: Bool
        if #available(macOS 13.0, *) {
            enabled = SMAppService.mainApp.status == .enabled
        } else {
            enabled = false
        }
        // Sync stored pref with actual state (user may have changed via System Settings)
        if UserDefaults.standard.object(forKey: userDefaultsKey) != nil {
            UserDefaults.standard.set(enabled, forKey: userDefaultsKey)
        }
    }

    private static func apply(_ enable: Bool) {
        guard isBundled else {
            print("Login item requires a .app bundle — run `swift build -c release` and create an app bundle")
            return
        }

        do {
            if enable {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to \(enable ? "enable" : "disable") login item: \(error)")
        }
    }

    /// True when running inside a proper .app bundle (required for SMAppService)
    static var isBundled: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }
}
