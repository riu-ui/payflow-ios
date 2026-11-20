import Foundation
import LocalAuthentication

/// Face ID / Touch ID gate. The app locks on launch and when backgrounded.
/// No fallback password is stored by PAYFLOW — device passcode is the
/// only fallback, handled by the system LAContext itself.
@MainActor
final class BiometricAuthService: ObservableObject {
    @Published var isUnlocked = false
    @Published var biometryType: String = "Face ID"
    @Published var lastError: String?

    func biometryAvailable() -> Bool {
        let ctx = LAContext()
        var err: NSError?
        let ok = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err)
        if ok {
            biometryType = ctx.biometryType == .faceID ? "Face ID" : ctx.biometryType == .touchID ? "Touch ID" : "Biometrics"
        }
        return ok
    }

    func authenticate(reason: String = "Unlock PAYFLOW") async -> Bool {
        let ctx = LAContext()
        ctx.localizedCancelTitle = "Cancel"
        var err: NSError?
        guard ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &err) else {
            // Device without biometrics: fall back to device passcode, never a PAYFLOW password.
            return await authenticateWithPasscode()
        }
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason)
            isUnlocked = ok
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func authenticateWithPasscode() async -> Bool {
        let ctx = LAContext()
        do {
            let ok = try await ctx.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Unlock PAYFLOW with device passcode")
            isUnlocked = ok
            return ok
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    func lock() { isUnlocked = false }
}
