import Foundation
import SwiftData

/// Service for applying auto rules to transactions
@MainActor
final class AutoRulesService {
    private let modelContext: ModelContext
    private lazy var categoryPredictor: CategoryPredictor = {
        CategoryPredictor(modelContext: modelContext)
    }()

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Fetch Rules

	/// Fetch all enabled rules, sorted by order
	func fetchEnabledRules() -> [AutoRule] {
		let descriptor = FetchDescriptor<AutoRule>(
			predicate: #Predicate<AutoRule> { $0.isEnabled },
			sortBy: [SortDescriptor(\.order)]
		)
		let rules = (try? modelContext.fetch(descriptor)) ?? []
		sanitizeRuleReferencesIfNeeded(rules)
		return rules
	}

	/// Fetch all rules, sorted by order
	func fetchAllRules() -> [AutoRule] {
		let descriptor = FetchDescriptor<AutoRule>(
			sortBy: [SortDescriptor(\.order)]
		)
		let rules = (try? modelContext.fetch(descriptor)) ?? []
		sanitizeRuleReferencesIfNeeded(rules)
		return rules
	}

	private func sanitizeRuleReferencesIfNeeded(_ rules: [AutoRule]) {
		guard !rules.isEmpty else { return }

		let categories = (try? modelContext.fetch(FetchDescriptor<Category>())) ?? []
		let tags = (try? modelContext.fetch(FetchDescriptor<TransactionTag>())) ?? []
		let categoryIDs = Set(categories.map(\.persistentModelID))
		let tagIDs = Set(tags.map(\.persistentModelID))

		var didMutate = false

		for rule in rules {
			if let category = rule.actionCategory,
			   !categoryIDs.contains(category.persistentModelID) {
				rule.actionCategory = nil
				didMutate = true
			}

			if let ruleTags = rule.actionTags, !ruleTags.isEmpty {
				let filtered = ruleTags.filter { tagIDs.contains($0.persistentModelID) }
				if filtered.count != ruleTags.count {
					rule.actionTags = filtered.isEmpty ? nil : filtered
					didMutate = true
				}
			}
		}

			if didMutate {
				modelContext.safeSave(context: "AutoRulesService.purgeInvalidReferences", showErrorToUser: false)
			}
		}

    // MARK: - Apply Rules to Transaction

    /// Result of applying rules to a transaction
    struct RuleApplicationResult {
        var rulesApplied: [AutoRule]
        var fieldsChanged: [AutoRuleFieldChange]
        var applications: [AutoRuleApplication]
        var mlPrediction: CategoryPredictor.Prediction?
    }

	    /// Apply all enabled rules to a single transaction
	    /// Returns the rules that were applied
	    func applyRules(
	        to transaction: Transaction,
	        originalPayee: String? = nil
	    ) -> RuleApplicationResult {
        let rules = fetchEnabledRules()
        var result = RuleApplicationResult(rulesApplied: [], fieldsChanged: [], applications: [], mlPrediction: nil)

	        for rule in rules {
	            let payeeToMatch = originalPayee ?? transaction.payee
            guard rule.matches(
                payee: payeeToMatch,
                account: transaction.account,
                amount: transaction.amount
            ) else { continue }

	            let applications = applyRuleInternal(rule, to: transaction)
	            if !applications.isEmpty {
	                result.rulesApplied.append(rule)
	                result.applications.append(contentsOf: applications)

                // Track which fields changed
                for app in applications {
                    if let field = AutoRuleFieldChange(rawValue: app.fieldChanged),
                       !result.fieldsChanged.contains(field) {
                        result.fieldsChanged.append(field)
                    }
                }

	                // Update rule statistics
	                rule.timesApplied += 1
	                rule.lastAppliedAt = Date()
	            }
	        }

        // If no rule assigned a category, try ML prediction
        if transaction.category == nil, !result.fieldsChanged.contains(.category) {
            result.mlPrediction = categoryPredictor.predictCategory(for: transaction)
        }

	        return result
	    }

	    /// Apply a single rule to a transaction (no match check).
	    private func applyRuleInternal(_ rule: AutoRule, to transaction: Transaction) -> [AutoRuleApplication] {
	        var applications: [AutoRuleApplication] = []

        // Rename payee
        if let newPayee = rule.actionRenamePayee, !newPayee.isEmpty, transaction.payee != newPayee {
            let app = AutoRuleApplication(
                rule: rule,
                transaction: transaction,
                fieldChanged: AutoRuleFieldChange.payee.rawValue,
                oldValue: transaction.payee,
                newValue: newPayee
            )
            modelContext.insert(app)
            applications.append(app)
            transaction.payee = newPayee
        }

        // Set category
        if let category = rule.actionCategory {
            let oldCategory = transaction.category?.name
            if transaction.category?.persistentModelID != category.persistentModelID {
                let app = AutoRuleApplication(
                    rule: rule,
                    transaction: transaction,
                    fieldChanged: AutoRuleFieldChange.category.rawValue,
                    oldValue: oldCategory,
                    newValue: category.name
                )
                modelContext.insert(app)
                applications.append(app)
                transaction.category = category
            }
        }

        // Set tags
        if let tags = rule.actionTags, !tags.isEmpty {
            let existingTagIDs = Set(transaction.tags?.map(\.persistentModelID) ?? [])
            let newTagIDs = Set(tags.map(\.persistentModelID))

            if existingTagIDs != newTagIDs {
                let oldTags = transaction.tags?.map(\.name).joined(separator: ", ")
                let newTagNames = tags.map(\.name).joined(separator: ", ")

                let app = AutoRuleApplication(
                    rule: rule,
                    transaction: transaction,
                    fieldChanged: AutoRuleFieldChange.tags.rawValue,
                    oldValue: oldTags,
                    newValue: newTagNames
                )
                modelContext.insert(app)
                applications.append(app)

                // Merge tags (add new ones, keep existing)
                var currentTags = transaction.tags ?? []
                for tag in tags {
                    if !currentTags.contains(where: { $0.persistentModelID == tag.persistentModelID }) {
                        currentTags.append(tag)
                    }
                }
                transaction.tags = currentTags
            }
        }

        // Set memo
        if let memo = rule.actionMemo, !memo.isEmpty {
            let oldMemo = transaction.memo
            let newMemo: String

            if rule.actionAppendMemo, let existing = transaction.memo, !existing.isEmpty {
                newMemo = "\(existing) | \(memo)"
            } else {
                newMemo = memo
            }

            let normalizedNewMemo = TransactionTextLimits.normalizedMemo(newMemo)
            if transaction.memo != normalizedNewMemo {
                let app = AutoRuleApplication(
                    rule: rule,
                    transaction: transaction,
                    fieldChanged: AutoRuleFieldChange.memo.rawValue,
                    oldValue: oldMemo,
                    newValue: normalizedNewMemo
                )
                modelContext.insert(app)
                applications.append(app)
                transaction.memo = normalizedNewMemo
            }
        }

        // Set status
        if let status = rule.actionStatus, transaction.status != status {
            let app = AutoRuleApplication(
                rule: rule,
                transaction: transaction,
                fieldChanged: AutoRuleFieldChange.status.rawValue,
                oldValue: transaction.status.rawValue,
                newValue: status.rawValue
            )
            modelContext.insert(app)
            applications.append(app)
            transaction.status = status
        }

	        return applications
	    }

	    /// Apply a specific rule to a transaction (with match check), optionally updating rule stats.
	    /// - Returns: The `AutoRuleApplication` rows created (empty if no changes applied or no match).
	    func apply(rule: AutoRule, to transaction: Transaction, originalPayee: String? = nil, updateStats: Bool = true) -> [AutoRuleApplication] {
	        let payeeToMatch = originalPayee ?? transaction.payee
	        guard rule.matches(payee: payeeToMatch, account: transaction.account, amount: transaction.amount) else { return [] }

	        let apps = applyRuleInternal(rule, to: transaction)
	        if updateStats, !apps.isEmpty {
	            rule.timesApplied += 1
	            rule.lastAppliedAt = Date()
	        }
	        return apps
	    }

    // MARK: - Apply Rules to Imported Transaction

    /// Apply rules to an ImportedTransaction before it's converted to a real Transaction
    /// Returns the modified data
    func applyRulesToImportData(
        _ data: inout ImportedTransaction,
        account: Account?,
        allRules: [AutoRule]? = nil
    ) -> [AutoRule] {
        let rules = allRules ?? fetchEnabledRules()
        var appliedRules: [AutoRule] = []

        for rule in rules {
            guard rule.matches(
                payee: data.payee,
                account: account,
                amount: data.amount
            ) else { continue }

            var didApply = false

            // Rename payee
            if let newPayee = rule.actionRenamePayee, !newPayee.isEmpty {
                data.payee = newPayee
                didApply = true
            }

            // Note: Category and Tags are handled via rawCategory/rawTags
            // which get resolved later. For auto-rules at import time,
            // we need to set these directly since we have the actual objects.

            // Set memo
            if let memo = rule.actionMemo, !memo.isEmpty {
                if rule.actionAppendMemo, let existing = data.memo, !existing.isEmpty {
                    data.memo = "\(existing) | \(memo)"
                } else {
                    data.memo = memo
                }
                data.memo = TransactionTextLimits.normalizedMemo(data.memo)
                didApply = true
            }

            // Set status
            if let status = rule.actionStatus {
                data.status = status
                didApply = true
            }

            if didApply {
                appliedRules.append(rule)
                rule.timesApplied += 1
                rule.lastAppliedAt = Date()
            }
        }

        return appliedRules
    }

    // MARK: - Preview Matching

    /// Preview which transactions would match a rule
    func previewMatchingTransactions(
        for rule: AutoRule,
        limit: Int = 50
    ) -> [Transaction] {
        // Fetch recent transactions
        var descriptor = FetchDescriptor<Transaction>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 500 // Check up to 500 recent transactions

        guard let transactions = try? modelContext.fetch(descriptor) else {
            return []
        }

        var matches: [Transaction] = []
        for transaction in transactions {
            if rule.matches(
                payee: transaction.payee,
                account: transaction.account,
                amount: transaction.amount
            ) {
                matches.append(transaction)
                if matches.count >= limit { break }
            }
        }

        return matches
    }

    // MARK: - History

    /// Fetch recent rule applications
    func fetchRecentApplications(limit: Int = 100) -> [AutoRuleApplication] {
        var descriptor = FetchDescriptor<AutoRuleApplication>(
            sortBy: [SortDescriptor(\.appliedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch applications for a specific rule
    func fetchApplications(for rule: AutoRule, limit: Int = 50) -> [AutoRuleApplication] {
        let ruleID = rule.id
        var descriptor = FetchDescriptor<AutoRuleApplication>(
            predicate: #Predicate<AutoRuleApplication> { app in
                app.rule?.id == ruleID
            },
            sortBy: [SortDescriptor(\.appliedAt, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Mark an application as overridden (user manually changed the value)
    func markAsOverridden(_ application: AutoRuleApplication) {
        application.wasOverridden = true
    }

    // MARK: - Rule Management

    /// Get the next order value for a new rule
    func nextRuleOrder() -> Int {
        let rules = fetchAllRules()
        return (rules.map(\.order).max() ?? -1) + 1
    }

    /// Reorder rules
    func reorderRules(_ rules: [AutoRule]) {
        for (index, rule) in rules.enumerated() {
            rule.order = index
            rule.updatedAt = Date()
        }
    }

    /// Delete a rule and its applications
    func deleteRule(_ rule: AutoRule) {
        // Delete applications first
        let ruleID = rule.id
        let descriptor = FetchDescriptor<AutoRuleApplication>(
            predicate: #Predicate<AutoRuleApplication> { app in
                app.rule?.id == ruleID
            }
        )

        if let applications = try? modelContext.fetch(descriptor) {
            for app in applications {
                modelContext.delete(app)
            }
        }

        modelContext.delete(rule)
    }

    // MARK: - ML Category Prediction

    /// Get ML category prediction for a transaction
    func predictCategory(for transaction: Transaction) -> CategoryPredictor.Prediction? {
        return categoryPredictor.predictCategory(for: transaction)
    }

    /// Get top N category predictions
    func predictTopCategories(for transaction: Transaction, limit: Int = 3) -> [CategoryPredictor.Prediction] {
        return categoryPredictor.predictTopCategories(for: transaction, limit: limit)
    }

    /// Learn from user's category assignment
    func learnFromCategorization(transaction: Transaction, wasAutoDetected: Bool) {
        categoryPredictor.learnFromCategorization(transaction: transaction, wasAutoDetected: wasAutoDetected)
    }

    /// Learn from rejected ML suggestion
    func learnFromRejection(transaction: Transaction, rejectedCategory: Category) {
        categoryPredictor.learnFromRejection(transaction: transaction, rejectedCategory: rejectedCategory)
    }

    /// Bulk learn from transaction history
    func learnFromHistory(limit: Int = 500) async {
        await categoryPredictor.patternLearner.learnFromHistory(limit: limit)
    }
}
