import SwiftUI
import SwiftData

struct BudgetCategoryFixSheet: View {
    let category: Category
    let spent: Decimal
    let currencyCode: String
    let dateRange: (start: Date, end: Date)
    let transactions: [Transaction]

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @State private var assignedInput: String = ""
    @State private var errorMessage: String?
    @State private var showingTransactions = false

    private var remaining: Decimal {
        category.assigned - spent
    }

    private var statusTint: Color {
        remaining >= 0 ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Status") {
                    HStack {
                        Text("Assigned")
                        Spacer()
                        Text(category.assigned, format: .currency(code: currencyCode))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Spent")
                        Spacer()
                        Text(spent, format: .currency(code: currencyCode))
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                            .monospacedDigit()
                    }
                    HStack {
                        Text("Remaining")
                        Spacer()
                        Text(remaining, format: .currency(code: currencyCode))
                            .foregroundStyle(statusTint)
                            .monospacedDigit()
                    }
                }

                Section("Fix Budget") {
                    TextField("Assigned", text: $assignedInput)
                        .keyboardType(.decimalPad)

                    HStack {
                        Button("Match spent") {
                            assignedInput = "\(spent)"
                        }
                        Spacer()
                        Button("Add 10% buffer") {
                            let buffered = spent * Decimal(1.10)
                            assignedInput = "\(buffered)"
                        }
                    }
                    .font(.subheadline)

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(AppColors.danger(for: appColorMode))
                            .appCaptionText()
                    }
                }

                Section("Transactions") {
                    Button("View Transactions in \(category.name)") {
                        showingTransactions = true
                    }
                }
            }
            .navigationTitle(category.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAssigned() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                assignedInput = "\(category.assigned)"
            }
            .sheet(isPresented: $showingTransactions) {
                CategoryTransactionsSheet(
                    category: category,
                    transactions: transactions,
                    dateRange: dateRange
                )
            }
        }
    }

    private func saveAssigned() {
        let parsed = ImportParser.parseAmount(assignedInput)
            ?? Decimal(string: assignedInput.trimmingCharacters(in: .whitespacesAndNewlines))
        guard let parsed else {
            errorMessage = "Enter a valid amount."
            return
        }

        errorMessage = nil
        category.assigned = parsed
        if !modelContext.safeSave(
            context: "BudgetCategoryFixSheet.saveAssigned",
            userMessage: "Couldn’t update the budget amount. Please try again.",
            showErrorToUser: true
        ) {
            errorMessage = "Couldn’t save changes."
        }
    }
}

