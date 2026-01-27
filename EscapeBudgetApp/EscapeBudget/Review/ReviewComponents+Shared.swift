import SwiftUI
import SwiftData
import Charts

extension Transaction {
    var isCategorizedAsIncome: Bool {
        category?.group?.type == .income
    }
}

struct ReviewCalloutBar: View {
    struct Item: Identifiable {
        let id: String
        let systemImage: String
        let title: String
        let value: String?
        let tint: Color
        let action: (() -> Void)?
    }

    let title: String
    let items: [Item]
    var isVertical: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.small) {
            Text(title)
                .appSectionTitleText()

            if isVertical {
                VStack(spacing: AppTheme.Spacing.small) {
                    ForEach(items) { item in
                        if let action = item.action {
                            Button(action: action) {
                                ReviewCalloutChip(
                                    systemImage: item.systemImage,
                                    title: item.title,
                                    value: item.value,
                                    tint: item.tint,
                                    isFullWidth: true
                                )
                            }
                            .buttonStyle(.plain)
                        } else {
                            ReviewCalloutChip(
                                systemImage: item.systemImage,
                                title: item.title,
                                value: item.value,
                                tint: item.tint,
                                isFullWidth: true
                            )
                        }
                    }
                }
                .padding(.vertical, AppTheme.Spacing.micro)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: AppTheme.Spacing.small) {
                        ForEach(items) { item in
                            if let action = item.action {
                                Button(action: action) {
                                    ReviewCalloutChip(
                                        systemImage: item.systemImage,
                                        title: item.title,
                                        value: item.value,
                                        tint: item.tint
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                ReviewCalloutChip(
                                    systemImage: item.systemImage,
                                    title: item.title,
                                    value: item.value,
                                    tint: item.tint
                                )
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.micro)
                }
            }
        }
    }
}

private struct ReviewCalloutChip: View {
    let systemImage: String
    let title: String
    let value: String?
    let tint: Color
    var isFullWidth: Bool = false

    var body: some View {
        HStack(spacing: AppTheme.Spacing.compact) {
            Image(systemName: systemImage)
                .foregroundStyle(tint)

            VStack(alignment: .leading, spacing: AppTheme.Spacing.hairline) {
                Text(title)
                    .appCaptionText()
                    .fontWeight(.semibold)
                    .foregroundStyle(.primary)

                if let value, !value.isEmpty {
                    Text(value)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, AppTheme.Spacing.compact)
        .padding(.horizontal, AppTheme.Spacing.small)
        .frame(maxWidth: isFullWidth ? .infinity : nil, alignment: .leading)
        .frame(minWidth: isFullWidth ? nil : 150)
        .background(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.compact, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

struct MonthSwipeNavigationModifier: ViewModifier {
    @Binding var selectedDate: Date
    @State private var dragOffset: CGFloat = 0

    private let minimumDragDistance: CGFloat = 50

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(
                DragGesture(minimumDistance: 45)
                    .onChanged { value in
                        dragOffset = value.translation.width
                    }
                    .onEnded { value in
                        let calendar = Calendar.current

                        // Only trigger if horizontal swipe is dominant (more horizontal than vertical)
                        let horizontalDistance = abs(value.translation.width)
                        let verticalDistance = abs(value.translation.height)

                        guard horizontalDistance > verticalDistance else {
                            dragOffset = 0
                            return
                        }

                        // Swipe left (next month)
                        if value.translation.width < -minimumDragDistance {
                            if let nextMonth = calendar.date(byAdding: .month, value: 1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = nextMonth
                                }
                            }
                        }
                        // Swipe right (previous month)
                        else if value.translation.width > minimumDragDistance {
                            if let previousMonth = calendar.date(byAdding: .month, value: -1, to: selectedDate) {
                                withAnimation {
                                    selectedDate = previousMonth
                                }
                            }
                        }

                        dragOffset = 0
                    }
            , including: .gesture)
    }
}

extension View {
    func monthSwipeNavigation(selectedDate: Binding<Date>) -> some View {
        self.modifier(MonthSwipeNavigationModifier(selectedDate: selectedDate))
    }

    @ViewBuilder
    func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
