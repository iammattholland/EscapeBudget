import SwiftUI

struct CompactSearchBar: View {
    @Binding var text: String
    var placeholder: String = "Search"
    var showsBackground: Bool = true

    var body: some View {
        HStack(spacing: AppDesign.Theme.Spacing.compact) {
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
        .padding(.horizontal, showsBackground ? AppDesign.Theme.Spacing.tight : AppDesign.Theme.Spacing.compact)
        .padding(.vertical, showsBackground ? AppDesign.Theme.Spacing.xSmall : AppDesign.Theme.Spacing.compact)
        .background(showsBackground ? Color(.secondarySystemFill) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.compact, style: .continuous)
                .strokeBorder(
                    Color(.separator).opacity(showsBackground ? 1 : 0.6),
                    lineWidth: AppDesign.Theme.Stroke.subtle
                )
        )
    }
}
