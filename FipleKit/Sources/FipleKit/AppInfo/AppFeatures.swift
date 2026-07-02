import Foundation

/// Compile-time feature flags shared by both apps.
///
/// `remoteFiles` gates the off-LAN file browsing feature (CloudKit). It is
/// **off** for the 1.0 App Store release so the submission is a clean LAN-only
/// remote — no iCloud entitlement, no folder-access exception, nothing for App
/// Review to question. The full implementation stays in the tree behind this
/// flag; flip it back on (and restore the iCloud/CloudKit entitlements) for the
/// 1.1 release once the CloudKit container is provisioned and the Mac folder
/// access is migrated to security-scoped bookmarks.
public enum AppFeatures {
    public static let remoteFiles = false
}
