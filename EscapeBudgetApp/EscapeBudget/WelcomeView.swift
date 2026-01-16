import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    let onTryDemo: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 60, weight: .light))
                        .foregroundColor(.accentColor)

                    Text("Welcome to Escape\u{00A0}Budget")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .minimumScaleFactor(0.85)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 12)

                    Text("Your personal finance companion for tracking spending, managing budgets, and achieving your goals.")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                VStack(alignment: .leading, spacing: 16) {
                    FeatureRow(icon: "chart.bar.doc.horizontal", title: "Track every dollar", detail: "Import transactions and see where your money goes")
                    FeatureRow(icon: "target", title: "Reach your goals", detail: "Save for vacations, gadgets, or emergencies")
                    FeatureRow(icon: "brain.head.profile", title: "Smart insights", detail: "Get personalized tips based on your spending")
                }
                .padding()
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))

                Spacer()

                VStack(spacing: 12) {
                    // Primary action: Try Demo
                    Button(action: onTryDemo) {
                        VStack(spacing: 4) {
                            Text("Guided Introduction")
                                .font(.headline)
                            Text("Explore the app with sample data")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                    // Secondary action: Start Fresh
                    Button(action: onContinue) {
                        Text("Start Fresh")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    EmptyView()
                }
            }
        }
    }

    private struct FeatureRow: View {
        let icon: String
        let title: String
        let detail: String

        var body: some View {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title3)
                    .frame(width: 32, height: 32)
                    .foregroundColor(.accentColor)
                    .background(Circle().fill(Color(.tertiarySystemFill)))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
