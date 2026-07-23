import Foundation
import ServiceManagement

/// Launch-at-login via ServiceManagement (macOS 13+). Registers the running
/// .app bundle itself as a login item. Only works from a real bundle, not
/// from `swift run`, so callers should tolerate a thrown error.
public enum LoginItem {
    public static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    public static func setEnabled(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("PortSight login-item toggle failed: \(error.localizedDescription)")
            return false
        }
    }
}
