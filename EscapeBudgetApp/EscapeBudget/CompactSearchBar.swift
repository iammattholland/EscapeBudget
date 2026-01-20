import SwiftUI

struct CompactSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var showsBackground: Bool = true

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, showsBackground ? AppTheme.Spacing.tight : AppTheme.Spacing.micro)
        .padding(.vertical, showsBackground ? AppTheme.Spacing.xSmall : AppTheme.Spacing.micro)
        .background(showsBackground ? Color(.secondarySystemFill) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous))
    }
}
