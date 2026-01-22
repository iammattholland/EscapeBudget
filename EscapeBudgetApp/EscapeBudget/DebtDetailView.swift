import SwiftUI
import SwiftData

struct DebtDetailView: View {
    @Bindable var debt: DebtAccount
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var showingEditSheet = false

    private var color: Color {
        Color(hex: debt.colorHex) ?? AppColors.danger(for: appColorMode)
    }

    var body: some View {
        List {
            // Progress Section
            Section {
                VStack(spacing: AppTheme.Spacing.medium) {
                    // Large Progress Ring
                    ZStack {
                        Circle()
                            .stroke(color.opacity(0.2), lineWidth: 12)
                            .frame(width: 160, height: 160)

                        Circle()
                            .trim(from: 0, to: debt.payoffProgress)
                            .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                            .frame(width: 160, height: 160)
                            .rotationEffect(.degrees(-90))

                        VStack(spacing: AppTheme.Spacing.micro) {
                            if debt.isPaidOff {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 48))
                                    .foregroundStyle(AppColors.success(for: appColorMode))
                                Text("Paid Off!")
                                    .appSectionTitleText()
                                    .foregroundStyle(AppColors.success(for: appColorMode))
                            } else {
                                Text("\(Int(debt.payoffProgressPercentage))%")
                                    .font(.system(size: 36, weight: .bold, design: .rounded))
                                    .foregroundStyle(color)
                                Text("paid off")
                                    .appCaptionText()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.medium)
                }
            }
            .listRowBackground(Color.clear)

            // Balance Section
            Section("Balance") {
                LabeledContent("Current Balance") {
                    HStack(spacing: AppTheme.Spacing.xSmall) {
                        Text(debt.effectiveBalance, format: .currency(code: currencyCode))
                            .fontWeight(.semibold)
                            .foregroundStyle(debt.isPaidOff ? AppColors.success(for: appColorMode) : AppColors.danger(for: appColorMode))
                        if debt.isSyncedWithAccount {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if debt.isSyncedWithAccount, let account = debt.linkedAccount {
                    LabeledContent("Synced from") {
                        Text(account.name)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent("Original Balance") {
                    Text(debt.originalBalance, format: .currency(code: currencyCode))
                }

                LabeledContent("Amount Paid") {
                    Text(debt.originalBalance - debt.effectiveBalance, format: .currency(code: currencyCode))
                        .foregroundStyle(AppColors.success(for: appColorMode))
                }
            }

            // Interest & Payments Section
            Section("Interest & Payments") {
                LabeledContent("Interest Rate (APR)") {
                    Text("\(debt.interestRatePercentage, format: .number.precision(.fractionLength(2)))%")
                        .foregroundStyle(debt.isHighInterest ? AppColors.danger(for: appColorMode) : .primary)
                }

                LabeledContent("Minimum Payment") {
                    Text(debt.minimumPayment, format: .currency(code: currencyCode))
                }

                if debt.extraPayment > 0 {
                    LabeledContent("Extra Payment") {
                        Text(debt.extraPayment, format: .currency(code: currencyCode))
                            .foregroundStyle(AppColors.success(for: appColorMode))
                    }
                }

                LabeledContent("Total Monthly Payment") {
                    Text(debt.totalMonthlyPayment, format: .currency(code: currencyCode))
                        .fontWeight(.semibold)
                }
            }

            // Payoff Projection Section
            if !debt.isPaidOff {
                Section("Payoff Projection") {
                    if let months = debt.monthsRemaining {
                        LabeledContent("Time to Payoff") {
                            Text(DebtPayoffCalculator.formatMonths(months))
                                .fontWeight(.medium)
                        }
                    }

                    if let payoffDate = debt.projectedPayoffDate {
                        LabeledContent("Debt-Free Date") {
                            Text(payoffDate, format: .dateTime.month().year())
                                .fontWeight(.medium)
                                .foregroundStyle(AppColors.success(for: appColorMode))
                        }
                    }

                    if let totalInterest = debt.projectedTotalInterest {
                        LabeledContent("Total Interest to Pay") {
                            Text(totalInterest, format: .currency(code: currencyCode))
                                .fontWeight(.medium)
                                .foregroundStyle(AppColors.danger(for: appColorMode))
                        }
                    }
                }
            }

            // What If Section
            if !debt.isPaidOff {
                Section {
                    NavigationLink {
                        DebtWhatIfView(debt: debt)
                    } label: {
                        Label("What If Calculator", systemImage: "slider.horizontal.3")
                    }
                } header: {
                    Text("Tools")
                } footer: {
                    Text("See how extra payments could help you pay off this debt faster.")
                }
            }

            // Notes Section
            if let notes = debt.notes, !notes.isEmpty {
                Section("Notes") {
                    Text(notes)
                        .appSecondaryBodyText()
                }
            }
        }
        .navigationTitle(debt.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            DebtFormView(existingDebt: debt)
        }
    }
}

// MARK: - What If Calculator

struct DebtWhatIfView: View {
    let debt: DebtAccount
    @Environment(\.appColorMode) private var appColorMode
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var extraPaymentAmount: Double = 0

    private var maxExtraPayment: Double {
        min(500, Double(truncating: debt.effectiveBalance as NSNumber))
    }

    private var projection: DebtPayoffCalculator.PayoffProjection? {
        let extra = Decimal(extraPaymentAmount)
        let totalPayment = debt.totalMonthlyPayment + extra

        return DebtPayoffCalculator.calculatePayoff(
            balance: debt.effectiveBalance,
            interestRate: debt.interestRate,
            monthlyPayment: totalPayment
        )
    }

    private var originalProjection: DebtPayoffCalculator.PayoffProjection? {
        DebtPayoffCalculator.calculatePayoff(
            balance: debt.effectiveBalance,
            interestRate: debt.interestRate,
            monthlyPayment: debt.totalMonthlyPayment
        )
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: AppTheme.Spacing.medium) {
                    Text("Extra Monthly Payment")
                        .appCaptionText()
                        .foregroundStyle(.secondary)

                    Text(Decimal(extraPaymentAmount), format: .currency(code: currencyCode))
                        .appTitleText()
                        .fontWeight(.bold)
                        .foregroundStyle(AppColors.tint(for: appColorMode))

                    Slider(value: $extraPaymentAmount, in: 0...maxExtraPayment, step: 10)
                        .tint(AppColors.tint(for: appColorMode))
                }
                .padding(.vertical, AppTheme.Spacing.compact)
            }

            if let projection = projection, let original = originalProjection {
                Section("With Extra Payment") {
                    LabeledContent("Time to Payoff") {
                        HStack(spacing: AppTheme.Spacing.xSmall) {
                            Text(DebtPayoffCalculator.formatMonths(projection.monthsToPayoff))
                                .fontWeight(.semibold)
                            if projection.monthsToPayoff < original.monthsToPayoff {
                                Text("(\(original.monthsToPayoff - projection.monthsToPayoff) months faster)")
                                    .appCaptionText()
                                    .foregroundStyle(AppColors.success(for: appColorMode))
                            }
                        }
                    }

                    LabeledContent("Total Interest") {
                        VStack(alignment: .trailing, spacing: AppTheme.Spacing.micro) {
                            Text(projection.totalInterestPaid, format: .currency(code: currencyCode))
                                .fontWeight(.semibold)
                            if projection.totalInterestPaid < original.totalInterestPaid {
                                let saved = original.totalInterestPaid - projection.totalInterestPaid
                                Text("Save \(saved, format: .currency(code: currencyCode))")
                                    .appCaptionText()
                                    .foregroundStyle(AppColors.success(for: appColorMode))
                            }
                        }
                    }

                    LabeledContent("Debt-Free Date") {
                        Text(projection.payoffDate, format: .dateTime.month().year())
                            .fontWeight(.semibold)
                            .foregroundStyle(AppColors.success(for: appColorMode))
                    }
                }

                Section("Current Plan (No Extra)") {
                    LabeledContent("Time to Payoff") {
                        Text(DebtPayoffCalculator.formatMonths(original.monthsToPayoff))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Total Interest") {
                        Text(original.totalInterestPaid, format: .currency(code: currencyCode))
                            .foregroundStyle(.secondary)
                    }

                    LabeledContent("Debt-Free Date") {
                        Text(original.payoffDate, format: .dateTime.month().year())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("What If")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack {
        DebtDetailView(debt: DebtAccount(
            name: "Chase Visa",
            currentBalance: 4500,
            originalBalance: 6000,
            interestRate: 0.2199,
            minimumPayment: 135,
            extraPayment: 50,
            colorHex: "FF3B30"
        ))
    }
    .modelContainer(for: [DebtAccount.self], inMemory: true)
}
