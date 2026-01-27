import SwiftUI

struct DateRangeFilterHeader: View {
    enum FilterMode: String, CaseIterable, Identifiable {
        case month = "Month"
        case last3Months = "Last 3 Months"
        case year = "Year"
        case custom = "Custom Range"
        
        var id: String { rawValue }
    }
    
    @Binding var filterMode: FilterMode
    @Binding var date: Date
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    var isCompact: Bool = false
    
    @State private var showingCustomPicker = false
    @State private var showingModeDialog = false
    
    // Derived label based on mode
    private var labelText: String {
        let formatter = DateFormatter()
        switch filterMode {
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        case .last3Months:
            return "Last 3 Months"
        case .year:
            return date.formatted(.dateTime.year())
        case .custom:
            formatter.dateStyle = .short
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
    }
    
    var body: some View {
        HStack {
            // Left Arrow
            Button(action: previousPeriod) {
                Image(systemName: "chevron.left")
                    .font(isCompact ? .callout : .body)
                    .foregroundStyle(.primary)
                    .padding(isCompact ? AppTheme.Spacing.xSmall : AppTheme.Spacing.compact)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(filterMode == .custom || filterMode == .last3Months) 
            // Logical decision: disabling arrows for "Last 3 Months" as it's usually relative to "Now" 
            // or "Custom" as it's fixed. Could enable them if we defined logic, but for now disable.
            .opacity((filterMode == .custom || filterMode == .last3Months) ? 0.3 : 1.0)
            
            Spacer()
            
            Button {
                showingModeDialog = true
            } label: {
                Text(labelText)
                    .font(isCompact ? .subheadline.weight(.semibold) : .headline)
                    .foregroundStyle(.primary)
                    .padding(.vertical, isCompact ? AppTheme.Spacing.micro : AppTheme.Spacing.compact)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            
            Spacer()
            
            // Right Arrow
            Button(action: nextPeriod) {
                Image(systemName: "chevron.right")
                    .font(isCompact ? .callout : .body)
                    .foregroundStyle(.primary)
                    .padding(isCompact ? AppTheme.Spacing.xSmall : AppTheme.Spacing.compact)
                    .background(Color(.systemGray6))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(filterMode == .custom || filterMode == .last3Months)
            .opacity((filterMode == .custom || filterMode == .last3Months) ? 0.3 : 1.0)
        }
        .background(
            RoundedRectangle(cornerRadius: isCompact ? AppTheme.Radius.chromeCompact : AppTheme.Radius.chrome, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: isCompact ? AppTheme.Radius.chromeCompact : AppTheme.Radius.chrome, style: .continuous)
                .strokeBorder(Color(.separator), lineWidth: AppTheme.Stroke.subtle)
        )
        .confirmationDialog("Select Range", isPresented: $showingModeDialog, titleVisibility: .visible) {
            Button("This Month") {
                filterMode = .month
            }
            Button("Last 3 Months") {
                filterMode = .last3Months
            }
            Button("This Year") {
                filterMode = .year
            }
            Button("Custom Range...") {
                filterMode = .custom
                showingCustomPicker = true
            }
        }
        .sheet(isPresented: $showingCustomPicker) {
            NavigationStack {
                Form {
                    DatePicker("Start Date", selection: $customStartDate, displayedComponents: .date)
                    DatePicker("End Date", selection: $customEndDate, displayedComponents: .date)
                }
                .navigationTitle("Select Range")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { showingCustomPicker = false }
                    }
                }
                .presentationDetents([.medium])
                .solidPresentationBackground()
            }
        }
    }
    
    private func previousPeriod() {
        withAnimation {
            switch filterMode {
            case .month:
                date = Calendar.current.date(byAdding: .month, value: -1, to: date) ?? date
            case .year:
                date = Calendar.current.date(byAdding: .year, value: -1, to: date) ?? date
            default:
                break
            }
        }
    }
    
    private func nextPeriod() {
        withAnimation {
            switch filterMode {
            case .month:
                date = Calendar.current.date(byAdding: .month, value: 1, to: date) ?? date
            case .year:
                date = Calendar.current.date(byAdding: .year, value: 1, to: date) ?? date
            default:
                break
            }
        }
    }
}
