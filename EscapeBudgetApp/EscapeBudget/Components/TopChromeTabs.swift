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
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == tab.id ? .primary : .secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background {
                            if selection == tab.id {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(Color(.tertiarySystemFill))
                                    .matchedGeometryEffect(id: "TopChromeTabs.selection", in: namespace)
                                    .padding(2)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == tab.id ? [.isSelected] : [])
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemFill))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
        .topChromeSegmentedStyle(isCompact: isCompact)
    }
}

