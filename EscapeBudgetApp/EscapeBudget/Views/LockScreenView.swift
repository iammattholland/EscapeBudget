import SwiftUI

/// Lock screen displayed when biometric authentication is required
struct LockScreenView: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.appColorMode) private var appColorMode
    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var hasAttemptedAutoAuth = false
    @State private var passcodeError = false

    var body: some View {
        ZStack {
            // Fully opaque background for privacy - no transparency
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.2, green: 0.1, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppDesign.Theme.Spacing.xxLarge) {
                Spacer()

                // App Icon / Lock Icon
                ZStack {
                    Circle()
                        .fill(AppDesign.Colors.tint(for: appColorMode).opacity(0.12))
                        .frame(width: 120, height: 120)

                    Image(systemName: authService.isBiometricsEnabled ? authService.biometricType.systemImage : "lock.fill")
                        .appIcon(size: AppDesign.Theme.IconSize.emptyState)
                        .foregroundStyle(AppDesign.Colors.tint(for: appColorMode))
                }

                // Title
                VStack(spacing: AppDesign.Theme.Spacing.compact) {
                    Text("Escape Budget")
                        .appLargeTitleText()
                        .fontWeight(.bold)

                    Text("Locked")
                        .appTitleText()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if authService.isPasscodeEnabled {
                    PasscodeEntryView(
                        title: "Enter Passcode",
                        subtitle: authService.isBiometricsEnabled ? "You can also unlock with \(authService.biometricType.displayName)" : nil,
                        showsBiometricButton: authService.isBiometricsEnabled,
                        biometricTitle: "Unlock with \(authService.biometricType.displayName)",
                        resetKey: 0,
                        onBiometricTap: authenticate,
                        onComplete: { code in
                            let success = authService.verifyAppPasscode(code)
                            if !success {
                                passcodeError = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    passcodeError = false
                                }
                            } else {
                                passcodeError = false
                            }
                        },
                        showError: $passcodeError,
                        errorMessage: "Incorrect passcode. Try again."
                    )
                    .padding(.horizontal, AppDesign.Theme.Spacing.xxLarge)
                    .padding(.bottom, AppDesign.Theme.Spacing.hero)
                } else {
                    // Unlock Button (biometrics-only)
                    VStack(spacing: AppDesign.Theme.Spacing.medium) {
                        Button {
                            authenticate()
                        } label: {
                            HStack(spacing: AppDesign.Theme.Spacing.tight) {
                                if isAuthenticating {
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                } else {
                                    Image(systemName: authService.biometricType.systemImage)
                                }
                                Text(isAuthenticating ? "Authenticating..." : "Unlock with \(authService.biometricType.displayName)")
                            }
                            .font(AppDesign.Theme.Typography.buttonLabel.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(AppDesign.Colors.tint(for: appColorMode))
                            .cornerRadius(AppDesign.Theme.Radius.small)
                        }
                        .disabled(isAuthenticating)

                        if showError {
                            Text("Authentication failed. Please try again.")
                                .appCaptionText()
                                .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                                .transition(.opacity)
                        }
                    }
                    .padding(.horizontal, AppDesign.Theme.Spacing.xxLarge)
                    .padding(.bottom, AppDesign.Theme.Spacing.hero)
                }
            }
        }
        .task {
            // Only auto-authenticate once per view instance
            guard !hasAttemptedAutoAuth else { return }
            guard authService.shouldAutoAuthenticate else { return }

            hasAttemptedAutoAuth = true

            // Small delay to ensure UI is fully rendered before showing biometric prompt
            try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

            // Check we're still locked (user might have disabled biometrics)
            if authService.isLocked {
                authenticate()
            }
        }
    }

    private func authenticate() {
        guard !isAuthenticating else { return }

        isAuthenticating = true
        showError = false

        Task {
            // Reset auto-authenticate flag so we don't auto-trigger again
            authService.resetAutoAuthenticate()

            let success = await authService.authenticate()

            await MainActor.run {
                isAuthenticating = false
                if !success {
                    withAnimation {
                        showError = true
                    }

                    // Hide error after delay
                    Task {
                        try? await Task.sleep(nanoseconds: 3_000_000_000)
                        await MainActor.run {
                            withAnimation {
                                showError = false
                            }
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    LockScreenView(authService: AuthenticationService.shared)
}
