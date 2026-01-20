import SwiftUI
import SwiftData

struct PurchasePlannerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PurchasePlan.purchaseDate) private var allPurchases: [PurchasePlan]
    @Query private var transactions: [Transaction]
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var showingAddPurchase = false
    @State private var selectedFilter: FilterOption = .upcoming
    @State private var showingMarkPurchased = false
    @State private var selectedPurchaseForMark: PurchasePlan?
    @State private var actualPrice = ""
    
    enum FilterOption: String, CaseIterable {
        case all = "All"
        case upcoming = "Upcoming"
        case purchased = "Purchased"
    }
    
    private var filteredPurchases: [PurchasePlan] {
        switch selectedFilter {
        case .all:
            return allPurchases
        case .upcoming:
            return allPurchases.filter { !$0.isPurchased }
        case .purchased:
            return allPurchases.filter { $0.isPurchased }
        }
    }
    
    var body: some View {
        Group {
            if filteredPurchases.isEmpty {
                List {
                    ScrollOffsetReader(coordinateSpace: "PurchasePlannerView.scroll", id: "PurchasePlannerView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    EmptyDataCard(
                        systemImage: "cart",
                        title: "No Purchase Plans",
                        message: "Create a purchase plan to track items you want to buy.",
                        actionTitle: "Add Purchase",
                        action: { showingAddPurchase = true }
                    )
                    .listRowInsets(EdgeInsets())
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .coordinateSpace(name: "PurchasePlannerView.scroll")
            } else {
                List {
                    ScrollOffsetReader(coordinateSpace: "PurchasePlannerView.scroll", id: "PurchasePlannerView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    // Summary Card
                    Section {
                        VStack(spacing: AppTheme.Spacing.tight) {
                            HStack {
                                VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                                    Text("Total Planned")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalPlanned, format: .currency(code: currencyCode))
                                        .appTitleText()
                                        .fontWeight(.bold)
                                }

                                Spacer()

                                VStack(alignment: .trailing, spacing: AppTheme.Spacing.micro) {
                                    Text("Items")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text("\(filteredPurchases.count)")
                                        .appTitleText()
                                }
                            }
                        }
                        .padding(.vertical, AppTheme.Spacing.compact)
                    }
                    
                    // Filter Picker
                    Section {
                        Picker("Filter", selection: $selectedFilter) {
                            ForEach(FilterOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    
                    // Purchase List
                    Section {
                        ForEach(filteredPurchases) { purchase in
                            PurchasePlanRow(
                                purchase: purchase,
                                savingsRate: calculateSavingsRate(),
                                monthlyIncome: calculateMonthlyIncome()
                            )
                            .swipeActions(edge: .leading) {
                                if !purchase.isPurchased {
                                    Button {
                                        selectedPurchaseForMark = purchase
                                        showingMarkPurchased = true
                                    } label: {
                                        Label("Purchased", systemImage: "checkmark.circle.fill")
                                    }
                                    .tint(.green)
                                }
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    deletePurchase(purchase)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
                .coordinateSpace(name: "PurchasePlannerView.scroll")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddPurchase = true }) {
                    Label("Add Purchase", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddPurchase) {
            AddPurchasePlanView()
        }
        .alert("Mark as Purchased", isPresented: $showingMarkPurchased) {
            TextField("Actual Price (optional)", text: $actualPrice)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {
                actualPrice = ""
                selectedPurchaseForMark = nil
            }
            Button("Confirm") {
                markPurchased()
            }
        } message: {
            if let purchase = selectedPurchaseForMark {
                Text("Expected: \(purchase.expectedPrice.formatted(.currency(code: currencyCode)))")
            }
        }
    }
    
    private var totalPlanned: Decimal {
        filteredPurchases.filter { !$0.isPurchased }.reduce(0) { $0 + $1.expectedPrice }
    }
    
    private func deletePurchase(_ purchase: PurchasePlan) {
        modelContext.delete(purchase)
    }

    private func markPurchased() {
        guard let purchase = selectedPurchaseForMark else { return }

        purchase.isPurchased = true
        purchase.actualPrice = Decimal(string: actualPrice) ?? purchase.expectedPrice
        purchase.actualPurchaseDate = Date()

        actualPrice = ""
        selectedPurchaseForMark = nil

        try? modelContext.save()
    }

    private func calculateSavingsRate() -> Double {
        // Calculate savings rate from last 3 months
        let calendar = Calendar.current
        let now = Date()
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now

        let recentTx = transactions.filter { $0.date >= threeMonthsAgo }

        let income = recentTx.filter { tx in
            guard tx.amount > 0 else { return false }
            return tx.category?.group?.type == .income
        }.reduce(Decimal(0)) { $0 + $1.amount }

        let expenses = recentTx.filter { $0.amount < 0 && $0.kind == .standard }
            .reduce(Decimal(0)) { $0 + abs($1.amount) }

        guard income > 0 else { return 0 }
        let savings = income - expenses
        return Double(truncating: (savings / income) as NSNumber)
    }

    private func calculateMonthlyIncome() -> Decimal {
        // Calculate average monthly income from last 3 months
        let calendar = Calendar.current
        let now = Date()
        let threeMonthsAgo = calendar.date(byAdding: .month, value: -3, to: now) ?? now

        let recentIncome = transactions.filter { tx in
            guard tx.date >= threeMonthsAgo, tx.amount > 0 else { return false }
            return tx.category?.group?.type == .income
        }.reduce(Decimal(0)) { $0 + $1.amount }

        return recentIncome / 3
    }
}

// MARK: - Purchase Plan Row

struct PurchasePlanRow: View {
    let purchase: PurchasePlan
    let savingsRate: Double
    let monthlyIncome: Decimal
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    private var categoryIcon: String {
        switch purchase.category {
        case "Electronics": return "laptopcomputer"
        case "Furniture": return "sofa"
        case "Clothing": return "tshirt"
        case "Travel": return "airplane"
        case "Fitness": return "figure.run"
        case "Entertainment": return "popcorn"
        case "Education": return "book"
        case "Home": return "house"
        default: return "tag"
        }
    }

    private var categoryColor: Color {
        switch purchase.category {
        case "Electronics": return .blue
        case "Furniture": return .brown
        case "Clothing": return .purple
        case "Travel": return .orange
        case "Fitness": return .green
        case "Entertainment": return .pink
        case "Education": return .indigo
        case "Home": return .cyan
        default: return .gray
        }
    }

    private var priorityColor: Color {
        switch purchase.priority {
        case 1, 2: return AppColors.success(for: appColorMode)
        case 3: return AppColors.warning(for: appColorMode)
        case 4, 5: return AppColors.danger(for: appColorMode)
        default: return .gray
        }
    }

    private var affordabilityInsight: String? {
        if purchase.isPurchased {
            return nil
        }

        let monthlySavings = monthlyIncome * Decimal(savingsRate)

        guard monthlySavings > 0 else {
            return nil
        }

        let monthsToAfford = Int(ceil(Double(truncating: (purchase.expectedPrice / monthlySavings) as NSNumber)))

        if monthsToAfford == 0 {
            return "You can afford this now"
        } else if monthsToAfford == 1 {
            return "Affordable in 1 month"
        } else if monthsToAfford <= 6 {
            return "Affordable in \(monthsToAfford) months"
        }

        return nil
    }
    
    var body: some View {
        NavigationLink(destination: PurchasePlanDetailView(purchase: purchase)) {
            HStack(spacing: AppTheme.Spacing.medium) {
                // Category Icon
                ZStack {
                    RoundedRectangle(cornerRadius: AppTheme.Radius.compact)
                        .fill(categoryColor.opacity(0.15))
                        .frame(width: 56, height: 56)

                    Image(systemName: categoryIcon)
                        .appTitleText()
                        .foregroundStyle(categoryColor)

                    if purchase.isPurchased {
                        VStack {
                            Spacer()
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .appCaptionText()
                                    .foregroundStyle(.white)
                                    .background(
                                        Circle()
                                            .fill(AppColors.success(for: appColorMode))
                                            .frame(width: 18, height: 18)
                                    )
                                    .offset(x: 8, y: 8)
                            }
                        }
                        .frame(width: 56, height: 56)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: AppTheme.Spacing.xSmall) {
                    HStack {
                        Text(purchase.itemName)
                            .appSectionTitleText()
                            .lineLimit(1)

                        Spacer()

                        // Priority stars
                        if purchase.priority > 3 {
                            HStack(spacing: AppTheme.Spacing.hairline) {
                                ForEach(0..<min(purchase.priority - 2, 3), id: \.self) { _ in
                                    Image(systemName: "star.fill")
                                        .font(.caption2)
                                }
                            }
                            .foregroundStyle(priorityColor)
                        }
                    }

                    Text(purchase.expectedPrice, format: .currency(code: currencyCode))
                        .appSecondaryBodyText()
                        .fontWeight(.semibold)
                        .foregroundStyle(categoryColor)

                    if let insight = affordabilityInsight {
                        Text(insight)
                            .appCaptionText()
                            .foregroundStyle(insight.contains("now") ? AppColors.success(for: appColorMode) : .secondary)
                    } else if let purchaseDate = purchase.purchaseDate, !purchase.isPurchased {
                        let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: purchaseDate).day ?? 0
                        if daysUntil > 0 && daysUntil <= 30 {
                            Text("\(daysUntil) day\(daysUntil == 1 ? "" : "s") until target")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, AppTheme.Spacing.compact)
        }
    }
}

// MARK: - Add/Edit View

struct AddPurchasePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @AppStorage("currencyCode") private var currencyCode = "USD"
    
    @State private var itemName = ""
    @State private var expectedPrice = ""
    @State private var category = "Other"
    @State private var priority = 3
    @State private var usePurchaseDate = false
    @State private var purchaseDate = Date().addingTimeInterval(86400 * 30) // 30 days
    @State private var url = ""
    @State private var notes = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Item Details") {
                    TextField("Item Name", text: $itemName)
                    TextField("Expected Price", text: $expectedPrice)
                        .keyboardType(.decimalPad)
                }
                
                Section("Category & Priority") {
                    Picker("Category", selection: $category) {
                        ForEach(PurchasePlan.categories, id: \.self) { cat in
                            Text(cat).tag(cat)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.compact) {
                        Text("Priority: \(priority)")
                            .appSecondaryBodyText()
                        Slider(value: Binding(
                            get: { Double(priority) },
                            set: { priority = Int($0) }
                        ), in: 1...5, step: 1)
                        
                        HStack {
                            Text("Low")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("High")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                Section("Purchase Date") {
                    Toggle("Set Target Date", isOn: $usePurchaseDate)
                    
                    if usePurchaseDate {
                        DatePicker("Target Date", selection: $purchaseDate, in: Date()..., displayedComponents: .date)
                    }
                }
                
                Section("Additional Info") {
                    TextField("Website URL (optional)", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                    
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Purchase Plan")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        savePurchase()
                    }
                    .disabled(itemName.isEmpty || expectedPrice.isEmpty)
                }
            }
        }
    }
    
    private func savePurchase() {
        let price = Decimal(string: expectedPrice) ?? 0
        let date = usePurchaseDate ? purchaseDate : nil
        
        let purchase = PurchasePlan(
            itemName: itemName,
            expectedPrice: price,
            purchaseDate: date,
            url: url.isEmpty ? nil : url,
            category: category,
            priority: priority,
            notes: notes.isEmpty ? nil : notes
        )
        
        modelContext.insert(purchase)
        dismiss()
    }
}

// MARK: - Detail View

struct PurchasePlanDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let purchase: PurchasePlan
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    @State private var showingMarkPurchased = false
    @State private var actualPrice = ""
    
    var body: some View {
        List {
            Section("Item Information") {
                LabeledContent("Item", value: purchase.itemName)
                LabeledContent("Expected Price", value: purchase.expectedPrice, format: .currency(code: currencyCode))
                LabeledContent("Category", value: purchase.category)
                
                HStack {
                    Text("Priority")
                    Spacer()
                    HStack(spacing: AppTheme.Spacing.hairline) {
                        ForEach(0..<purchase.priority, id: \.self) { _ in
                            Image(systemName: "star.fill")
                                .appCaptionText()
                        }
                    }
                    .foregroundStyle(AppColors.warning(for: appColorMode))
                }
            }
            
            if let purchaseDate = purchase.purchaseDate {
                Section("Timeline") {
                    LabeledContent("Target Date", value: purchaseDate, format: .dateTime.day().month().year())
                    
                    let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: purchaseDate).day ?? 0
                    if daysUntil > 0 {
                        LabeledContent("Days Until", value: "\(daysUntil) days")
                    }
                }
            }
            
            if let validURL = purchase.validatedURL {
                Section("Link") {
                    Link(destination: validURL) {
                        HStack {
                            Text("View Item Online")
                            Spacer()
                            Image(systemName: "arrow.up.right.square")
                        }
                    }
                }
            }
            
            if let notes = purchase.notes {
                Section("Notes") {
                    Text(notes)
                        .font(AppTheme.Typography.body)
                }
            }
            
            if purchase.isPurchased {
                Section("Purchase Details") {
                    if let actualPrice = purchase.actualPrice {
                        LabeledContent("Actual Price", value: actualPrice, format: .currency(code: currencyCode))
                    }
                    if let actualDate = purchase.actualPurchaseDate {
                        LabeledContent("Purchase Date", value: actualDate, format: .dateTime.day().month().year())
                    }
                }
            } else {
                Section {
                    Button(action: { showingMarkPurchased = true }) {
                        HStack {
                            Image(systemName: "checkmark.circle")
                            Text("Mark as Purchased")
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(AppColors.success(for: appColorMode))
                    }
                }
            }
        }
        .navigationTitle("Purchase Details")
        .navigationBarTitleDisplayMode(.inline)
        .globalKeyboardDoneToolbar()
        .alert("Mark as Purchased", isPresented: $showingMarkPurchased) {
            TextField("Actual Price", text: $actualPrice)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {
                actualPrice = ""
            }
            Button("Confirm") {
                purchase.isPurchased = true
                purchase.actualPrice = Decimal(string: actualPrice) ?? purchase.expectedPrice
                purchase.actualPurchaseDate = Date()
                actualPrice = ""
            }
        } message: {
            Text("Enter the actual price you paid (optional)")
        }
    }
}

#Preview {
    PurchasePlannerView()
        .modelContainer(for: [PurchasePlan.self], inMemory: true)
}
