import SwiftUI
import SwiftData

struct PayeeTransactionsSheet: View {
    let payee: String
    let transactions: [Transaction]
    let dateRange: (start: Date, end: Date)
    let onCreateRule: () -> Void

    @AppStorage("currencyCode") private var currencyCode = "USD"
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode
    @State private var selectedTransaction: Transaction?

    private var totalSpent: Decimal {
        let net = transactions.reduce(Decimal.zero) { $0 + $1.amount }
        let used = max(Decimal.zero, -net)
        return used
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: AppTheme.Spacing.medium) {
                    HStack(spacing: AppTheme.Spacing.large) {
                        VStack(spacing: AppTheme.Spacing.micro) {
                            Text("Transactions")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text("\(transactions.count)")
                                .appTitleText()
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }

                        Divider()
                            .frame(height: 40)

                        VStack(spacing: AppTheme.Spacing.micro) {
                            Text("Spent")
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                            Text(totalSpent, format: .currency(code: currencyCode))
                                .appTitleText()
                                .foregroundStyle(AppColors.danger(for: appColorMode))
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                        }
                    }

                    let formatter = DateFormatter()
                    let _ = formatter.dateFormat = "MMM d, yyyy"
                    Text("\(formatter.string(from: dateRange.start)) – \(formatter.string(from: dateRange.end))")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(Color(.systemGroupedBackground))

                if transactions.isEmpty {
                    EmptyDataCard(
                        systemImage: "tray",
                        title: "No transactions",
                        message: "Transactions for this payee will appear here."
                    )
                } else {
                    List {
                        ForEach(transactions.sorted { $0.date > $1.date }) { transaction in
                            Button {
                                selectedTransaction = transaction
                            } label: {
                                HStack {
                                    VStack(alignment: .leading, spacing: AppTheme.Spacing.micro) {
                                        Text(transaction.payee)
                                            .font(AppTheme.Typography.body)
                                            .fontWeight(.medium)

                                        HStack(spacing: AppTheme.Spacing.compact) {
                                            Text(transaction.date, format: .dateTime.month(.abbreviated).day())
                                                .appCaptionText()
                                                .foregroundStyle(.secondary)

                                            if let account = transaction.account {
                                                Text(account.name)
                                                    .appCaptionText()
                                                    .foregroundStyle(.secondary)
                                            }
                                        }
                                    }

                                    Spacer()

                                    Text(transaction.amount, format: .currency(code: currencyCode))
                                        .appSecondaryBodyText()
                                        .fontWeight(.semibold)
                                        .foregroundStyle(transaction.amount >= 0 ? AppColors.success(for: appColorMode) : .primary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.5)

                                    Image(systemName: "chevron.right")
                                        .appCaptionText()
                                        .foregroundStyle(.tertiary)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .padding(.vertical, AppTheme.Spacing.micro)
                        }
                    }
                    .sheet(item: $selectedTransaction) { transaction in
                        TransactionFormView(transaction: transaction)
                    }
                }
            }
            .navigationTitle(payee)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Create Rule") {
                        dismiss()
                        onCreateRule()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

