// AppShared
//
// Code shared between the main app and the ShareExtension. This module is
// extension-API-safe: it must not use APIs that are unavailable in app
// extensions (e.g. UIApplication.shared). Extension-unsafe code lives in the
// app target instead.

/// Namespace marker for the AppShared module.
public enum AppShared {}
