import SwiftUI

struct AppSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
            Text(title)
                .appSectionTitleText()
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .appSecondaryBodyText()
                    .foregroundStyle(.secondary)
            }
        }
    }
}

