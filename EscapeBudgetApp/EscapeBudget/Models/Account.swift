import Foundation
import SwiftData
import SwiftUI

@Model
final class Account: DemoDataTrackable {
    var name: String
    var typeRawValue: String
    var balance: Decimal
    var transactions: [Transaction]?
    /// Transfers that are intended for this account but not yet matched to a specific transaction.
    var intendedTransferTransactions: [Transaction]?
    var notes: String?
    /// When the user first created / set up this account in the app.
    /// Optional for backwards compatibility with older stores.
    var createdAt: Date?
    /// Accounts created for tracking-only purposes (e.g., external transfer counterpart).
    var isTrackingOnly: Bool = false
    /// Timestamp of the last successful reconciliation for this account.
    var lastReconciledAt: Date?
    /// Highest reconciliation reminder threshold already sent for the current reconciliation cycle.
    /// (0 / nil means none sent yet.)
    var reconcileReminderLastThresholdSent: Int?
    var isDemoData: Bool = false
    
    var type: AccountType {
        get { AccountType(rawValue: typeRawValue) ?? .chequing }
        set { typeRawValue = newValue.rawValue }
    }
    
    init(
        name: String,
        type: AccountType,
        balance: Decimal = 0.0,
        notes: String? = nil,
        createdAt: Date? = Date(),
        isTrackingOnly: Bool = false,
        lastReconciledAt: Date? = nil,
        reconcileReminderLastThresholdSent: Int? = 0,
        isDemoData: Bool = false
    ) {
        self.name = name
        self.typeRawValue = type.rawValue
        self.balance = balance
        self.transactions = []
        self.notes = notes
        self.createdAt = createdAt
        self.isTrackingOnly = isTrackingOnly
        self.lastReconciledAt = lastReconciledAt
        self.reconcileReminderLastThresholdSent = reconcileReminderLastThresholdSent
        self.isDemoData = isDemoData
    }
}

enum AccountType: String, Codable, CaseIterable, Identifiable {
    case chequing = "Chequing"
    case savings = "Savings"
    case creditCard = "Credit Card"
    case investment = "Investment"
    case lineOfCredit = "Line of Credit"
    case mortgage = "Mortgage"
    case loans = "Loans"
    case other = "Other"

    var id: String { rawValue }
    
    var icon: String {
        switch self {
        case .chequing: return "building.columns.fill"
        case .savings: return "banknote.fill"
        case .creditCard: return "creditcard.fill"
        case .investment: return "chart.bar.xaxis"
        case .lineOfCredit: return "signature"
        case .mortgage: return "house.fill"
        case .loans: return "person.text.rectangle.fill"
        case .other: return "dollarsign.circle.fill"
        }
    }
    
    func color(for mode: AppColorMode) -> Color {
        switch self {
        case .chequing: return AppDesign.Colors.tint(for: mode)
        case .savings: return AppDesign.Colors.success(for: mode)
        case .creditCard: return AppDesign.Colors.warning(for: mode)
        case .investment: return .purple
        case .lineOfCredit: return .teal
        case .mortgage: return .indigo
        case .loans: return .brown
        case .other: return .gray
        }
    }

    var color: Color {
        color(for: AppDesign.Colors.currentModeFromDefaults())
    }
}
