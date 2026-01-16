import SwiftUI

struct EmptyDataCard: View {
    let systemImage: String
    let title: String
    let message: String
    let actionTitle: String
    var action: (() -> Void)?
    var showDemoModeSuggestion: Bool = true

    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("isDemoMode") private var isDemoMode = false

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .semibold))
                .foregroundColor(.secondary)

            Text(title)
                .font(.headline)
                .foregroundColor(.primary)

            Text(message)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            if let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(EmptyDataCardActionButtonStyle(colorScheme: colorScheme))
                .controlSize(.regular)
                .font(.subheadline.weight(.semibold))
            }

            // Demo mode suggestion
            if showDemoModeSuggestion && !isDemoMode {
                VStack(spacing: 8) {
                    Divider()
                        .padding(.vertical, 4)

                    Text("Want to see how this works?")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button {
                        isDemoMode = true
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "sparkles")
                                .font(.caption)
                            Text("Try Demo Mode")
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(18)
        .padding(.vertical, 40)
        .padding(.horizontal)
    }
}

private struct EmptyDataCardActionButtonStyle: ButtonStyle {
    let colorScheme: ColorScheme

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(minHeight: 36)
            .foregroundStyle(foregroundColor(configuration: configuration))
            .background(backgroundColor(configuration: configuration))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(borderColor(configuration: configuration), lineWidth: 1)
            )
            .cornerRadius(10)
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
        return RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(configuration.isPressed ? base.opacity(0.85) : base)
    }

    private func borderColor(configuration: Configuration) -> Color {
        if colorScheme == .dark {
            return Color(.systemGray3).opacity(configuration.isPressed ? 0.6 : 0.9)
        }
        return Color(.systemGray3).opacity(configuration.isPressed ? 0.5 : 0.8)
    }
}
