import SwiftUI

struct PasscodeEntryView: View {
    let title: String
    let subtitle: String?
    let showsBiometricButton: Bool
    let biometricTitle: String
    let onBiometricTap: () -> Void
    let onComplete: (String) -> Void
    @Binding var showError: Bool
    let errorMessage: String

    @State private var code: String = ""
    @Environment(\.appColorMode) private var appColorMode

    private let codeLength = 4
    private let keypadColumns = Array(repeating: GridItem(.flexible(), spacing: 16), count: 3)

    var body: some View {
        VStack(spacing: AppDesign.Theme.Spacing.large) {
            VStack(spacing: AppDesign.Theme.Spacing.compact) {
                Text(title)
                    .appTitleText()
                    .fontWeight(.semibold)

                if let subtitle {
                    Text(subtitle)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: AppDesign.Theme.Spacing.compact) {
                ForEach(0..<codeLength, id: \.self) { index in
                    Circle()
                        .strokeBorder(.secondary.opacity(0.3), lineWidth: 1)
                        .background(
                            Circle()
                                .fill(index < code.count ? AppDesign.Colors.tint(for: appColorMode) : .clear)
                        )
                        .frame(width: 14, height: 14)
                }
            }

            if showError {
                Text(errorMessage)
                    .appCaptionText()
                    .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
            }

            LazyVGrid(columns: keypadColumns, spacing: 16) {
                ForEach(1...9, id: \.self) { number in
                    keypadButton(label: "\(number)") {
                        appendDigit("\(number)")
                    }
                }

                keypadButton(label: "⌫", isSecondary: true) {
                    removeDigit()
                }

                keypadButton(label: "0") {
                    appendDigit("0")
                }

                keypadButton(label: "Clear", isSecondary: true) {
                    clearCode()
                }
            }
            .padding(.horizontal, AppDesign.Theme.Spacing.xLarge)

            if showsBiometricButton {
                Button(biometricTitle) {
                    onBiometricTap()
                }
                .appSecondaryCTA()
            }
        }
        .padding(.vertical, AppDesign.Theme.Spacing.large)
        .onChange(of: showError) { _, newValue in
            if newValue {
                clearCode()
            }
        }
    }

    private func appendDigit(_ digit: String) {
        guard code.count < codeLength else { return }
        code.append(digit)
        showError = false

        if code.count == codeLength {
            let entered = code
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                onComplete(entered)
            }
        }
    }

    private func removeDigit() {
        guard !code.isEmpty else { return }
        code.removeLast()
        showError = false
    }

    private func clearCode() {
        code = ""
        showError = false
    }

    @ViewBuilder
    private func keypadButton(label: String, isSecondary: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(AppDesign.Theme.Typography.sectionTitle)
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(isSecondary ? .secondary : .primary)
                .background(
                    RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.small)
                        .fill(Color(.systemGray6))
                )
        }
        .buttonStyle(.plain)
    }
}
