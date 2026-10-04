// AppViews
//
// SwiftUI views, view models and view utilities shared between the main app
// and the ShareExtension. iOS-only; logic that needs tests belongs in
// AppShared. This module is extension-API-safe: it must not use APIs that are
// unavailable in app extensions (e.g. UIApplication.shared). Extension-unsafe
// code lives in the app target instead.

/// Namespace marker for the AppViews module.
public enum AppViews {}
