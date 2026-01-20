import SwiftUI

struct EmptyDataCard: View {
    let systemImage: String
    let title: String
    let message: String
    var actionTitle: String = ""
    var action: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: AppTheme.Spacing.medium) {
            Image(systemName: systemImage)
                .font(.system(size: AppTheme.IconSize.large, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(title)
                .font(AppTheme.Typography.sectionTitle)
                .foregroundStyle(.primary)

            Text(message)
                .font(AppTheme.Typography.secondaryBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let action, !actionTitle.isEmpty {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(EmptyDataCardActionButtonStyle(colorScheme: colorScheme))
                .controlSize(.regular)
                .font(AppTheme.Typography.buttonLabel.weight(.semibold))
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.card, style: .continuous))
        .padding(.vertical, AppTheme.Spacing.xxLarge)
        .padding(.horizontal, AppTheme.Spacing.screenHorizontal)
    }
}

private struct EmptyDataCardActionButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, AppTheme.Spacing.cardPadding)
            .padding(.vertical, AppTheme.Spacing.small)
            .frame(minHeight: 36)
            .foregroundStyle(foregroundColor(configuration: configuration))
            .background(backgroundColor(configuration: configuration))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
                    .strokeBorder(borderColor(configuration: configuration), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func foregroundColor(configuration: Configuration) -> Color {
        switch colorScheme {
        case .dark:
            return configuration.isPressed ? .white.opacity(0.9) : .white
        default:
            return configuration.isPressed ? .black.opacity(0.9) : .black
        }
    }

    private func backgroundColor(configuration: Configuration) -> some View {
        let base: Color = (colorScheme == .dark) ? Color(.systemGray6) : .white
        return RoundedRectangle(cornerRadius: AppTheme.Radius.button, style: .continuous)
            .fill(configuration.isPressed ? base.opacity(0.85) : base)
    }

    private func borderColor(configuration: Configuration) -> Color {
        if colorScheme == .dark {
            return Color(.systemGray3).opacity(configuration.isPressed ? 0.6 : 0.9)
        }
        return Color(.systemGray3).opacity(configuration.isPressed ? 0.5 : 0.8)
    }
}
