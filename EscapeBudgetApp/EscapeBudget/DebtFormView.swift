import SwiftUI
import SwiftData

struct DebtFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    // Query all accounts - we'll filter debt types in the view
    @Query(sort: \Account.name) private var allAccounts: [Account]

    private var debtAccounts: [Account] {
        allAccounts.filter { account in
            account.type == .creditCard ||
            account.type == .loans ||
            account.type == .mortgage ||
            account.type == .lineOfCredit
        }
    }

    var existingDebt: DebtAccount?

    @State private var name = ""
    @State private var currentBalance = ""
    @State private var originalBalance = ""
    @State private var interestRate = ""
    @State private var minimumPayment = ""
    @State private var extraPayment = ""
    @State private var notes = ""
    @State private var selectedColorHex = "FF3B30"
    @State private var selectedAccount: Account?
    @State private var useLinkedAccount = false

    private let colorOptions = [
        "FF3B30",  // Red
        "FF9500",  // Orange
        "FFCC00",  // Yellow
        "34C759",  // Green
        "00C7BE",  // Teal
        "007AFF",  // Blue
        "5856D6",  // Purple
        "AF52DE",  // Magenta
        "FF2D55",  // Pink
        "8E8E93"   // Gray
    ]

    var body: some View {
        NavigationStack {
            Form {
                // Link to existing account section - shown prominently at top for new debts
                if !debtAccounts.isEmpty && existingDebt == nil {
                    Section {
                        Picker("Link Account", selection: $selectedAccount) {
                            Text("Manual Entry").tag(nil as Account?)
                            ForEach(debtAccounts) { account in
                                HStack {
                                    Text(account.name)
                                    Spacer()
                                    Text(account.type.rawValue)
                                        .foregroundStyle(.secondary)
                                }
                                .tag(account as Account?)
                            }
                        }
                        .onChange(of: selectedAccount) { _, newAccount in
                            if let account = newAccount {
                                prefillFromAccount(account)
                                useLinkedAccount = true
                            } else {
                                useLinkedAccount = false
                            }
                        }
                    } header: {
                        Text("Quick Setup")
                    } footer: {
                        if selectedAccount != nil {
                            Text("Balance will automatically sync from this account.")
                        } else {
                            Text("Select an existing account to sync balances, or enter debt details manually.")
                        }
                    }
                }

                Section("Debt Details") {
                    TextField("Name", text: $name)

                    if useLinkedAccount && selectedAccount != nil {
                        LabeledContent("Current Balance") {
                            HStack(spacing: AppDesign.Theme.Spacing.xSmall) {
                                Text(abs(selectedAccount?.balance ?? 0), format: .currency(code: currencyCode))
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        HStack {
                            Text(currencySymbol)
                                .foregroundStyle(.secondary)
                            TextField("Current Balance", text: $currentBalance)
                                .keyboardType(.decimalPad)
                        }
                    }

                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("Original Balance (optional)", text: $originalBalance)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        TextField("Interest Rate (APR)", text: $interestRate)
                            .keyboardType(.decimalPad)
                        Text("%")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Monthly Payments") {
                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("Minimum Payment", text: $minimumPayment)
                            .keyboardType(.decimalPad)
                    }

                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("Extra Payment (optional)", text: $extraPayment)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: AppDesign.Theme.Spacing.compact) {
                        ForEach(colorOptions, id: \.self) { hex in
                            Circle()
                                .fill(Color(hex: hex) ?? .red)
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
                    .padding(.vertical, AppDesign.Theme.Spacing.compact)
                }

                if let projection = payoffProjection {
                    Section("Payoff Projection") {
                        HStack {
                            Text("Time to Payoff")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(DebtPayoffCalculator.formatMonths(projection.monthsToPayoff))
                                .fontWeight(.medium)
                        }

                        HStack {
                            Text("Total Interest")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(projection.totalInterestPaid, format: .currency(code: currencyCode))
                                .fontWeight(.medium)
                                .foregroundStyle(AppDesign.Colors.danger(for: appColorMode))
                        }

                        HStack {
                            Text("Debt-Free Date")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(projection.payoffDate, format: .dateTime.month().year())
                                .fontWeight(.medium)
                                .foregroundStyle(AppDesign.Colors.success(for: appColorMode))
                        }
                    }
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingDebt == nil ? "Add Debt" : "Edit Debt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveDebt()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let debt = existingDebt {
                    name = debt.name
                    currentBalance = "\(debt.currentBalance)"
                    originalBalance = "\(debt.originalBalance)"
                    interestRate = "\(debt.interestRatePercentage)"
                    minimumPayment = "\(debt.minimumPayment)"
                    extraPayment = debt.extraPayment > 0 ? "\(debt.extraPayment)" : ""
                    notes = debt.notes ?? ""
                    selectedColorHex = debt.colorHex
                    selectedAccount = debt.linkedAccount
                    useLinkedAccount = debt.linkedAccount != nil
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var currencySymbol: String {
        let locale = Locale(identifier: Locale.identifier(fromComponents: [NSLocale.Key.currencyCode.rawValue: currencyCode]))
        return locale.currencySymbol ?? "$"
    }

    private var isValid: Bool {
        let hasBalance = useLinkedAccount && selectedAccount != nil || Decimal(string: currentBalance) != nil
        return !name.isEmpty &&
            hasBalance &&
            Decimal(string: interestRate) != nil &&
            Decimal(string: minimumPayment) != nil
    }

    private var payoffProjection: DebtPayoffCalculator.PayoffProjection? {
        let balance: Decimal
        if useLinkedAccount, let account = selectedAccount {
            balance = abs(account.balance)
        } else if let parsedBalance = Decimal(string: currentBalance) {
            balance = parsedBalance
        } else {
            return nil
        }

        guard let rate = Decimal(string: interestRate),
              let minimum = Decimal(string: minimumPayment),
              balance > 0, minimum > 0 else {
            return nil
        }

        let extra = Decimal(string: extraPayment) ?? 0
        let totalPayment = minimum + extra
        let aprDecimal = rate / 100

        return DebtPayoffCalculator.calculatePayoff(
            balance: balance,
            interestRate: aprDecimal,
            monthlyPayment: totalPayment
        )
    }

    // MARK: - Actions

    private func prefillFromAccount(_ account: Account) {
        name = account.name
        // Account balance is negative for debt accounts, so negate it
        let balance = abs(account.balance)
        currentBalance = "\(balance)"
        if originalBalance.isEmpty {
            originalBalance = "\(balance)"
        }
    }

    private func saveDebt() {
        // Get balance from linked account or manual entry
        let balance: Decimal
        if useLinkedAccount, let account = selectedAccount {
            balance = abs(account.balance)
        } else if let parsedBalance = Decimal(string: currentBalance) {
            balance = parsedBalance
        } else {
            return
        }

        guard let rate = Decimal(string: interestRate),
              let minimum = Decimal(string: minimumPayment) else {
            return
        }

        let original = Decimal(string: originalBalance) ?? balance
        let extra = Decimal(string: extraPayment) ?? 0
        let aprDecimal = rate / 100

        if let debt = existingDebt {
            debt.name = name
            debt.currentBalance = balance
            debt.originalBalance = original
            debt.interestRate = aprDecimal
            debt.minimumPayment = minimum
            debt.extraPayment = extra
            debt.notes = notes.isEmpty ? nil : notes
            debt.colorHex = selectedColorHex
            debt.linkedAccount = useLinkedAccount ? selectedAccount : nil
        } else {
            let debt = DebtAccount(
                name: name,
                currentBalance: balance,
                originalBalance: original,
                interestRate: aprDecimal,
                minimumPayment: minimum,
                extraPayment: extra,
                colorHex: selectedColorHex,
                notes: notes.isEmpty ? nil : notes,
                linkedAccount: useLinkedAccount ? selectedAccount : nil
            )
            modelContext.insert(debt)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    DebtFormView()
        .modelContainer(for: [DebtAccount.self, Account.self], inMemory: true)
}
