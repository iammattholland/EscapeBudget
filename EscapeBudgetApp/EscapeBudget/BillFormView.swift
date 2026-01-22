import SwiftUI
import SwiftData

struct BillFormView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    var existingBill: RecurringPurchase?

    @State private var name = ""
    @State private var amount = ""
    @State private var frequency: RecurrenceFrequency = .monthly
    @State private var nextDate = Date()
    @State private var category = "Bills"
    @State private var notes = ""
    @State private var isActive = true

    private let categoryOptions = [
        "Bills",
        "Rent",
        "Mortgage",
        "Utilities",
        "Internet",
        "Phone",
        "Insurance",
        "Subscription",
        "Gym",
        "Car",
        "Loan",
        "Healthcare",
        "Other"
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("Bill Details") {
                    TextField("Name", text: $name)

                    HStack {
                        Text(currencySymbol)
                            .foregroundStyle(.secondary)
                        TextField("Amount", text: $amount)
                            .keyboardType(.decimalPad)
                    }

                    Picker("Frequency", selection: $frequency) {
                        ForEach(RecurrenceFrequency.allCases, id: \.self) { freq in
                            Text(freq.rawValue).tag(freq)
                        }
                    }

                    DatePicker("Next Due Date", selection: $nextDate, displayedComponents: .date)
                }

                Section("Category") {
                    Picker("Category", selection: $category) {
                        ForEach(categoryOptions, id: \.self) { cat in
                            HStack {
                                Image(systemName: iconForCategory(cat))
                                Text(cat)
                            }
                            .tag(cat)
                        }
                    }
                    .pickerStyle(.navigationLink)
                }

                Section {
                    Toggle("Active", isOn: $isActive)
                } footer: {
                    Text("Inactive bills won't appear in upcoming reminders.")
                }

                if let projection = monthlyProjection {
                    Section("Cost Breakdown") {
                        LabeledContent("Monthly Equivalent") {
                            Text(projection.monthly, format: .currency(code: currencyCode))
                                .fontWeight(.medium)
                        }

                        LabeledContent("Yearly Cost") {
                            Text(projection.yearly, format: .currency(code: currencyCode))
                                .fontWeight(.medium)
                                .foregroundStyle(AppColors.danger(for: appColorMode))
                        }
                    }
                }

                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingBill == nil ? "Add Bill" : "Edit Bill")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveBill()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                if let bill = existingBill {
                    name = bill.name
                    amount = "\(bill.amount)"
                    frequency = bill.recurrenceFrequency
                    nextDate = bill.nextDate
                    category = bill.category
                    notes = bill.notes ?? ""
                    isActive = bill.isActive
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
        !name.isEmpty && Decimal(string: amount) != nil
    }

    private var monthlyProjection: (monthly: Decimal, yearly: Decimal)? {
        guard let amt = Decimal(string: amount), amt > 0 else { return nil }

        let monthly: Decimal
        switch frequency {
        case .weekly:
            monthly = amt * Decimal(52) / Decimal(12)
        case .biweekly:
            monthly = amt * Decimal(26) / Decimal(12)
        case .monthly:
            monthly = amt
        case .quarterly:
            monthly = amt / Decimal(3)
        case .yearly:
            monthly = amt / Decimal(12)
        }

        return (monthly: monthly, yearly: monthly * 12)
    }

    // MARK: - Actions

    private func saveBill() {
        guard let amt = Decimal(string: amount) else { return }

        if let bill = existingBill {
            bill.name = name
            bill.amount = amt
            bill.frequency = frequency.rawValue
            bill.nextDate = nextDate
            bill.category = category
            bill.notes = notes.isEmpty ? nil : notes
            bill.isActive = isActive
        } else {
            let bill = RecurringPurchase(
                name: name,
                amount: amt,
                frequency: frequency,
                nextDate: nextDate,
                category: category,
                notes: notes.isEmpty ? nil : notes,
                isActive: isActive
            )
            modelContext.insert(bill)
        }

        try? modelContext.save()
        dismiss()
    }

    private func iconForCategory(_ category: String) -> String {
        switch category.lowercased() {
        case "rent", "mortgage", "housing":
            return "house.fill"
        case "utilities", "electricity", "gas", "water":
            return "bolt.fill"
        case "internet", "wifi", "cable":
            return "wifi"
        case "phone", "mobile", "cellphone":
            return "iphone"
        case "insurance":
            return "shield.fill"
        case "subscription", "subscriptions", "streaming":
            return "play.tv.fill"
        case "gym", "fitness":
            return "figure.run"
        case "car", "auto", "vehicle":
            return "car.fill"
        case "loan", "loans", "debt":
            return "creditcard.fill"
        case "healthcare", "health", "medical":
            return "heart.fill"
        case "bills":
            return "doc.text.fill"
        default:
            return "calendar.badge.clock"
        }
    }
}

#Preview {
    BillFormView()
        .modelContainer(for: [RecurringPurchase.self], inMemory: true)
}

#Preview("Edit Bill") {
    BillFormView(existingBill: RecurringPurchase(
        name: "Netflix",
        amount: 15.99,
        frequency: .monthly,
        nextDate: Date(),
        category: "Subscription"
    ))
    .modelContainer(for: [RecurringPurchase.self], inMemory: true)
}
