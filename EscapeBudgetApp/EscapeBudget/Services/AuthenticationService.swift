import Foundation
import LocalAuthentication
import Combine

/// Manages app authentication state and biometric authentication.
@MainActor
final class AuthenticationService: ObservableObject {
    static let shared = AuthenticationService()

    /// Whether the app is currently locked and requires authentication
    @Published private(set) var isLocked: Bool = true

    /// Whether biometric authentication is enabled
    @Published var isBiometricsEnabled: Bool = false {
        didSet {
            if oldValue != isBiometricsEnabled {
                _ = KeychainService.shared.setBool(isBiometricsEnabled, forKey: .biometricsEnabled)
                if isBiometricsEnabled {
                    SecurityLogger.shared.logBiometricEnabled()
                } else {
                    SecurityLogger.shared.logBiometricDisabled()
                }
            }
        }
    }

    /// The type of biometric available on the device
    @Published private(set) var biometricType: BiometricType = .none

    /// Timestamp when app was last authenticated
    private var lastAuthenticatedAt: Date?

    /// Prevents multiple simultaneous authentication attempts
    @Published private(set) var shouldAutoAuthenticate: Bool = false

    private init() {
        // Load biometric setting from Keychain
        isBiometricsEnabled = KeychainService.shared.getBool(forKey: .biometricsEnabled) ?? false

        // Determine biometric type
        detectBiometricType()

        // If biometrics not enabled, unlock immediately
        if !isBiometricsEnabled {
            isLocked = false
        } else {
            // If biometrics enabled, flag that we should auto-authenticate on first appearance
            shouldAutoAuthenticate = true
        }

        // Log app launch
        SecurityLogger.shared.logAppLaunch()
    }

    // MARK: - Public API

    /// Attempts biometric authentication
    func authenticate() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometrics not available, fall back to passcode
            return await authenticateWithPasscode()
        }

        let reason = "Unlock Escape Budget to access your financial data"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                handleAuthenticationSuccess()
            } else {
                handleAuthenticationFailure(method: biometricType.displayName)
            }

            return success
        } catch {
            handleAuthenticationFailure(method: biometricType.displayName)

            // If biometric failed, try passcode as fallback
            if let laError = error as? LAError,
               laError.code == .userFallback || laError.code == .biometryLockout {
                return await authenticateWithPasscode()
            }

            return false
        }
    }

    /// Authenticates using device passcode as fallback
    func authenticateWithPasscode() async -> Bool {
        let context = LAContext()

        let reason = "Enter your passcode to unlock Escape Budget"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )

            if success {
                handleAuthenticationSuccess()
            } else {
                handleAuthenticationFailure(method: "passcode")
            }

            return success
        } catch {
            handleAuthenticationFailure(method: "passcode")
            return false
        }
    }

    /// Called when app enters background
    func appDidEnterBackground() {
        SecurityLogger.shared.logAppBackground()

        // When biometric lock is enabled, require authentication every time the app returns.
        if isBiometricsEnabled {
            isLocked = true
            shouldAutoAuthenticate = true
        }
    }

    /// Called when app enters foreground - determines if re-auth is needed
    func appWillEnterForeground() {
        SecurityLogger.shared.logAppForeground()

        guard isBiometricsEnabled else {
            isLocked = false
            return
        }

        // Always require authentication after returning from background.
        isLocked = true
        shouldAutoAuthenticate = true
    }

    /// Enables biometric authentication after successful verification
    func enableBiometrics() async -> Bool {
        let context = LAContext()
        var error: NSError?

        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            return false
        }

        let reason = "Authenticate to enable \(biometricType.displayName) lock"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                isBiometricsEnabled = true
                isLocked = false
                lastAuthenticatedAt = Date()
            }

            return success
        } catch {
            return false
        }
    }

    /// Disables biometric authentication
    func disableBiometrics() {
        isBiometricsEnabled = false
        isLocked = false
    }

    /// Resets the auto-authentication flag
    /// Called when authentication is cancelled or completed
    func resetAutoAuthenticate() {
        shouldAutoAuthenticate = false
    }

    // MARK: - Private

    private func detectBiometricType() {
        let context = LAContext()
        var error: NSError?

        // First check if biometrics are available at all
        let canEvaluate = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)

        // Even if canEvaluate is false, we can still check biometryType
        // to show the correct icon/label (user might need to enroll)
        switch context.biometryType {
        case .faceID:
            biometricType = .faceID
        case .touchID:
            biometricType = .touchID
        case .opticID:
            biometricType = .opticID
        case .none:
            biometricType = .none
        @unknown default:
            biometricType = .none
        }

        // If biometrics available but not enrolled, we still show the option
        // but it will prompt user to enroll when they try to enable
        if !canEvaluate {
            if let laError = error as? LAError {
                switch laError.code {
                case .biometryNotEnrolled:
                    // Biometry hardware exists but not enrolled - keep the detected type
                    // User will be prompted to enroll when they try to authenticate
                    break
                case .biometryNotAvailable:
                    // No biometry hardware
                    biometricType = .none
                default:
                    break
                }
            }
        }
    }

    private func handleAuthenticationSuccess() {
        isLocked = false
        lastAuthenticatedAt = Date()
        shouldAutoAuthenticate = false
        SecurityLogger.shared.logAuthenticationAttempt(success: true, method: biometricType.displayName)

        // Reset failure count
        _ = KeychainService.shared.remove(forKey: .authFailureCount)
    }

    private func handleAuthenticationFailure(method: String) {
        SecurityLogger.shared.logAuthenticationAttempt(success: false, method: method)
        // Note: For a full implementation, you'd track failure count and implement lockout
    }
}

// MARK: - Biometric Type

enum BiometricType {
    case none
    case touchID
    case faceID
    case opticID

    var displayName: String {
        switch self {
        case .none: return "Biometric"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        }
    }

    var systemImage: String {
        switch self {
        case .none: return "lock"
        case .touchID: return "touchid"
        case .faceID: return "faceid"
        case .opticID: return "opticid"
        }
    }
}
