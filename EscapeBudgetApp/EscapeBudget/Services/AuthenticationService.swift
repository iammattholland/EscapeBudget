import Foundation
import LocalAuthentication
import Combine
import CryptoKit

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

    /// Whether app passcode authentication is enabled
    @Published var isPasscodeEnabled: Bool = false {
        didSet {
            if oldValue != isPasscodeEnabled {
                _ = KeychainService.shared.setBool(isPasscodeEnabled, forKey: .passcodeEnabled)
                if !isPasscodeEnabled {
                    _ = KeychainService.shared.remove(forKey: .passcodeHash)
                    isBiometricsEnabled = false
                }
            }
        }
    }

    /// The type of biometric available on the device
    @Published private(set) var biometricType: BiometricType = .none

    /// Timestamp when app was last authenticated
    private var lastAuthenticatedAt: Date?
    private let sessionTimeoutInterval: TimeInterval = 15 * 60
    private var sessionTimeoutTask: Task<Void, Never>?
    private var isAppActive: Bool = false

    /// Prevents multiple simultaneous authentication attempts
    @Published private(set) var shouldAutoAuthenticate: Bool = false

    private init() {
        // Load biometric setting from Keychain
        isBiometricsEnabled = KeychainService.shared.getBool(forKey: .biometricsEnabled) ?? false
        isPasscodeEnabled = KeychainService.shared.getBool(forKey: .passcodeEnabled) ?? false

        // Determine biometric type
        detectBiometricType()

        // If biometrics not enabled, unlock immediately
        if !isBiometricsEnabled && !isPasscodeEnabled {
            isLocked = false
        } else {
            // If biometrics enabled, flag that we should auto-authenticate on first appearance
            shouldAutoAuthenticate = isBiometricsEnabled
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
            return await authenticateWithDevicePasscode()
        }

        let reason = "Unlock Escape Budget to access your financial data"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: reason
            )

            if success {
                handleAuthenticationSuccess(method: biometricType.displayName)
            } else {
                handleAuthenticationFailure(method: biometricType.displayName)
            }

            return success
        } catch {
            handleAuthenticationFailure(method: biometricType.displayName)

            // If biometric failed, try device passcode only if app passcode isn't enabled
            if let laError = error as? LAError,
               laError.code == .userFallback || laError.code == .biometryLockout,
               !isPasscodeEnabled {
                return await authenticateWithDevicePasscode()
            }

            return false
        }
    }

    /// Authenticates using device passcode as fallback
    func authenticateWithDevicePasscode() async -> Bool {
        let context = LAContext()

        let reason = "Enter your passcode to unlock Escape Budget"

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: reason
            )

            if success {
                handleAuthenticationSuccess(method: "passcode")
            } else {
                handleAuthenticationFailure(method: "passcode")
            }

            return success
        } catch {
            handleAuthenticationFailure(method: "passcode")
            return false
        }
    }

    /// Verifies the app passcode
    func verifyAppPasscode(_ code: String) -> Bool {
        guard isPasscodeEnabled else { return false }
        guard let storedHash = KeychainService.shared.getString(forKey: .passcodeHash) else { return false }

        if hashPasscode(code) == storedHash {
            handleAuthenticationSuccess(method: "passcode")
            return true
        }

        handleAuthenticationFailure(method: "passcode")
        return false
    }

    /// Sets the app passcode (4+ digits recommended)
    func setPasscode(_ code: String) -> Bool {
        let hash = hashPasscode(code)
        let stored = KeychainService.shared.setString(hash, forKey: .passcodeHash)
        if stored {
            isPasscodeEnabled = true
            isLocked = false
            lastAuthenticatedAt = Date()
            restartSessionTimeoutMonitor()
        }
        return stored
    }

    /// Disables the app passcode
    func disablePasscode() {
        isPasscodeEnabled = false
        isLocked = false
        restartSessionTimeoutMonitor()
    }

    /// Called when app enters background
    func appDidEnterBackground() {
        SecurityLogger.shared.logAppBackground()
        isAppActive = false
        sessionTimeoutTask?.cancel()

        // When biometric lock is enabled, require authentication every time the app returns.
        if isBiometricsEnabled || isPasscodeEnabled {
            isLocked = true
            shouldAutoAuthenticate = isBiometricsEnabled
        }
    }

    /// Called when app becomes active.
    /// - Parameter cameFromBackground: true only when transitioning from `.background` to `.active`.
    func appDidBecomeActive(cameFromBackground: Bool) {
        SecurityLogger.shared.logAppForeground()
        isAppActive = true

        guard isBiometricsEnabled || isPasscodeEnabled else {
            isLocked = false
            shouldAutoAuthenticate = false
            sessionTimeoutTask?.cancel()
            return
        }

        // Require re-auth only when actually returning from background.
        if cameFromBackground {
            isLocked = true
            shouldAutoAuthenticate = isBiometricsEnabled
            sessionTimeoutTask?.cancel()
            return
        }

        // Relock only after session timeout when continuously active.
        if shouldRequireSessionTimeoutLock() {
            isLocked = true
            shouldAutoAuthenticate = isBiometricsEnabled
            sessionTimeoutTask?.cancel()
            return
        }

        restartSessionTimeoutMonitor()
    }

    /// Enables biometric authentication after successful verification
    func enableBiometrics() async -> Bool {
        guard isPasscodeEnabled else { return false }
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
                restartSessionTimeoutMonitor()
            }

            return success
        } catch {
            return false
        }
    }

    /// Disables biometric authentication
    func disableBiometrics() {
        isBiometricsEnabled = false
        isLocked = isPasscodeEnabled
        restartSessionTimeoutMonitor()
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

    private func handleAuthenticationSuccess(method: String) {
        isLocked = false
        lastAuthenticatedAt = Date()
        shouldAutoAuthenticate = false
        SecurityLogger.shared.logAuthenticationAttempt(success: true, method: method)
        restartSessionTimeoutMonitor()

        // Reset failure count
        _ = KeychainService.shared.remove(forKey: .authFailureCount)
    }

    private func handleAuthenticationFailure(method: String) {
        SecurityLogger.shared.logAuthenticationAttempt(success: false, method: method)
        // Note: For a full implementation, you'd track failure count and implement lockout
    }

    private func shouldRequireSessionTimeoutLock(now: Date = Date()) -> Bool {
        guard isBiometricsEnabled || isPasscodeEnabled else { return false }
        guard let lastAuthenticatedAt else { return true }
        return now.timeIntervalSince(lastAuthenticatedAt) >= sessionTimeoutInterval
    }

    private func restartSessionTimeoutMonitor() {
        sessionTimeoutTask?.cancel()

        guard isAppActive else { return }
        guard isBiometricsEnabled || isPasscodeEnabled else { return }
        guard !isLocked else { return }
        guard let lastAuthenticatedAt else { return }

        sessionTimeoutTask = Task { [weak self] in
            guard let self else { return }
            let elapsed = Date().timeIntervalSince(lastAuthenticatedAt)
            let remaining = max(0, sessionTimeoutInterval - elapsed)
            if remaining > 0 {
                try? await Task.sleep(nanoseconds: UInt64(remaining * 1_000_000_000))
            }
            if Task.isCancelled { return }
            await MainActor.run {
                guard self.isAppActive else { return }
                guard !self.isLocked else { return }
                guard self.shouldRequireSessionTimeoutLock() else { return }
                self.isLocked = true
                self.shouldAutoAuthenticate = self.isBiometricsEnabled
            }
        }
    }

    private func hashPasscode(_ code: String) -> String {
        let data = Data(code.utf8)
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
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
