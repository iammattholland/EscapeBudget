import SwiftUI

struct TopChromeTabs<Selection: Hashable>: View {
    struct Tab: Identifiable {
        let id: Selection
        let title: String

        init(id: Selection, title: String) {
            self.id = id
            self.title = title
        }
    }

    @Binding var selection: Selection
    let tabs: [Tab]
    var isCompact: Bool = false

    @Namespace private var namespace

    var body: some View {
        HStack(spacing: 0) {
            ForEach(tabs) { tab in
                Button {
#if canImport(UIKit)
                    KeyboardUtilities.dismiss()
#endif
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = tab.id
                    }
                } label: {
                    Text(tab.title)
                        .font(AppTheme.Typography.tabLabel)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .allowsTightening(true)
                        .foregroundStyle(selection == tab.id ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, AppTheme.Spacing.compact)
                        .contentShape(Rectangle())
                        .background {
                            if selection == tab.id {
                                RoundedRectangle(cornerRadius: AppTheme.Radius.tabsSelection, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                                    .matchedGeometryEffect(id: "TopChromeTabs.selection", in: namespace)
                                    .padding(AppTheme.Spacing.hairline)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab.id ? [.isSelected] : [])
            }
        }
        .padding(AppTheme.Spacing.hairline)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.tabsOuter, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.tabsOuter, style: .continuous)
                .strokeBorder(Color.primary.opacity(AppTheme.Stroke.subtleOpacity), lineWidth: AppTheme.Stroke.subtle)
        )
        .topChromeSegmentedStyle(isCompact: isCompact)
    }
}
