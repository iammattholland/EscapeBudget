import Foundation
import SwiftData

@MainActor
enum TransactionProcessor {
    enum Source: String {
        case `import`
        case manual
        case bulk
        case retroactive
    }

    enum EventKind: String, Hashable {
        case payeeNormalized
        case ruleApplied
        case categoryChanged
        case tagsChanged
        case memoChanged
        case statusChanged
        case transferSuggestion
        case invariantFix
    }

    struct Event: Identifiable, Hashable {
        let id = UUID()
        let transactionID: PersistentIdentifier
        let kind: EventKind
        let title: String
        let detail: String?
    }

    struct Summary: Equatable {
        var processedCount: Int = 0
        var changedCount: Int = 0

        var payeesNormalizedCount: Int = 0
        var transactionsWithRulesApplied: Int = 0
        var rulesAppliedCount: Int = 0

        var fieldChanges: [EventKind: Int] = [:]
        var transferSuggestionsInvolvingProcessed: Int = 0
    }

    struct Result {
        var summary: Summary
        var eventsByTransactionID: [PersistentIdentifier: [Event]]
        var changedTransactions: [Transaction]
        var transferSuggestions: [TransferMatcher.Suggestion]
    }

    struct Config {
        var normalizePayee: Bool
        var applyAutoRules: Bool
        var suggestTransfers: Bool
        var saveDetailedHistory: Bool
        var maxDetailedTransactions: Int
        var maxEventsPerTransaction: Int

        static func fromUserDefaults(source: Source) -> Config {
            let defaults = UserDefaults.standard

            let normalizePayee: Bool = {
                switch source {
                case .import:
                    return defaults.object(forKey: "transactions.normalizePayeeOnImport") as? Bool ?? true
                case .manual:
                    return defaults.object(forKey: "transactions.normalizePayeeOnManual") as? Bool ?? false
                case .bulk, .retroactive:
                    return defaults.object(forKey: "transactions.normalizePayeeOnManual") as? Bool ?? false
                }
            }()

            let applyAutoRules: Bool = {
                switch source {
                case .import:
                    return defaults.object(forKey: "transactions.applyAutoRulesOnImport") as? Bool ?? true
                case .manual:
                    return defaults.object(forKey: "transactions.applyAutoRulesOnManual") as? Bool ?? false
                case .bulk, .retroactive:
                    return defaults.object(forKey: "transactions.applyAutoRulesOnManual") as? Bool ?? false
                }
            }()

            let suggestTransfers: Bool = {
                switch source {
                case .import:
                    return defaults.object(forKey: "transactions.suggestTransfersOnImport") as? Bool ?? true
                case .manual:
                    return defaults.object(forKey: "transactions.suggestTransfersOnManual") as? Bool ?? false
                case .bulk, .retroactive:
                    return defaults.object(forKey: "transactions.suggestTransfersOnManual") as? Bool ?? false
                }
            }()

            let saveDetailedHistory = defaults.object(forKey: "transactions.saveProcessingHistory") as? Bool ?? false

            return Config(
                normalizePayee: normalizePayee,
                applyAutoRules: applyAutoRules,
                suggestTransfers: suggestTransfers,
                saveDetailedHistory: saveDetailedHistory,
                maxDetailedTransactions: 250,
                maxEventsPerTransaction: 8
            )
        }
    }

    static func process(
        transactions: [Transaction],
        in modelContext: ModelContext,
        source: Source,
        originalPayeeByTransactionID: [PersistentIdentifier: String] = [:],
        configOverride: Config? = nil
    ) -> Result {
        var result = Result(summary: Summary(), eventsByTransactionID: [:], changedTransactions: [], transferSuggestions: [])
        guard !transactions.isEmpty else { return result }

        let config = configOverride ?? Config.fromUserDefaults(source: source)

        result.summary.processedCount = transactions.count

        let autoRulesService = AutoRulesService(modelContext: modelContext)

        let processedIDs = Set(transactions.map(\.persistentModelID))

        for transaction in transactions {
            let beforePayee = transaction.payee
            let beforeCategoryID = transaction.category?.persistentModelID
            let beforeTags = Set((transaction.tags ?? []).map(\.persistentModelID))
            let beforeMemo = transaction.memo
            let beforeStatus = transaction.status
            let beforeKind = transaction.kind

            var events: [Event] = []

            if transaction.kind == .standard {
                if config.normalizePayee {
                    let normalized = PayeeNormalizer.normalizeDisplay(transaction.payee)
                    if normalized != transaction.payee {
                        transaction.payee = normalized
                        events.append(Event(
                            transactionID: transaction.persistentModelID,
                            kind: .payeeNormalized,
                            title: "Payee cleaned up",
                            detail: "\(beforePayee) → \(normalized)"
                        ))
                        result.summary.payeesNormalizedCount += 1
                        result.summary.fieldChanges[.payeeNormalized, default: 0] += 1
                    }
                }

                if config.applyAutoRules {
                    let originalPayee = originalPayeeByTransactionID[transaction.persistentModelID] ?? beforePayee
                    let applied = autoRulesService.applyRules(to: transaction, originalPayee: originalPayee)
                    if !applied.rulesApplied.isEmpty {
                        result.summary.transactionsWithRulesApplied += 1
                        result.summary.rulesAppliedCount += applied.rulesApplied.count
                        let names = applied.rulesApplied.map(\.name).joined(separator: ", ")
                        events.append(Event(
                            transactionID: transaction.persistentModelID,
                            kind: .ruleApplied,
                            title: "Auto rule applied",
                            detail: names
                        ))
                    }

                    if applied.fieldsChanged.contains(.category) {
                        result.summary.fieldChanges[.categoryChanged, default: 0] += 1
                    }
                    if applied.fieldsChanged.contains(.tags) {
                        result.summary.fieldChanges[.tagsChanged, default: 0] += 1
                    }
                    if applied.fieldsChanged.contains(.memo) {
                        result.summary.fieldChanges[.memoChanged, default: 0] += 1
                    }
                    if applied.fieldsChanged.contains(.status) {
                        result.summary.fieldChanges[.statusChanged, default: 0] += 1
                    }
                }
            }

            // Enforce invariants (never persist transfer-group categories; transfers never have categories).
            if transaction.kind == .transfer {
                if transaction.category != nil {
                    transaction.category = nil
                    events.append(Event(
                        transactionID: transaction.persistentModelID,
                        kind: .invariantFix,
                        title: "Normalized transfer category",
                        detail: "Removed category from transfer"
                    ))
                }
            } else if transaction.category?.group?.type == .transfer {
                transaction.category = nil
                events.append(Event(
                    transactionID: transaction.persistentModelID,
                    kind: .invariantFix,
                    title: "Normalized transfer category",
                    detail: "Transfer categories are not used"
                ))
            }

            let afterCategoryID = transaction.category?.persistentModelID
            let afterTags = Set((transaction.tags ?? []).map(\.persistentModelID))
            let afterMemo = transaction.memo
            let afterStatus = transaction.status

            if afterCategoryID != beforeCategoryID {
                if let category = transaction.category {
                    events.append(Event(
                        transactionID: transaction.persistentModelID,
                        kind: .categoryChanged,
                        title: "Category updated",
                        detail: category.name
                    ))
                } else if beforeCategoryID != nil {
                    events.append(Event(
                        transactionID: transaction.persistentModelID,
                        kind: .categoryChanged,
                        title: "Category cleared",
                        detail: nil
                    ))
                }
            }

            if afterTags != beforeTags {
                let names = (transaction.tags ?? []).map(\.name).sorted().joined(separator: ", ")
                events.append(Event(
                    transactionID: transaction.persistentModelID,
                    kind: .tagsChanged,
                    title: "Tags updated",
                    detail: names.isEmpty ? nil : names
                ))
            }

            if afterMemo != beforeMemo, let memo = afterMemo, !memo.isEmpty {
                events.append(Event(
                    transactionID: transaction.persistentModelID,
                    kind: .memoChanged,
                    title: "Memo updated",
                    detail: nil
                ))
            }

            if afterStatus != beforeStatus {
                events.append(Event(
                    transactionID: transaction.persistentModelID,
                    kind: .statusChanged,
                    title: "Status updated",
                    detail: afterStatus.rawValue
                ))
            }

            let didChange =
                beforePayee != transaction.payee ||
                beforeCategoryID != afterCategoryID ||
                beforeTags != afterTags ||
                beforeMemo != afterMemo ||
                beforeStatus != afterStatus ||
                beforeKind != transaction.kind

            if didChange {
                result.summary.changedCount += 1
                TransactionStatsUpdateCoordinator.markDirty(transaction: transaction)
                if result.changedTransactions.count < config.maxDetailedTransactions {
                    result.changedTransactions.append(transaction)
                }
            }

            if !events.isEmpty {
                if result.eventsByTransactionID.count < config.maxDetailedTransactions {
                    result.eventsByTransactionID[transaction.persistentModelID] = Array(events.prefix(config.maxEventsPerTransaction))
                }

                if config.saveDetailedHistory {
                    let historyLine = summarizeHistoryLine(events: events)
                    if !historyLine.isEmpty {
                        TransactionHistoryService.append(
                            detail: "Auto processing: \(historyLine)",
                            to: transaction,
                            in: modelContext
                        )
                    }
                }
            }
        }

        if config.suggestTransfers {
            var matcherConfig = TransferMatcher.Config(lookbackDays: 365, maxDaysApart: 14, limit: 250, minScore: 0.62)
            matcherConfig.maxAmountDifferenceCents = 200
            let suggestions = TransferMatcher.suggestions(modelContext: modelContext, config: matcherConfig)
            let involving = suggestions.filter { processedIDs.contains($0.baseID) || processedIDs.contains($0.matchID) }
            result.transferSuggestions = involving
            if !involving.isEmpty {
                result.summary.transferSuggestionsInvolvingProcessed = involving.count

                // Attach per-transaction "suggested transfer" events (capped) so the UI can explain why something is in the inbox.
                for suggestion in involving.prefix(config.maxDetailedTransactions) {
                    if processedIDs.contains(suggestion.baseID) {
                        addTransferSuggestionEvent(
                            for: suggestion.baseID,
                            suggestion: suggestion,
                            otherID: suggestion.matchID,
                            in: modelContext,
                            result: &result,
                            config: config
                        )
                    }
                    if processedIDs.contains(suggestion.matchID) {
                        addTransferSuggestionEvent(
                            for: suggestion.matchID,
                            suggestion: suggestion,
                            otherID: suggestion.baseID,
                            in: modelContext,
                            result: &result,
                            config: config
                        )
                    }
                }
            }
        }

        return result
    }

    private static func addTransferSuggestionEvent(
        for transactionID: PersistentIdentifier,
        suggestion: TransferMatcher.Suggestion,
        otherID: PersistentIdentifier,
        in modelContext: ModelContext,
        result: inout Result,
        config: Config
    ) {
        if result.eventsByTransactionID[transactionID] == nil, result.eventsByTransactionID.count >= config.maxDetailedTransactions {
            return
        }

        let other = modelContext.model(for: otherID) as? Transaction
        let otherLabel: String = {
            guard let other else { return "another transaction" }
            let accountName = other.account?.name
            if let accountName, !accountName.isEmpty {
                return "\(other.payee) (\(accountName))"
            }
            return other.payee
        }()

        let score = String(format: "%.2f", suggestion.score)
        let detail = "Potential match with \(otherLabel) • score \(score) • \(suggestion.daysApart)d apart"

        var events = result.eventsByTransactionID[transactionID] ?? []
        events.append(Event(
            transactionID: transactionID,
            kind: .transferSuggestion,
            title: "Transfer suggested",
            detail: detail
        ))
        result.eventsByTransactionID[transactionID] = Array(events.prefix(config.maxEventsPerTransaction))

        if config.saveDetailedHistory, let transaction = modelContext.model(for: transactionID) as? Transaction {
            TransactionHistoryService.append(
                detail: "Auto processing: transfer suggested",
                to: transaction,
                in: modelContext
            )
        }
    }

    private static func summarizeHistoryLine(events: [Event]) -> String {
        let parts = events.compactMap { event -> String? in
            switch event.kind {
            case .payeeNormalized:
                return "payee cleaned up"
            case .ruleApplied:
                return "rule applied"
            case .categoryChanged:
                return "category updated"
            case .tagsChanged:
                return "tags updated"
            case .memoChanged:
                return "memo updated"
            case .statusChanged:
                return "status updated"
            case .transferSuggestion:
                return "transfer suggested"
            case .invariantFix:
                return "normalized"
            }
        }
        return Array(NSOrderedSet(array: parts)).compactMap { $0 as? String }.joined(separator: ", ")
    }
}
