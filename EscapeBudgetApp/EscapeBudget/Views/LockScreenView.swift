import SwiftUI

/// Lock screen displayed when biometric authentication is required
struct LockScreenView: View {
    @ObservedObject var authService: AuthenticationService
    @Environment(\.appColorMode) private var appColorMode
    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var hasAttemptedAutoAuth = false

    var body: some View {
        ZStack {
            // Fully opaque background for privacy - no transparency
            LinearGradient(
                colors: [Color(red: 0.1, green: 0.1, blue: 0.3), Color(red: 0.2, green: 0.1, blue: 0.3)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: AppTheme.Spacing.xxLarge) {
                Spacer()

                // App Icon / Lock Icon
                ZStack {
                    Circle()
                        .fill(AppColors.tint(for: appColorMode).opacity(0.12))
                        .frame(width: 120, height: 120)

                    Image(systemName: authService.biometricType.systemImage)
                        .appIcon(size: AppTheme.IconSize.emptyState)
                        .foregroundStyle(AppColors.tint(for: appColorMode))
                }

                // Title
                VStack(spacing: AppTheme.Spacing.compact) {
                    Text("Escape Budget")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Locked")
                        .appTitleText()
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Unlock Button
                VStack(spacing: AppTheme.Spacing.medium) {
                    Button {
                        authenticate()
                    } label: {
                        HStack(spacing: AppTheme.Spacing.tight) {
                            if isAuthenticating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            } else {
                                Image(systemName: authService.biometricType.systemImage)
                            }
                            Text(isAuthenticating ? "Authenticating..." : "Unlock with \(authService.biometricType.displayName)")
                        }
                        .font(AppTheme.Typography.buttonLabel.weight(.semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(AppColors.tint(for: appColorMode))
                        .cornerRadius(AppTheme.Radius.small)
                    }
                    .disabled(isAuthenticating)

                    if showError {
                        Text("Authentication failed. Please try again.")
                            .appCaptionText()
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                            .transition(.opacity)
                    }
                }
                .padding(.horizontal, AppTheme.Spacing.xxLarge)
                .padding(.bottom, AppTheme.Spacing.hero)
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
