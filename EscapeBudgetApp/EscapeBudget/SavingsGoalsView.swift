import SwiftUI
import SwiftData

struct SavingsGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \SavingsGoal.createdDate, order: .reverse) private var savingsGoals: [SavingsGoal]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    @State private var showingAddGoal = false
    @State private var showingQuickContribute = false
    @State private var selectedGoalForContribution: SavingsGoal?
    @State private var contributionAmount = ""
    
    var body: some View {
        Group {
            if savingsGoals.isEmpty {
                List {
                    ScrollOffsetReader(coordinateSpace: "SavingsGoalsView.scroll", id: "SavingsGoalsView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                EmptyDataCard(
                    systemImage: "target",
                    title: "No Savings Goals",
                    message: "Create a savings goal to start tracking your progress.",
                    actionTitle: "Add Goal",
                    action: { showingAddGoal = true }
                )
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(.systemBackground))
                .coordinateSpace(name: "SavingsGoalsView.scroll")
            } else {
                List {
                    ScrollOffsetReader(coordinateSpace: "SavingsGoalsView.scroll", id: "SavingsGoalsView.scroll")
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                    // Summary Card
                    Section {
                        VStack(spacing: 12) {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Saved")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalSaved, format: .currency(code: currencyCode))
                                        .font(.title2)
                                        .fontWeight(.bold)
                                }
                                
                                Spacer()
                                
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text("Total Goal")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                    Text(totalTarget, format: .currency(code: currencyCode))
                                        .font(.title3)
                                        .fontWeight(.semibold)
                                }
                            }
                            
                            ProgressView(value: overallProgress)
                                .tint(AppColors.tint(for: appColorMode))
                        }
                        .padding(.vertical, 8)
                    }
                    
                    // Goals List
                    Section {
                        ForEach(savingsGoals) { goal in
                            SavingsGoalRow(goal: goal)
                                .swipeActions(edge: .leading) {
                                    if !goal.isAchieved {
                                        Button {
                                            selectedGoalForContribution = goal
                                            showingQuickContribute = true
                                        } label: {
                                            Label("Add Money", systemImage: "plus.circle.fill")
                                        }
                                        .tint(.green)
                                    }
                                }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        deleteGoal(goal)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                }
                .coordinateSpace(name: "SavingsGoalsView.scroll")
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: { showingAddGoal = true }) {
                    Label("Add Goal", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddGoal) {
            AddSavingsGoalView()
        }
        .alert("Add to \(selectedGoalForContribution?.name ?? "Goal")", isPresented: $showingQuickContribute) {
            TextField("Amount", text: $contributionAmount)
                .keyboardType(.decimalPad)
            Button("Cancel", role: .cancel) {
                contributionAmount = ""
            }
            Button("Add") {
                addContribution()
            }
        } message: {
            Text("How much would you like to add?")
        }
    }
    
    private var totalSaved: Decimal {
        savingsGoals.reduce(0) { $0 + $1.currentAmount }
    }
    
    private var totalTarget: Decimal {
        savingsGoals.reduce(0) { $0 + $1.targetAmount }
    }
    
    private var overallProgress: Double {
        guard totalTarget > 0 else { return 0 }
        return Double(truncating: (totalSaved / totalTarget) as NSNumber)
    }
    
    private func deleteGoal(_ goal: SavingsGoal) {
        modelContext.delete(goal)
    }

    private func addContribution() {
        guard let goal = selectedGoalForContribution,
              let amount = Decimal(string: contributionAmount),
              amount > 0 else {
            contributionAmount = ""
            return
        }

        goal.currentAmount += amount
        contributionAmount = ""
        selectedGoalForContribution = nil

        try? modelContext.save()
    }
}

// MARK: - Savings Goal Row

struct SavingsGoalRow: View {
    let goal: SavingsGoal
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode

    private var color: Color {
        Color(hex: goal.colorHex) ?? AppColors.tint(for: appColorMode)
    }

    private var smartInsight: String? {
        if goal.isAchieved {
            return "🎉 Goal achieved!"
        }

        let remaining = goal.amountRemaining

        // Show how close they are
        if remaining <= 50 {
            return "Almost there! Just \(remaining.formatted(.currency(code: currencyCode))) to go"
        }

        // Show timeline projection based on monthly contribution
        if let monthly = goal.monthlyContribution, monthly > 0 {
            let monthsRemaining = Int(ceil(Double(truncating: (remaining / monthly) as NSNumber)))
            if monthsRemaining == 1 {
                return "One more month at current pace"
            } else if monthsRemaining <= 12 {
                return "\(monthsRemaining) months at current pace"
            }
        }

        // Show days until target date
        if let targetDate = goal.targetDate {
            let daysUntil = Calendar.current.dateComponents([.day], from: Date(), to: targetDate).day ?? 0
            if daysUntil > 0 && daysUntil <= 7 {
                return "\(daysUntil) day\(daysUntil == 1 ? "" : "s") until target"
            } else if daysUntil > 7 && daysUntil <= 30 {
                let weeks = daysUntil / 7
                return "\(weeks) week\(weeks == 1 ? "" : "s") until target"
            }
        }

        return nil
    }

    var body: some View {
        NavigationLink(destination: SavingsGoalDetailView(goal: goal)) {
            HStack(spacing: 16) {
                // Circular Progress Ring (simplified)
                ZStack {
                    Circle()
                        .stroke(color.opacity(0.2), lineWidth: 4)
                        .frame(width: 56, height: 56)

                    Circle()
                        .trim(from: 0, to: min(goal.progressPercentage / 100, 1.0))
                        .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .frame(width: 56, height: 56)
                        .rotationEffect(.degrees(-90))

                    if goal.isAchieved {
                        Image(systemName: "checkmark")
                            .font(.title3)
                            .foregroundColor(color)
                    } else {
                        Text("\(Int(goal.progressPercentage))%")
                            .appCaptionText()
                            .fontWeight(.bold)
                            .foregroundColor(color)
                    }
                }

                // Content
                VStack(alignment: .leading, spacing: 6) {
                    Text(goal.name)
                        .appSectionTitleText()

                    Text("\(goal.currentAmount, format: .currency(code: currencyCode)) of \(goal.targetAmount, format: .currency(code: currencyCode))")
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)

                    if let insight = smartInsight {
                        Text(insight)
                            .appCaptionText()
                            .foregroundStyle(goal.isAchieved ? AppColors.success(for: appColorMode) : color)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)
        }
    }
}

// MARK: - Add/Edit View

struct AddSavingsGoalView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var goals: [SavingsGoal]
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    @State private var name = ""
    @State private var targetAmount = ""
    @State private var currentAmount = ""
    @State private var useTargetDate = true
    @State private var targetDate = Date().addingTimeInterval(86400 * 365) // 1 year from now
    @State private var monthlyContribution = ""
    @State private var selectedColorHex = "007AFF"
    @State private var notes = ""

    private var colorOptions: [(hex: String, name: String)] {
        switch appColorMode {
        case .standard:
            return [
                ("007AFF", "Blue"),
                ("FF9500", "Orange"),
                ("FF2D55", "Pink"),
                ("5AC8FA", "Teal"),
                ("34C759", "Green"),
                ("AF52DE", "Purple")
            ]
        case .neutral:
            return [
                ("576980", "Slate"),
                ("5C806B", "Sage"),
                ("9E8057", "Sand"),
                ("9E5C66", "Rose"),
                ("7C5C8A", "Plum"),
                ("6B7280", "Graphite")
            ]
        }
    }

    private var defaultColorHex: String {
        colorOptions.first?.hex ?? "007AFF"
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Goal Details") {
                    TextField("Goal Name", text: $name)
                    TextField("Target Amount", text: $targetAmount)
                        .keyboardType(.decimalPad)
                    TextField("Current Amount", text: $currentAmount)
                        .keyboardType(.decimalPad)
                }
                
                Section("Timeframe") {
                    Picker("Method", selection: $useTargetDate) {
                        Text("Target Date").tag(true)
                        Text("Monthly Amount").tag(false)
                    }
                    .pickerStyle(.segmented)
                    
                    if useTargetDate {
                        DatePicker("Target Date", selection: $targetDate, in: Date()..., displayedComponents: .date)
                    } else {
                        TextField("Monthly Contribution", text: $monthlyContribution)
                            .keyboardType(.decimalPad)
                    }
                }
                
                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 12) {
                        ForEach(colorOptions, id: \.0) { hex, name in
                            Circle()
                                .fill(Color(hex: hex) ?? AppColors.tint(for: appColorMode))
                                .frame(width: 40, height: 40)
                                .overlay(
                                    Circle()
                                        .stroke(selectedColorHex == hex ? Color.primary : Color.clear, lineWidth: 3)
                                )
                                .onTapGesture {
                                    selectedColorHex = hex
                                }
                        }
                    }
                }
                
                Section("Notes") {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("New Savings Goal")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .onAppear {
                if selectedColorHex == "007AFF" {
                    selectedColorHex = defaultColorHex
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveGoal()
                    }
                    .disabled(name.isEmpty || targetAmount.isEmpty)
                }
            }
        }
    }
    
    private func saveGoal() {
        let target = Decimal(string: targetAmount) ?? 0
        let current = Decimal(string: currentAmount) ?? 0
        let monthly = useTargetDate ? nil : (Decimal(string: monthlyContribution) ?? 0)
        let date = useTargetDate ? targetDate : nil
        
        let goal = SavingsGoal(
            name: name,
            targetAmount: target,
            currentAmount: current,
            targetDate: date,
            monthlyContribution: monthly,
            colorHex: selectedColorHex,
            notes: notes.isEmpty ? nil : notes
        )
        
        modelContext.insert(goal)
        dismiss()
    }
}

// MARK: - Detail View

struct SavingsGoalDetailView: View {
    let goal: SavingsGoal
    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.appColorMode) private var appColorMode
    
    var body: some View {
        List {
            Section {
                VStack(spacing: 16) {
                    Text(goal.progressPercentage, format: .percent.precision(.fractionLength(1)))
                        .font(.system(size: 48, weight: .bold))
                        .foregroundColor(Color(hex: goal.colorHex) ?? AppColors.tint(for: appColorMode))
                    
                    ProgressView(value: goal.progressPercentage / 100)
                        .tint(Color(hex: goal.colorHex) ?? AppColors.tint(for: appColorMode))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            
            Section("Progress") {
                LabeledContent("Current Amount", value: goal.currentAmount, format: .currency(code: currencyCode))
                LabeledContent("Target Amount", value: goal.targetAmount, format: .currency(code: currencyCode))
                LabeledContent("Remaining", value: goal.amountRemaining, format: .currency(code: currencyCode))
            }
            
            if let targetDate = goal.targetDate {
                Section("Timeline") {
                    LabeledContent("Target Date", value: targetDate, format: .dateTime.day().month().year())
                    if let suggested = goal.calculatedMonthlyContribution {
                        LabeledContent("Suggested Monthly", value: suggested, format: .currency(code: currencyCode))
                    }
                }
            } else if let monthly = goal.monthlyContribution {
                Section("Timeline") {
                    LabeledContent("Monthly Contribution", value: monthly, format: .currency(code: currencyCode))
                    if let completionDate = goal.calculatedCompletionDate {
                        LabeledContent("Expected Completion", value: completionDate, format: .dateTime.day().month().year())
                    }
                }
            }
            
            if let notes = goal.notes {
                Section("Notes") {
                    Text(notes)
                        .font(.body)
                }
            }
        }
        .navigationTitle(goal.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Color Extension

extension Color {
    init?(hex: String) {
        var hexSanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        hexSanitized = hexSanitized.replacingOccurrences(of: "#", with: "")
        
        var rgb: UInt64 = 0
        guard Scanner(string: hexSanitized).scanHexInt64(&rgb) else { return nil }
        
        let r = Double((rgb & 0xFF0000) >> 16) / 255.0
        let g = Double((rgb & 0x00FF00) >> 8) / 255.0
        let b = Double(rgb & 0x0000FF) / 255.0
        
        self.init(red: r, green: g, blue: b)
    }
}

#Preview {
    SavingsGoalsView()
        .modelContainer(for: [SavingsGoal.self], inMemory: true)
}
