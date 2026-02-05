import SwiftUI
import SwiftData

struct CustomDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \CustomDashboardWidget.order) private var widgets: [CustomDashboardWidget]
    @Environment(\.appColorMode) private var appColorMode
    
    @State private var showingAddWidget = false
    @State private var selectedWidget: CustomDashboardWidget?
    
    // Date Navigation State
    @State private var selectedDate = Date()
    @State private var filterMode: DateRangeFilterHeader.FilterMode = .month
    @State private var customStartDate = Date()
    @State private var customEndDate = Date()
    private let scrollCoordinateSpace = "CustomDashboardView.scroll"
    private let topChrome: AnyView?

    init(topChrome: (() -> AnyView)? = nil) {
        self.topChrome = topChrome?()
    }
    
    var body: some View {
        ScrollView {
            AppChromeStack(topChrome: topChrome, scrollID: scrollCoordinateSpace) {
                LazyVStack(spacing: AppDesign.Theme.Spacing.medium) {
                    // Header
                    ForEach(widgets) { widget in
                        CustomWidgetContainer(widget: widget) {
                            selectedWidget = widget
                        }
                    }
                    
                    Button(action: {
                        selectedWidget = nil
                        showingAddWidget = true
                    }) {
                        VStack(spacing: AppDesign.Theme.Spacing.compact) {
                            Image(systemName: "plus.circle.fill")
                                .appIconLarge()
                                .foregroundStyle(AppDesign.Colors.tint(for: appColorMode).gradient)
                            Text("Add Widget")
                                .font(AppDesign.Theme.Typography.sectionTitle)
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 150)
                        .background(
                            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.card, style: .continuous)
                                .fill(.background)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.card, style: .continuous)
                                .stroke(Color(.separator).opacity(0.35))
                        )
                    }
                }
                .padding()
            }
        }
        .coordinateSpace(name: scrollCoordinateSpace)
        .background(Color(.systemGroupedBackground))
        .sheet(isPresented: $showingAddWidget) {
            WidgetEditorView(widget: .constant(nil))
                .presentationDetents([.medium, .large])
                .solidPresentationBackground()
        }
        .sheet(item: $selectedWidget) { widget in
            WidgetEditorView(widget: Binding(
                get: { widget },
                set: { _ in }
            ))
        }
    }
}

struct CustomWidgetContainer: View {
    let widget: CustomDashboardWidget
    let onEdit: () -> Void
    @Environment(\.modelContext) private var modelContext
    @State private var showingDeleteAlert = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
            HStack {
                Text(widget.title)
                    .font(AppDesign.Theme.Typography.sectionTitle)
                Spacer()
                
                Menu {
                    Button(action: onEdit) {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        showingDeleteAlert = true
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }
            
            // Render Content
            CustomWidgetRenderer(widget: widget)
                .frame(minHeight: 200)
        }
        .appElevatedCardSurface()
        .alert("Delete Widget?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(widget)
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
