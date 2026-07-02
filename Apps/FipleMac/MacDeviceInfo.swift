import Foundation
import FipleKit
import IOKit.ps

/// Detects this Mac's hardware family so the iPhone remote can show the right
/// device icon. The model identifier (`hw.model`) names the family directly on
/// Intel and some Apple-Silicon Macs; on the generic "MacNN,M" identifiers it
/// doesn't, so we fall back to battery presence to tell a laptop from a desktop.
enum MacDeviceInfo {
    /// Computed once — the hardware family never changes at runtime.
    static let current: MacKind = detect()

    private static func detect() -> MacKind {
        let model = (sysctlString("hw.model") ?? "").lowercased()

        // Descriptive identifiers (Intel + AS iMac) name the family outright.
        if model.hasPrefix("macbook") { return .laptop }
        if model.hasPrefix("imac") { return .iMac }
        if model.hasPrefix("macmini") { return .macMini }
        if model.hasPrefix("macstudio") { return .macStudio }
        if model.hasPrefix("macpro") { return .macPro }

        // Generic Apple-Silicon "MacNN,M": a battery means it's a laptop; without
        // one it's a desktop we can't pin down further, so report .desktop.
        return hasInternalBattery() ? .laptop : .desktop
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        // Drop the trailing NUL before decoding.
        if buffer.last == 0 { buffer.removeLast() }
        return String(decoding: buffer, as: UTF8.self)
    }

    private static func hasInternalBattery() -> Bool {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef]
        else { return false }

        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?
                .takeUnretainedValue() as? [String: Any],
                let type = desc[kIOPSTypeKey] as? String
            else { continue }
            if type == kIOPSInternalBatteryType { return true }
        }
        return false
    }
}
