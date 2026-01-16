import Foundation
import SwiftData

@Model
final class SavingsGoal: DemoDataTrackable {
    var name: String
    var targetAmount: Decimal
    var currentAmount: Decimal
    var targetDate: Date?
    var monthlyContribution: Decimal?
    var colorHex: String  // For visual identification
    var notes: String?
    var isAchieved: Bool
    var createdDate: Date
    var isDemoData: Bool = false
    
    @Relationship(inverse: \Category.savingsGoal)
    var category: Category?
    
    init(
        name: String,
        targetAmount: Decimal,
        currentAmount: Decimal = 0,
        targetDate: Date? = nil,
        monthlyContribution: Decimal? = nil,
        colorHex: String = "007AFF", // Default blue
        notes: String? = nil,
        isAchieved: Bool = false,
        isDemoData: Bool = false
    ) {
        self.name = name
        self.targetAmount = targetAmount
        self.currentAmount = currentAmount
        self.targetDate = targetDate
        self.monthlyContribution = monthlyContribution
        self.colorHex = colorHex
        self.notes = notes
        self.isAchieved = isAchieved
        self.createdDate = Date()
        self.isDemoData = isDemoData
    }
    
    // Computed properties
    var progressPercentage: Double {
        guard targetAmount > 0 else { return 0 }
        return min(100, Double(truncating: (currentAmount / targetAmount * 100) as NSNumber))
    }
    
    var amountRemaining: Decimal {
        max(0, targetAmount - currentAmount)
    }
    
    var calculatedMonthlyContribution: Decimal? {
        guard let targetDate = targetDate, targetDate > Date() else { return nil }
        let calendar = Calendar.current
        let months = calendar.dateComponents([.month], from: Date(), to: targetDate).month ?? 1
        guard months > 0 else { return nil }
        return amountRemaining / Decimal(months)
    }
    
    var calculatedCompletionDate: Date? {
        guard let monthlyContribution = monthlyContribution, monthlyContribution > 0 else { return nil }
        let months = Int(ceil(Double(truncating: (amountRemaining / monthlyContribution) as NSNumber)))
        return Calendar.current.date(byAdding: .month, value: months, to: Date())
    }
}
