
import SwiftUI
import SwiftData
import UserNotifications

struct SpendingForecastView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var navigator: AppNavigator
    @Query(sort: \RecurringPurchase.nextDate) private var recurringPurchases: [RecurringPurchase]
    @Query(sort: \PurchasePlan.purchaseDate) private var purchasePlans: [PurchasePlan]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @AppStorage("billReminders") private var billReminders = true
    @Environment(\.appColorMode) private var appColorMode

    @State private var viewMode: ViewMode = .list
    @State private var showingAddRecurring = false
    @State private var showingSettings = false
    @StateObject private var notificationService = NotificationService.shared
    private let scrollCoordinateSpace = "PlanForecastHubView.scroll"
    
    enum ViewMode: String, CaseIterable {
        case list = "List"
        case calendar = "Calendar"
        case timeline = "Timeline"
    }
    
    private var upcomingPurchases: [(name: String, date: Date, amount: Decimal, type: String, id: String, daysUntil: Int)] {
        var items: [(name: String, date: Date, amount: Decimal, type: String, id: String, daysUntil: Int)] = []
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Add recurring purchases
        recurringPurchases.filter { $0.isActive }.forEach { purchase in
            let daysUntil = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: purchase.nextDate)).day ?? 0
            items.append((purchase.name, purchase.nextDate, purchase.amount, "Recurring", "recurring-\(purchase.persistentModelID)", daysUntil))
        }

        // Add planned purchases with dates
        purchasePlans.filter { !$0.isPurchased && $0.purchaseDate != nil }.forEach { plan in
            let daysUntil = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: plan.purchaseDate!)).day ?? 0
            items.append((plan.itemName, plan.purchaseDate!, plan.expectedPrice, "Planned", "planned-\(plan.persistentModelID)", daysUntil))
        }

        return items.sorted { $0.date < $1.date }
    }

    private var upcomingInNext7Days: [(name: String, date: Date, amount: Decimal, type: String, id: String, daysUntil: Int)] {
        upcomingPurchases.filter { $0.daysUntil >= 0 && $0.daysUntil <= 7 }
    }

    private var upcomingInNext30Days: [(name: String, date: Date, amount: Decimal, type: String, id: String, daysUntil: Int)] {
        upcomingPurchases.filter { $0.daysUntil >= 0 && $0.daysUntil <= 30 }
    }
    
    private var totalForecast: Decimal {
        upcomingPurchases.reduce(0) { $0 + $1.amount }
    }

    private var next7DaysTotal: Decimal {
        upcomingInNext7Days.reduce(0) { $0 + $1.amount }
    }

    private var next30DaysTotal: Decimal {
        upcomingInNext30Days.reduce(0) { $0 + $1.amount }
    }

    private var isEmptyForecast: Bool {
        upcomingPurchases.isEmpty
    }
    
    var body: some View {
        Group {
            if isEmptyForecast {
                emptyForecastView
            } else {
                VStack(spacing: 0) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            SummaryCard(
                                title: "Next 7 Days",
                                amount: next7DaysTotal,
                                count: upcomingInNext7Days.count,
                                currencyCode: currencyCode,
                                color: AppColors.danger(for: appColorMode)
                            )

                            SummaryCard(
                                title: "Next 30 Days",
                                amount: next30DaysTotal,
                                count: upcomingInNext30Days.count,
                                currencyCode: currencyCode,
                                color: AppColors.warning(for: appColorMode)
                            )

                            SummaryCard(
                                title: "All Upcoming",
                                amount: totalForecast,
                                count: upcomingPurchases.count,
                                currencyCode: currencyCode,
                                color: AppColors.tint(for: appColorMode)
                            )
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 12)
                    .background(Color(.systemGroupedBackground))

                    if billReminders && !notificationService.notificationsEnabled {
                        NotificationPromptBanner(onEnable: {
                            Task {
                                _ = await notificationService.requestAuthorization()
                                if notificationService.notificationsEnabled {
                                    await notificationService.scheduleAllRecurringBillNotifications(
                                        modelContext: modelContext,
                                        daysBefore: notificationService.reminderDaysBefore
                                    )
                                }
                            }
                        })
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                    }

                    Picker("View Mode", selection: $viewMode) {
                        ForEach(ViewMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding()

                    Group {
                        switch viewMode {
                        case .list:
                            listView
                        case .calendar:
                            calendarView
                        case .timeline:
                            timelineView
                        }
                    }
                }
            }
        }
        .navigationTitle("Spending Forecast")
        .globalKeyboardDoneToolbar()
        .toolbar {
            if !isEmptyForecast {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            showingAddRecurring = true
                        } label: {
                            Label("Add Recurring Bill", systemImage: "plus.circle")
                        }

                        Button {
                            showingSettings = true
                        } label: {
                            Label("Notification Settings", systemImage: "bell.badge")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .sheet(isPresented: $showingAddRecurring) {
            AddRecurringPurchaseView()
        }
        .sheet(isPresented: $showingSettings) {
            RecurringBillSettingsView()
        }
        .task {
            await syncBillReminderScheduling()
            postUpcomingBillsInboxNotificationIfNeeded()
        }
        .onChange(of: billReminders) { _, _ in
            Task { await syncBillReminderScheduling() }
        }
    }

    @MainActor
    private func syncBillReminderScheduling() async {
        guard billReminders else {
            notificationService.cancelAllRecurringBillNotifications()
            return
        }

        if notificationService.notificationsEnabled {
            await notificationService.scheduleAllRecurringBillNotifications(
                modelContext: modelContext,
                daysBefore: notificationService.reminderDaysBefore
            )
        }
    }

    private func postUpcomingBillsInboxNotificationIfNeeded() {
        guard billReminders else { return }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        let upcomingBills = recurringPurchases
            .filter { $0.isActive }
            .compactMap { purchase -> (RecurringPurchase, Int)? in
                let daysUntil = calendar.dateComponents([.day], from: today, to: calendar.startOfDay(for: purchase.nextDate)).day ?? 0
                guard daysUntil >= 0 && daysUntil <= 7 else { return nil }
                return (purchase, daysUntil)
            }
            .sorted { $0.0.nextDate < $1.0.nextDate }

        guard let next = upcomingBills.first else { return }

        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode

        let nextAmount = formatter.string(from: next.0.amount as NSDecimalNumber) ?? "\(next.0.amount)"
        let title: String
        let type: NotificationType

        if next.1 == 0 {
            title = "Bills Due Today"
            type = .warning
        } else if next.1 == 1 {
            title = "Bill Reminder"
            type = .info
        } else {
            title = "Upcoming Bills"
            type = .info
        }

        let message: String = {
            if upcomingBills.count == 1 {
                return "\(next.0.name) (\(nextAmount)) is due \(daysUntilText(next.1).lowercased())."
            }
            return "\(upcomingBills.count) bills due in the next 7 days. Next: \(next.0.name) (\(nextAmount)) \(daysUntilText(next.1).lowercased())."
        }()

        let dayKey: String = {
            let df = DateFormatter()
            df.calendar = calendar
            df.locale = Locale(identifier: "en_US_POSIX")
            df.dateFormat = "yyyy-MM-dd"
            return df.string(from: today)
        }()

        InAppNotificationService.post(
            title: title,
            message: message,
            type: type,
            in: modelContext,
            topic: .billReminders,
            dedupeKey: "bills.upcoming.\(dayKey)"
        )
    }
    
    private var listView: some View {
        List {
            ScrollOffsetReader(coordinateSpace: scrollCoordinateSpace, id: scrollCoordinateSpace)
	            ForEach(upcomingPurchases, id: \.id) { item in
	                HStack(spacing: 12) {
                    // Urgency Indicator
                    UrgencyIndicator(daysUntil: item.daysUntil, appColorMode: appColorMode)

	                    VStack(alignment: .leading, spacing: 4) {
	                        Text(item.name)
	                            .appSecondaryBodyText()
	                            .fontWeight(.medium)

                        HStack(spacing: 4) {
                            Text(item.date, style: .date)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("•")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text(daysUntilText(item.daysUntil))
                                .appCaptionText()
                                .foregroundColor(urgencyColor(for: item.daysUntil))
                        }
                    }

                    Spacer()

	                    VStack(alignment: .trailing, spacing: 4) {
	                        Text(item.amount, format: .currency(code: currencyCode))
	                            .appSecondaryBodyText()
	                            .fontWeight(.semibold)
                        Text(item.type)
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .coordinateSpace(name: scrollCoordinateSpace)
    }

    private var emptyForecastView: some View {
        List {
            ScrollOffsetReader(coordinateSpace: scrollCoordinateSpace, id: scrollCoordinateSpace)
            EmptyDataCard(
                systemImage: "chart.line.uptrend.xyaxis",
                title: "No Forecast",
                message: "Add your first transaction to start getting data.",
                actionTitle: "Add Transaction"
            ) {
                navigator.addTransaction()
            }
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Color(.systemBackground))
        .coordinateSpace(name: scrollCoordinateSpace)
    }

    private func daysUntilText(_ days: Int) -> String {
        if days < 0 {
            return "Overdue"
        } else if days == 0 {
            return "Today"
        } else if days == 1 {
            return "Tomorrow"
        } else {
            return "in \(days) days"
        }
    }

    private func urgencyColor(for daysUntil: Int) -> Color {
        if daysUntil < 0 {
            return AppColors.danger(for: appColorMode)
        } else if daysUntil == 0 {
            return AppColors.danger(for: appColorMode)
        } else if daysUntil <= 3 {
            return AppColors.warning(for: appColorMode)
        } else if daysUntil <= 7 {
            return AppColors.tint(for: appColorMode)
        } else {
            return .secondary
        }
    }
    
    private var calendarView: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                ScrollOffsetReader(coordinateSpace: scrollCoordinateSpace, id: scrollCoordinateSpace)
	                ForEach(groupedByMonth(), id: \.0) { month, items in
	                    VStack(alignment: .leading, spacing: 12) {
	                        HStack {
	                            Text(month, format: .dateTime.month(.wide).year())
	                                .appSectionTitleText()
	                            Spacer()
                            Text(items.reduce(Decimal(0)) { $0 + $1.amount }, format: .currency(code: currencyCode))
                                .appSecondaryBodyText()
                                .fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal)

                        ForEach(items, id: \.id) { item in
                            HStack(spacing: 12) {
                                // Date badge
                                VStack(spacing: 2) {
                                    Text(item.date, format: .dateTime.day())
                                        .font(.system(size: 20, weight: .bold))
                                    Text(item.date, format: .dateTime.month(.abbreviated))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 50)
                                .padding(.vertical, 8)
                                .background(urgencyColor(for: item.daysUntil).opacity(0.1))
                                .cornerRadius(AppTheme.Radius.xSmall)

	                                VStack(alignment: .leading, spacing: 4) {
	                                    Text(item.name)
	                                        .appSecondaryBodyText()
	                                        .fontWeight(.medium)
	                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(item.type == "Recurring" ? AppColors.tint(for: appColorMode) : AppColors.warning(for: appColorMode))
                                            .frame(width: 6, height: 6)
                                        Text(item.type)
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                        Text("•")
                                            .appCaptionText()
                                            .foregroundStyle(.secondary)
                                        Text(daysUntilText(item.daysUntil))
                                            .appCaptionText()
                                            .foregroundColor(urgencyColor(for: item.daysUntil))
                                    }
                                }

                                Spacer()

	                                Text(item.amount, format: .currency(code: currencyCode))
	                                    .appSecondaryBodyText()
	                                    .fontWeight(.semibold)
	                            }
                            .padding()
                            .background(Color(.systemBackground))
                            .cornerRadius(AppTheme.Radius.compact)
                            .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                            .padding(.horizontal)
                        }
                    }
                }
            }
            .padding(.vertical)
        }
        .background(Color(.systemGroupedBackground))
    }

    private var timelineView: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ScrollOffsetReader(coordinateSpace: scrollCoordinateSpace, id: scrollCoordinateSpace)
                ForEach(upcomingPurchases, id: \.id) { item in
                    HStack(alignment: .top, spacing: 12) {
                        // Timeline indicator
                        VStack(spacing: 0) {
                            Circle()
                                .fill(urgencyColor(for: item.daysUntil))
                                .frame(width: 12, height: 12)

                            if item.id != upcomingPurchases.last?.id {
                                Rectangle()
                                    .fill(Color.secondary.opacity(0.3))
                                    .frame(width: 2)
                                    .frame(maxHeight: .infinity)
                            }
                        }
                        .frame(height: 80)

                        // Content
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(item.date, format: .dateTime.month(.abbreviated).day().year())
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Text(daysUntilText(item.daysUntil))
                                    .appCaptionText()
                                    .fontWeight(.medium)
                                    .foregroundColor(urgencyColor(for: item.daysUntil))
                            }

	                            Text(item.name)
	                                .appSecondaryBodyText()
	                                .fontWeight(.semibold)

                            HStack {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(item.type == "Recurring" ? AppColors.tint(for: appColorMode) : AppColors.warning(for: appColorMode))
                                        .frame(width: 6, height: 6)
                                    Text(item.type)
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(item.amount, format: .currency(code: currencyCode))
                                    .appSecondaryBodyText()
                                    .fontWeight(.bold)
                            }
                        }
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemBackground))
                        .cornerRadius(AppTheme.Radius.compact)
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }
            }
            .padding(.vertical)
        }
        .coordinateSpace(name: scrollCoordinateSpace)
        .background(Color(.systemGroupedBackground))
    }
    
    private func groupedByMonth() -> [(Date, [(name: String, date: Date, amount: Decimal, type: String, id: String, daysUntil: Int)])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: upcomingPurchases) { item in
            calendar.date(from: calendar.dateComponents([.year, .month], from: item.date))!
        }
        return grouped.sorted { $0.key < $1.key }.map { ($0.key, $0.value.sorted { $0.date < $1.date }) }
    }
}

// MARK: - Supporting Views

private struct SummaryCard: View {
    let title: String
    let amount: Decimal
    let count: Int
    let currencyCode: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .appCaptionText()
                .foregroundStyle(.secondary)

            Text(amount, format: .currency(code: currencyCode))
                .font(.system(size: 24, weight: .bold))
                .foregroundColor(color)

            Text("\(count) item\(count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(width: 140)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(AppTheme.Radius.compact)
        .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
    }
}

struct UrgencyIndicator: View {
    let daysUntil: Int
    let appColorMode: AppColorMode

    private var color: Color {
        if daysUntil < 0 {
            return AppColors.danger(for: appColorMode)
        } else if daysUntil == 0 {
            return AppColors.danger(for: appColorMode)
        } else if daysUntil <= 3 {
            return AppColors.warning(for: appColorMode)
        } else if daysUntil <= 7 {
            return AppColors.tint(for: appColorMode)
        } else {
            return .secondary
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(color)
            .frame(width: 4, height: 40)
    }
}

struct NotificationPromptBanner: View {
    let onEnable: () -> Void
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        let tint = AppColors.warning(for: appColorMode)

	        HStack(spacing: 12) {
            Image(systemName: "bell.badge")
                .font(.title3)
                .foregroundColor(tint)

	            VStack(alignment: .leading, spacing: 2) {
	                Text("Enable Reminders")
	                    .appSecondaryBodyText()
	                    .fontWeight(.semibold)
                Text("Get notified before bills are due")
                    .appCaptionText()
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Enable") {
                onEnable()
            }
            .appPrimaryCTA()
            .controlSize(.small)
        }
        .padding()
        .background(tint.opacity(0.12))
        .cornerRadius(AppTheme.Radius.compact)
    }
}

struct RecurringBillSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @StateObject private var notificationService = NotificationService.shared
    @AppStorage("billReminderDays") private var reminderDays = 1

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Enable Bill Reminders", isOn: $notificationService.notificationsEnabled)
                        .onChange(of: notificationService.notificationsEnabled) { _, newValue in
                            if newValue {
                                Task {
                                    let granted = await notificationService.requestAuthorization()
                                    if granted {
                                        await notificationService.scheduleAllRecurringBillNotifications(
                                            modelContext: modelContext,
                                            daysBefore: reminderDays
                                        )
                                    }
                                }
                            } else {
                                notificationService.cancelAllRecurringBillNotifications()
                            }
                        }
                } header: {
                    Text("Notifications")
                } footer: {
                    Text("Receive notifications before your recurring bills are due")
                }

                if notificationService.notificationsEnabled {
                    Section {
                        Stepper("Remind me \(reminderDays) day\(reminderDays == 1 ? "" : "s") before", value: $reminderDays, in: 0...7)
                            .onChange(of: reminderDays) { _, newValue in
                                notificationService.reminderDaysBefore = newValue
                                Task {
                                    await notificationService.scheduleAllRecurringBillNotifications(
                                        modelContext: modelContext,
                                        daysBefore: newValue
                                    )
                                }
                            }
                    } header: {
                        Text("Reminder Timing")
                    } footer: {
                        if reminderDays == 0 {
                            Text("You will be notified on the day bills are due")
                        } else {
                            Text("You will be notified \(reminderDays) day\(reminderDays == 1 ? "" : "s") before bills are due")
                        }
                    }
                }
            }
            .navigationTitle("Bill Reminder Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Add Recurring Purchase
struct AddRecurringPurchaseView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var name = ""
    @State private var amount = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var nextDate = Date()
    @State private var category = "Bills"
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Purchase Details") {
                    TextField("Name", text: $name)
                    TextField("Amount", text: $amount)
                        .keyboardType(.decimalPad)
                }
                
                Section("Recurrence") {
                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }
                    DatePicker("Next Date", selection: $nextDate, displayedComponents: .date)
                }
                
                Section("Category") {
                    TextField("Category", text: $category)
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .navigationTitle("New Recurring Purchase")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveRecurring()
                    }
                    .disabled(name.isEmpty || amount.isEmpty)
                }
            }
        }
    }
    
    private func saveRecurring() {
        let amountDecimal = Decimal(string: amount) ?? 0
        let recurring = RecurringPurchase(
            name: name,
            amount: amountDecimal,
            frequency: frequency,
            nextDate: nextDate,
            category: category,
            notes: notes.isEmpty ? nil : notes
        )
        modelContext.insert(recurring)
        dismiss()
    }
}

#Preview {
    SpendingForecastView()
        .modelContainer(for: [RecurringPurchase.self, PurchasePlan.self], inMemory: true)
}
