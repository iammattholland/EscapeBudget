import Foundation
import SwiftData

// MARK: - Match Condition Types

enum PayeeMatchCondition: String, Codable, CaseIterable, Identifiable {
    case contains = "Contains"
    case equals = "Equals"
    case startsWith = "Starts with"
    case endsWith = "Ends with"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .contains: return "text.magnifyingglass"
        case .equals: return "equal"
        case .startsWith: return "arrow.right.to.line"
        case .endsWith: return "arrow.left.to.line"
        }
    }
}

enum AmountMatchCondition: String, Codable, CaseIterable, Identifiable {
    case any = "Any amount"
    case equals = "Equals"
    case greaterThan = "Greater than"
    case lessThan = "Less than"
    case between = "Between"

    var id: String { rawValue }
}

// MARK: - Auto Rule Model

@Model
final class AutoRule {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var order: Int
    var createdAt: Date
    var updatedAt: Date

    // MARK: - Matching Conditions

    /// Payee matching
    var matchPayeeConditionRaw: String?
    var matchPayeeValue: String?
    var matchPayeeCaseSensitive: Bool

    /// Account matching (nil = any account)
    @Relationship
    var matchAccount: Account?

    /// Amount matching
    var matchAmountConditionRaw: String?
    var matchAmountValue: Decimal?
    var matchAmountValueMax: Decimal? // For "between" condition

    // MARK: - Actions

    /// Rename payee to this value
    var actionRenamePayee: String?

    /// Assign this category
    @Relationship
    var actionCategory: Category?

    /// Assign these tags
    @Relationship
    var actionTags: [TransactionTag]?

    /// Set memo
    var actionMemo: String?
    var actionAppendMemo: Bool // If true, append to existing memo instead of replacing

    /// Set status
    var actionStatusRaw: String?

    // MARK: - Statistics

    var timesApplied: Int
    var lastAppliedAt: Date?

    // MARK: - Computed Properties

    var matchPayeeCondition: PayeeMatchCondition? {
        get {
            guard let raw = matchPayeeConditionRaw else { return nil }
            return PayeeMatchCondition(rawValue: raw)
        }
        set { matchPayeeConditionRaw = newValue?.rawValue }
    }

    var matchAmountCondition: AmountMatchCondition? {
        get {
            guard let raw = matchAmountConditionRaw else { return nil }
            return AmountMatchCondition(rawValue: raw)
        }
        set { matchAmountConditionRaw = newValue?.rawValue }
    }

    var actionStatus: TransactionStatus? {
        get {
            guard let raw = actionStatusRaw else { return nil }
            return TransactionStatus(rawValue: raw)
        }
        set { actionStatusRaw = newValue?.rawValue }
    }

    /// Human-readable summary of what this rule matches
    var matchSummary: String {
        var parts: [String] = []

        if let condition = matchPayeeCondition, let value = matchPayeeValue, !value.isEmpty {
            parts.append("Payee \(condition.rawValue.lowercased()) \"\(value)\"")
        }

        if let account = matchAccount {
            parts.append("Account: \(account.name)")
        }

        if let condition = matchAmountCondition, condition != .any {
            if let value = matchAmountValue {
                switch condition {
                case .equals:
                    parts.append("Amount = \(value)")
                case .greaterThan:
                    parts.append("Amount > \(value)")
                case .lessThan:
                    parts.append("Amount < \(value)")
                case .between:
                    if let max = matchAmountValueMax {
                        parts.append("Amount \(value) - \(max)")
                    }
                case .any:
                    break
                }
            }
        }

        return parts.isEmpty ? "No conditions set" : parts.joined(separator: ", ")
    }

    /// Human-readable summary of what this rule does
    var actionSummary: String {
        var parts: [String] = []

        if let rename = actionRenamePayee, !rename.isEmpty {
            parts.append("Rename to \"\(rename)\"")
        }

        if let category = actionCategory {
            parts.append("Categorize as \(category.name)")
        }

        if let tags = actionTags, !tags.isEmpty {
            let tagNames = tags.map(\.name).joined(separator: ", ")
            parts.append("Tag: \(tagNames)")
        }

        if let memo = actionMemo, !memo.isEmpty {
            parts.append(actionAppendMemo ? "Append memo" : "Set memo")
        }

        if let status = actionStatus {
            parts.append("Mark as \(status.rawValue)")
        }

        return parts.isEmpty ? "No actions set" : parts.joined(separator: ", ")
    }

    /// Whether this rule has any actions defined
    var hasActions: Bool {
        (actionRenamePayee != nil && !actionRenamePayee!.isEmpty) ||
        actionCategory != nil ||
        (actionTags != nil && !actionTags!.isEmpty) ||
        (actionMemo != nil && !actionMemo!.isEmpty) ||
        actionStatus != nil
    }

    /// Whether this rule has any matching conditions
    var hasConditions: Bool {
        (matchPayeeCondition != nil && matchPayeeValue != nil && !matchPayeeValue!.isEmpty) ||
        matchAccount != nil ||
        (matchAmountCondition != nil && matchAmountCondition != .any)
    }

    // MARK: - Initialization

    init(
        name: String,
        isEnabled: Bool = true,
        order: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.isEnabled = isEnabled
        self.order = order
        self.createdAt = Date()
        self.updatedAt = Date()
        self.matchPayeeCaseSensitive = false
        self.actionAppendMemo = false
        self.timesApplied = 0
    }

    // MARK: - Matching Logic

    /// Check if a transaction matches this rule's conditions
    func matches(payee: String, account: Account?, amount: Decimal) -> Bool {
        // Check payee condition
        if let condition = matchPayeeCondition, let value = matchPayeeValue, !value.isEmpty {
            let payeeToMatch = matchPayeeCaseSensitive ? payee : payee.lowercased()
            let valueToMatch = matchPayeeCaseSensitive ? value : value.lowercased()

            let payeeMatches: Bool
            switch condition {
            case .contains:
                payeeMatches = payeeToMatch.contains(valueToMatch)
            case .equals:
                payeeMatches = payeeToMatch == valueToMatch
            case .startsWith:
                payeeMatches = payeeToMatch.hasPrefix(valueToMatch)
            case .endsWith:
                payeeMatches = payeeToMatch.hasSuffix(valueToMatch)
            }

            if !payeeMatches { return false }
        }

        // Check account condition
        if let requiredAccount = matchAccount {
            guard let txAccount = account,
                  txAccount.persistentModelID == requiredAccount.persistentModelID else {
                return false
            }
        }

        // Check amount condition
        if let condition = matchAmountCondition, condition != .any {
            guard let value = matchAmountValue else { return false }

            let amountMatches: Bool
            switch condition {
            case .equals:
                amountMatches = amount == value
            case .greaterThan:
                amountMatches = amount > value
            case .lessThan:
                amountMatches = amount < value
            case .between:
                guard let maxValue = matchAmountValueMax else { return false }
                amountMatches = amount >= value && amount <= maxValue
            case .any:
                amountMatches = true
            }

            if !amountMatches { return false }
        }

        return true
    }
}

// MARK: - Auto Rule Application (History)

@Model
final class AutoRuleApplication {
    var id: UUID
    var appliedAt: Date
    var fieldChanged: String // "payee", "category", "tags", "memo", "status"
    var oldValue: String?
    var newValue: String?
    var wasOverridden: Bool

    @Relationship
    var rule: AutoRule?

    @Relationship
    var transaction: Transaction?

    init(
        rule: AutoRule,
        transaction: Transaction,
        fieldChanged: String,
        oldValue: String?,
        newValue: String?
    ) {
        self.id = UUID()
        self.appliedAt = Date()
        self.fieldChanged = fieldChanged
        self.oldValue = oldValue
        self.newValue = newValue
        self.wasOverridden = false
        self.rule = rule
        self.transaction = transaction
    }
}

// MARK: - Field Change Type

enum AutoRuleFieldChange: String, CaseIterable {
    case payee = "Payee"
    case category = "Category"
    case tags = "Tags"
    case memo = "Memo"
    case status = "Status"

    var systemImage: String {
        switch self {
        case .payee: return "person.text.rectangle"
        case .category: return "folder"
        case .tags: return "tag"
        case .memo: return "note.text"
        case .status: return "checkmark.circle"
        }
    }
}
