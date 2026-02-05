import SwiftUI

struct WelcomeView: View {
    let onContinue: () -> Void
    let onImport: () -> Void
    let onTryDemo: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: AppDesign.Theme.Spacing.xxLarge) {
                Spacer()

                VStack(spacing: AppDesign.Theme.Spacing.tight) {
                    Image("RocketLogo")
                        .resizable()
                        .scaledToFill()
                        .frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.chrome, style: .continuous))
                        .clipped()

                    Text("Escape Budget")
                        .appLargeTitleBoldText()
                        .multilineTextAlignment(.center)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .allowsTightening(true)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, AppDesign.Theme.Spacing.tight)

                    Text("Your personal finance companion for tracking spending, managing budgets, and achieving your goals.")
                        .font(AppDesign.Theme.Typography.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)
                }

                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.medium) {
                    FeatureRow(icon: "chart.bar.doc.horizontal", title: "Track every dollar", detail: "Import transactions and see where your money goes")
                    FeatureRow(icon: "target", title: "Reach your goals", detail: "Save for vacations, gadgets, or emergencies")
                    FeatureRow(icon: "brain.head.profile", title: "Smart insights", detail: "Get personalized tips based on your spending")
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.card, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )

                Spacer()

                VStack(spacing: AppDesign.Theme.Spacing.tight) {
                    // Primary action: Start Fresh
                    Button(action: onContinue) {
                        Text("Start Fresh")
                            .appPrimaryButtonLabel()
                    }
                    .appPrimaryCTA(controlSize: .large)

                    Button(action: onImport) {
                        Text("From Import")
                            .appSecondaryButtonLabel()
                    }
                    .appSecondaryCTA(controlSize: .large)

                    Button(action: onTryDemo) {
                        VStack(spacing: AppDesign.Theme.Spacing.micro) {
                            Text("Guided Introduction")
                                .appSecondaryButtonLabel()
                            Text("Explore the app with sample data")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, AppDesign.Theme.Spacing.micro)
                    }
                    .appSecondaryCTA(controlSize: .large)
                }
            }
            .appAdaptiveScreenPadding()
            .appConstrainContentWidth()
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
            HStack(alignment: .top, spacing: AppDesign.Theme.Spacing.tight) {
                Image(systemName: icon)
                    .appTitleText()
                    .frame(width: 32, height: 32)
                    .foregroundStyle(Color.accentColor)
                    .background(Circle().fill(Color(.tertiarySystemFill)))

                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                    Text(title)
                        .appSectionTitleText()
                    Text(detail)
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

#Preview("Welcome • iPhone (Light)") {
    WelcomeView(onContinue: {}, onImport: {}, onTryDemo: {})
        .preferredColorScheme(.light)
}

#Preview("Welcome • iPhone (Dark)") {
    WelcomeView(onContinue: {}, onImport: {}, onTryDemo: {})
        .preferredColorScheme(.dark)
}

#Preview("Welcome • iPad (Dark)") {
    WelcomeView(onContinue: {}, onImport: {}, onTryDemo: {})
        .preferredColorScheme(.dark)
}
