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
    
    var body: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ScrollOffsetReader(coordinateSpace: scrollCoordinateSpace, id: scrollCoordinateSpace)
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
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(AppColors.tint(for: appColorMode).gradient)
                        Text("Add Widget")
                            .font(.headline)
                            .foregroundColor(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .background(Color(.systemBackground))
                    .cornerRadius(16)
                    .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
                }
            }
            .padding()
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
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(widget.title)
                    .font(.headline)
                    .fontWeight(.semibold)
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
                        .font(.caption)
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(Circle())
                }
            }
            
            // Render Content
            CustomWidgetRenderer(widget: widget)
                .frame(minHeight: 200)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(16)
        .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        .alert("Delete Widget?", isPresented: $showingDeleteAlert) {
            Button("Delete", role: .destructive) {
                modelContext.delete(widget)
            }
            Button("Cancel", role: .cancel) { }
        }
    }
}
