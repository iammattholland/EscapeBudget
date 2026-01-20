import SwiftUI
import SwiftData

struct DebtFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    var existingDebt: DebtAccount?

    @State private var name = ""
    @State private var currentBalance = ""
    @State private var originalBalance = ""
    @State private var interestRate = ""
    @State private var minimumPayment = ""
    @State private var extraPayment = ""
    @State private var notes = ""
    @State private var selectedColorHex = "FF3B30"

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
                Section("Debt Details") {
                    TextField("Name", text: $name)

                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("Current Balance", text: $currentBalance)
                            .keyboardType(.decimalPad)
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
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: AppTheme.Spacing.compact) {
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
                    .padding(.vertical, AppTheme.Spacing.compact)
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
                                .foregroundStyle(AppColors.danger(for: appColorMode))
                        }

                        HStack {
                            Text("Debt-Free Date")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(projection.payoffDate, format: .dateTime.month().year())
                                .fontWeight(.medium)
                                .foregroundStyle(AppColors.success(for: appColorMode))
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
        !name.isEmpty &&
        Decimal(string: currentBalance) != nil &&
        Decimal(string: interestRate) != nil &&
        Decimal(string: minimumPayment) != nil
    }

    private var payoffProjection: DebtPayoffCalculator.PayoffProjection? {
        guard let balance = Decimal(string: currentBalance),
              let rate = Decimal(string: interestRate),
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

    private func saveDebt() {
        guard let balance = Decimal(string: currentBalance),
              let rate = Decimal(string: interestRate),
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
        } else {
            let debt = DebtAccount(
                name: name,
                currentBalance: balance,
                originalBalance: original,
                interestRate: aprDecimal,
                minimumPayment: minimum,
                extraPayment: extra,
                colorHex: selectedColorHex,
                notes: notes.isEmpty ? nil : notes
            )
            modelContext.insert(debt)
        }

        try? modelContext.save()
        dismiss()
    }
}

#Preview {
    DebtFormView()
        .modelContainer(for: [DebtAccount.self], inMemory: true)
}
