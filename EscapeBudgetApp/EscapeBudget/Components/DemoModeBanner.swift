import SwiftUI

struct DemoModeBanner: View {
    @AppStorage("isDemoMode") private var isDemoMode = false
    @State private var showingTurnOffConfirm = false
    var isVisible: Bool = true

    var body: some View {
        if isDemoMode, isVisible {
            Button {
                showingTurnOffConfirm = true
            } label: {
                HStack(spacing: AppTheme.Spacing.compact) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 8, height: 8)

                    Text("Demo Mode On")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal, AppTheme.Spacing.small)
                .padding(.vertical, AppTheme.Spacing.xSmall)
                .background(
                    Capsule(style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Demo mode is on. Tap to turn off.")
            .transition(.opacity.combined(with: .move(edge: .top)))
            .confirmationDialog("Turn off Demo Mode?", isPresented: $showingTurnOffConfirm, titleVisibility: .visible) {
                Button("Turn Off Demo Mode", role: .destructive) {
                    isDemoMode = false
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will switch you back to your real data.")
            }
        }
    }
}
