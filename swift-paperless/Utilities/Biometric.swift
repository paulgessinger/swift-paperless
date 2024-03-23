import LocalAuthentication

func biometricAuthenticate() async throws -> Bool {
    let context = LAContext()
    var error: NSError?
    let reason = String(localized: .settings.biometricReason)

    guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
        if let error {
            throw error
        } else {
            return false
        }
    }

    return try await context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
}

func getBiometricName() -> String? {
    var error: NSError?
    let laContext = LAContext()

    if !laContext.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
        return nil
    }

    switch laContext.biometryType {
    case .touchID:
        return "TouchID"
    case .faceID:
        return "FaceID"
    case .none, .opticID:
        fallthrough
    @unknown default:
        return nil
    }
}
