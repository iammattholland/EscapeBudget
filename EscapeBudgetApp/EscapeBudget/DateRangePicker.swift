import SwiftUI

// MARK: - Date Range Type

enum DateRangeType: String, CaseIterable, Identifiable {
    case thisMonth = "This Month"
    case lastMonth = "Last Month"
    case last3Months = "Last 3 Months"
    case lastYear = "Last Year"
    case custom = "Custom Range"
    
    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .thisMonth: return "calendar"
        case .lastMonth: return "calendar.badge.clock"
        case .last3Months: return "calendar.badge.minus"
        case .lastYear: return "calendar.circle"
        case .custom: return "calendar.badge.plus"
        }
    }
    
    func dateRange(customStart: Date? = nil, customEnd: Date? = nil) -> (start: Date, end: Date) {
        let calendar = Calendar.current
        let now = Date()
        
        switch self {
        case .thisMonth:
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: start)!
            return (start, min(end, now))
            
        case .lastMonth:
            let thisMonthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: now))!
            let start = calendar.date(byAdding: .month, value: -1, to: thisMonthStart)!
            let end = calendar.date(byAdding: .day, value: -1, to: thisMonthStart)!
            return (start, end)
            
        case .last3Months:
            let start = calendar.date(byAdding: .month, value: -3, to: now)!
            return (start, now)
            
        case .lastYear:
            let start = calendar.date(byAdding: .year, value: -1, to: now)!
            return (start, now)
            
        case .custom:
            return (customStart ?? now, customEnd ?? now)
        }
    }
}

// MARK: - Date Range Picker View

struct DateRangePicker: View {
    @Binding var selectedRange: DateRangeType
    @Binding var customStartDate: Date
    @Binding var customEndDate: Date
    
    @State private var showingCustomPicker = false
    
    var body: some View {
        Menu {
            ForEach(DateRangeType.allCases) { range in
                Button {
                    withAnimation(.spring(response: 0.3)) {
                        selectedRange = range
                        if range == .custom {
                            showingCustomPicker = true
                        }
                    }
                } label: {
                    Label(range.rawValue, systemImage: range.icon)
                }
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: selectedRange.icon)
                    .font(.subheadline)
                
                Text(displayText)
                    .font(.subheadline)
                    .fontWeight(.medium)
                
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .fontWeight(.semibold)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
            )
        }
        .sheet(isPresented: $showingCustomPicker) {
            CustomDateRangeSheet(
                startDate: $customStartDate,
                endDate: $customEndDate,
                onDismiss: { showingCustomPicker = false }
            )
        }
    }
    
    private var displayText: String {
        if selectedRange == .custom {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return "\(formatter.string(from: customStartDate)) - \(formatter.string(from: customEndDate))"
        }
        return selectedRange.rawValue
    }
}

// MARK: - Month Year Picker

struct MonthYearPicker: View {
    @Binding var selectedDate: Date
    
    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: selectedDate)
    }

    
    var body: some View {
        HStack(spacing: 16) {
            Button(action: previousMonth) {
                Image(systemName: "chevron.left")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.systemGray6)))
            }
            
            Text(formattedDate)
                .font(.headline)
                .frame(minWidth: 140)
            
            Button(action: nextMonth) {
                Image(systemName: "chevron.right")
                    .font(.body)
                    .fontWeight(.semibold)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Color(.systemGray6)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 8, y: 2)
        )
    }
    
    private func previousMonth() {
        withAnimation {
            selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
        }
    }
    
    private func nextMonth() {
        withAnimation {
            selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate
        }
    }
}

// MARK: - Custom Date Range Sheet

struct CustomDateRangeSheet: View {
    @Binding var startDate: Date
    @Binding var endDate: Date
    let onDismiss: () -> Void
    
    @State private var tempStartDate: Date
    @State private var tempEndDate: Date
    
    private let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: Date()) ?? Date()
    private let today = Date()
    
    init(startDate: Binding<Date>, endDate: Binding<Date>, onDismiss: @escaping () -> Void) {
        self._startDate = startDate
        self._endDate = endDate
        self.onDismiss = onDismiss
        self._tempStartDate = State(initialValue: startDate.wrappedValue)
        self._tempEndDate = State(initialValue: endDate.wrappedValue)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    DatePicker(
                        "Start Date",
                        selection: $tempStartDate,
                        in: oneYearAgo...today,
                        displayedComponents: .date
                    )
                    .onChange(of: tempStartDate) { _, newValue in
                        // Ensure end date is not before start date
                        if tempEndDate < newValue {
                            tempEndDate = newValue
                        }
                    }
                    
                    DatePicker(
                        "End Date",
                        selection: $tempEndDate,
                        in: tempStartDate...today,
                        displayedComponents: .date
                    )
                } header: {
                    Text("Select Date Range")
                } footer: {
                    Text("You can select a range up to one year from today.")
                        .foregroundColor(.secondary)
                }
                
                Section {
                    // Quick presets
                    Button("Last 7 Days") {
                        tempStartDate = Calendar.current.date(byAdding: .day, value: -7, to: today) ?? today
                        tempEndDate = today
                    }
                    
                    Button("Last 30 Days") {
                        tempStartDate = Calendar.current.date(byAdding: .day, value: -30, to: today) ?? today
                        tempEndDate = today
                    }
                    
                    Button("Last 6 Months") {
                        tempStartDate = Calendar.current.date(byAdding: .month, value: -6, to: today) ?? today
                        tempEndDate = today
                    }
                } header: {
                    Text("Quick Presets")
                }
            }
            .navigationTitle("Custom Range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                    }
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        startDate = tempStartDate
                        endDate = tempEndDate
                        onDismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
        .solidPresentationBackground()
    }
}

// MARK: - Date Range Summary View

struct DateRangeSummaryView: View {
    let rangeType: DateRangeType
    let customStart: Date
    let customEnd: Date
    
    private var dateRange: (start: Date, end: Date) {
        rangeType.dateRange(customStart: customStart, customEnd: customEnd)
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Text(formattedRange)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private var formattedRange: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: dateRange.start)) – \(formatter.string(from: dateRange.end))"
    }
}

#Preview {
    VStack(spacing: 20) {
        DateRangePicker(
            selectedRange: .constant(.thisMonth),
            customStartDate: .constant(Date()),
            customEndDate: .constant(Date())
        )
        
        MonthYearPicker(selectedDate: .constant(Date()))
        
        DateRangeSummaryView(
            rangeType: .thisMonth,
            customStart: Date(),
            customEnd: Date()
        )
    }
    .padding()
}
