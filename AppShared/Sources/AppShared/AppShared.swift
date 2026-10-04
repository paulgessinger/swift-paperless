// AppShared
//
// App logic shared between the main app and the ShareExtension: stores,
// repositories, connection management, error types and the localization
// catalogs. It builds for iOS and macOS so its tests run on the host; SwiftUI
// views and UIKit-dependent code live in AppViews. This module is
// extension-API-safe: it must not use APIs that are unavailable in app
// extensions (e.g. UIApplication.shared).

/// Namespace marker for the AppShared module.
public enum AppShared {}
