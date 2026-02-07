import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import UIKit

@MainActor
extension ImportDataViewImpl {
    // MARK: - Logic
    
    private func setImportFailedAndResetToPreview(message: String) {
        errorMessage = message
        currentStep = .preview
        isProcessing = false
        importProgress = nil
    }

    private func saveOrFail(context: String, userMessage: String) -> Bool {
        do {
            try modelContext.save()
            DataChangeTracker.bump()
            return true
        } catch {
            modelContext.rollback()
            SecurityLogger.shared.logSecurityError(error, context: context)
            let nsError = error as NSError
            setImportFailedAndResetToPreview(
                message: "\(userMessage)\n(\(nsError.domain) \(nsError.code))"
            )
            return false
        }
    }

    var encryptedExportPasswordSheet: some View {
        NavigationStack {
            Form {
                Section("Password") {
                    SecureField("Password", text: $encryptedExportPassword)
                        .textContentType(.password)
                }

                if isDecryptingEncryptedExport {
                    Section {
                        HStack(spacing: AppDesign.Theme.Spacing.small) {
                            ProgressView()
                            Text("Decrypting…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Encrypted Export")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if let url = encryptedExportURL {
                            try? FileManager.default.removeItem(at: url)
                        }
                        encryptedExportURL = nil
                        encryptedExportPassword = ""
                        showingEncryptedExportPasswordSheet = false
                    }
                    .disabled(isDecryptingEncryptedExport)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Unlock") {
                        decryptEncryptedExportAndLoadPreview()
                    }
                    .disabled(isDecryptingEncryptedExport || encryptedExportPassword.isEmpty)
                }
            }
        }
        .interactiveDismissDisabled(isDecryptingEncryptedExport)
    }

    func decryptEncryptedExportAndLoadPreview() {
        guard let sourceURL = encryptedExportURL else { return }
        let password = encryptedExportPassword
        guard !password.isEmpty else { return }

        isDecryptingEncryptedExport = true

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let ciphertext = try Data(contentsOf: sourceURL, options: [.mappedIfSafe])
                let plaintext = try EncryptedExportService.decrypt(ciphertext: ciphertext, password: password)

                let tempDir = FileManager.default.temporaryDirectory
                let csvURL = tempDir.appendingPathComponent(UUID().uuidString + ".csv")
                try plaintext.write(to: csvURL, options: [.atomic])
                SensitiveFileProtection.apply(to: csvURL, protection: .completeUnlessOpen)

                try? FileManager.default.removeItem(at: sourceURL)

                DispatchQueue.main.async {
                    self.isDecryptingEncryptedExport = false
                    self.showingEncryptedExportPasswordSheet = false
                    self.encryptedExportPassword = ""
                    self.encryptedExportURL = nil
                    self.selectedFileURL = csvURL
                    self.loadPreview(from: csvURL)
                }
            } catch {
                DispatchQueue.main.async {
                    self.isDecryptingEncryptedExport = false
                    SecurityLogger.shared.logSecurityError(error, context: "ebexport_decrypt")
                    self.errorMessage = "Unable to decrypt that export. Please check your password."
                }
            }
        }
    }
    
    func handleFileSelection(_ result: Result<[URL], Error>) {
        showFileImporter = false
        // Reset state
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = encryptedExportURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFileURL = nil
        encryptedExportURL = nil
        encryptedExportPassword = ""
        showingEncryptedExportPasswordSheet = false

        previewRows = []
        headerRowIndex = 0
        columnMapping = [:]
        importedCount = 0
        
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            
            // Security Scoped Access
            
            // Security Scoped Access
            // Note: If using asCopy: true, the URL might be in our sandbox and startAccessing... returns false.
            // We should attempt to access, but not fail if startAccessing returns false.
            let gotAccess = url.startAccessingSecurityScopedResource()
            // We must keep accessing it while reading. 
            // For the preview reading, we'll stop accessing after reading.
            // For the long import, we'll need to coordinate.
            // PROPER WAY: Copy to temp dir to avoid security scope timeout/issues during long operations.
            
            let tempDir = FileManager.default.temporaryDirectory
            let fileExtension = url.pathExtension.isEmpty ? "csv" : url.pathExtension.lowercased()
            let dstURL = tempDir.appendingPathComponent(UUID().uuidString + "." + fileExtension)
            do {
                // Validate before copying (size, type).
                try SensitiveFileProtection.validateImportableFile(
                    at: url,
                    maxBytes: 50 * 1024 * 1024,
                    allowedExtensions: ["csv", "txt", "tsv", "ebexport", "mmexport"]
                )

                try FileManager.default.copyItem(at: url, to: dstURL)
                if gotAccess { url.stopAccessingSecurityScopedResource() }

                // Ensure sensitive temp files are protected and excluded from backups.
                SensitiveFileProtection.apply(to: dstURL, protection: .completeUnlessOpen)

                if fileExtension == "ebexport" || fileExtension == "mmexport" {
                    self.encryptedExportURL = dstURL
                    self.showingEncryptedExportPasswordSheet = true
                } else {
                    self.selectedFileURL = dstURL
                    loadPreview(from: dstURL)
                }
            } catch {
                if gotAccess { url.stopAccessingSecurityScopedResource() }
                // Clean up temp file on failure
                try? FileManager.default.removeItem(at: dstURL)
                if (error as? SensitiveFileProtection.ValidationError) != nil {
                    errorMessage = error.localizedDescription
                } else {
                    SecurityLogger.shared.logFileOperationError(operation: "copy", path: dstURL.path)
                    errorMessage = "Unable to access the selected file. Please try again."
                }
            }

        case .failure:
            errorMessage = "Unable to select file. Please try again."
        }
    }

    func loadPreview(from url: URL) {
        isProcessing = true
        Task {
            do {
                // Use RobustCSVParser to read first N rows
                var rows: [[String]] = []
                var count = 0
                for try await row in RobustCSVParser.parse(url: url) {
                    rows.append(row)
                    count += 1
                    if count >= ImportConstants.previewRowLimit { break }
                }
                
                await MainActor.run {
                    self.previewRows = rows
                    self.hasLoadedPreview = true
                    self.currentStep = .selectHeader
                    self.detectHeaderRow()
                    self.isProcessing = false
                }
            } catch {
                await MainActor.run {
                    SecurityLogger.shared.logSecurityError(error, context: "csv_preview")
                    self.errorMessage = (error as NSError).localizedDescription
                    self.isProcessing = false
                }
            }
        }
    }
    
    func detectHeaderRow() {
        // Look for keywords in first 10 rows
        let keywords = ["date", "amount", "payee", "description", "memo", "category"]

        for (index, row) in previewRows.prefix(10).enumerated() {
            let hitCount = row.filter { cell in
                let lower = cell.lowercased()
                return keywords.contains { lower.contains($0) }
            }.count

            // If we found at least 2 keywords, assume this is header
            if hitCount >= 2 {
                headerRowIndex = index
                detectImportSource()
                return
            }
        }
    }

    func detectImportSource() {
        guard !previewRows.isEmpty && previewRows.indices.contains(headerRowIndex) else { return }
        let headers = previewRows[headerRowIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }

        // YNAB - has specific headers
        if headers.contains("outflow") && headers.contains("inflow") && headers.contains("cleared") {
            selectedImportSource = .ynab
            return
        }

        // Mint - has "original description" and "transaction type"
        if headers.contains("original description") || (headers.contains("transaction type") && headers.contains("labels")) {
            selectedImportSource = .mint
            return
        }

        // Monarch - has "merchant" column
        if headers.contains("merchant") && headers.contains("original statement") {
            selectedImportSource = .monarch
            return
        }

        // Chase - has "posting date" or "transaction date"
        if (headers.contains("posting date") || headers.contains("transaction date")) && headers.contains("type") {
            selectedImportSource = .chase
            return
        }

        // Bank of America - has "posted date" and "reference number"
        if headers.contains("posted date") && headers.contains("reference number") {
            selectedImportSource = .bankOfAmerica
            return
        }

        // Citibank - has "debit" and "credit" and "status"
        if headers.contains("debit") && headers.contains("credit") && headers.contains("status") {
            selectedImportSource = .citi
            return
        }

        // Capital One - has "card no." or specific debit/credit format
        if headers.contains("card no.") || (headers.contains("debit") && headers.contains("credit") && headers.contains("category")) {
            selectedImportSource = .capitalOne
            return
        }

        // Discover - has "trans. date" and "post date"
        if headers.contains("trans. date") && headers.contains("post date") {
            selectedImportSource = .discover
            return
        }

        // American Express - has "extended details" or "appears on your statement as"
        if headers.contains("extended details") || headers.contains("appears on your statement as") {
            selectedImportSource = .amex
            return
        }

        // PayPal - has very specific headers
        if headers.contains("from email address") || headers.contains("to email address") || headers.contains("transaction id") {
            selectedImportSource = .paypal
            return
        }

        // Venmo - has "funding source" and "destination"
        if headers.contains("funding source") && headers.contains("destination") {
            selectedImportSource = .venmo
            return
        }

        // Cash App - has "asset type" or "asset price"
        if headers.contains("asset type") || headers.contains("asset price") {
            selectedImportSource = .cashApp
            return
        }

        // RBC - has "cad$" or "usd$" columns
        if headers.contains("cad$") || headers.contains("usd$") || (headers.contains("account type") && headers.contains("cheque number")) {
            selectedImportSource = .rbc
            return
        }

        // TD - has specific "debit", "credit" and "balance" combination
        if headers.contains("debit") && headers.contains("credit") && headers.contains("balance") && !headers.contains("status") {
            selectedImportSource = .td
            return
        }

        // Scotiabank - has "transaction code" or "institution"
        if headers.contains("transaction code") || (headers.contains("institution") && headers.contains("account number")) {
            selectedImportSource = .scotiabank
            return
        }

        // BMO - has "first bank card" or "date posted"
        if headers.contains("first bank card") || (headers.contains("date posted") && headers.contains("transaction type")) {
            selectedImportSource = .bmo
            return
        }

        // CIBC - has "withdrawals" and "deposits"
        if headers.contains("withdrawals") && headers.contains("deposits") {
            selectedImportSource = .cibc
            return
        }

        // National Bank - similar to TD but may have different patterns
        // Will rely on manual selection for now

        // Tangerine - has "transaction" and "name" columns
        if headers.contains("transaction") && headers.contains("name") && headers.contains("memo") {
            selectedImportSource = .tangerine
            return
        }

        // Simplii - has "funds out" and "funds in"
        if headers.contains("funds out") && headers.contains("funds in") {
            selectedImportSource = .simplii
            return
        }

        // Wealthsimple - has "amount (cad)" or "amount (usd)" or "reference #"
        if headers.contains("amount (cad)") || headers.contains("amount (usd)") || headers.contains("reference #") {
            selectedImportSource = .wealthsimple
            return
        }

        // Wells Fargo - harder to detect, leave as custom
        // Default to custom if no match
        selectedImportSource = .custom
    }

    func autoMapColumns() {
        guard !previewRows.isEmpty && previewRows.indices.contains(headerRowIndex) else { return }
        
        // Reset
        columnMapping = [:]
        
        let headers = previewRows[headerRowIndex].map { $0.lowercased().trimmingCharacters(in: .whitespaces) }
        
        // Helper to find index (only on currently-unmapped columns)
        func findIndex(containing key: String) -> Int? {
            headers.enumerated().first { columnMapping[$0.offset] == nil && $0.element.contains(key) }?.offset
        }
        
        // Helper to find exact match (only on currently-unmapped columns)
        func findExact(_ key: String) -> Int? {
            headers.enumerated().first { columnMapping[$0.offset] == nil && $0.element == key }?.offset
        }
        
        switch selectedImportSource {
        case .ynab:
            // YNAB Headers: Account, Flag, Date, Payee, Category Group/Category, Category Group, Category, Memo, Outflow, Inflow, Cleared
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("payee") { columnMapping[idx] = "Payee" }
            if let idx = findExact("memo") { columnMapping[idx] = "Memo" }
            if let idx = findExact("inflow") { columnMapping[idx] = ColumnType.inflow.rawValue }
            if let idx = findExact("outflow") { columnMapping[idx] = ColumnType.outflow.rawValue }
            
            // YNAB often uses MM/dd/yyyy. Let's try to set hint if not set.
            if selectedDateFormat == nil {
                // Try to find one
                // selectedDateFormat = .mmddyyyy
            }
            
        case .mint:
            // Mint: Date, Description, Original Description, Amount, Transaction Type, Category, Account Name, Labels, Notes
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" } // Signed amount usually
            if let idx = findExact("notes") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" } 
            if let idx = findExact("account name") { columnMapping[idx] = "Account" }
            if let idx = findExact("labels") { columnMapping[idx] = "Tags" }
            
        case .monarch:
            // Monarch: Date, Merchant, Category, Account, Original Statement, Notes, Amount
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("merchant") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("notes") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }
            if let idx = findExact("account") { columnMapping[idx] = "Account" }
            if let idx = findExact("tags") { columnMapping[idx] = "Tags" }

        case .chase:
            // Chase: Transaction Date, Post Date, Description, Category, Type, Amount, Memo
            if let idx = findExact("transaction date") ?? findExact("posting date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("memo") ?? findExact("details") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") ?? findExact("type") { columnMapping[idx] = "Category" }

        case .bankOfAmerica:
            // BofA: Posted Date, Reference Number, Payee, Address, Amount
            if let idx = findExact("posted date") ?? findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("payee") ?? findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }

        case .wellsFargo:
            // Wells Fargo: Date, Amount, *, *, Name, Memo
            if let idx = findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("name") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("memo") { columnMapping[idx] = "Memo" }

        case .citi:
            // Citi: Status, Date, Description, Debit, Credit
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .capitalOne:
            // Capital One: Transaction Date, Posted Date, Card No., Description, Category, Debit, Credit
            if let idx = findExact("transaction date") ?? findExact("posted date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .discover:
            // Discover: Trans. Date, Post Date, Description, Amount, Category
            if let idx = findExact("trans. date") ?? findExact("post date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }

        case .amex:
            // Amex: Date, Description, Amount, Extended Details, Appears On Your Statement As, Address, City/State, Zip Code, Country, Reference, Category
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("extended details") { columnMapping[idx] = "Memo" }
            if let idx = findExact("category") { columnMapping[idx] = "Category" }

        case .paypal:
            // PayPal: Date, Time, Time Zone, Name, Type, Status, Currency, Gross, Fee, Net, From Email Address, To Email Address, Transaction ID, Item Title, Item ID, Reference Txn ID, Receipt ID, Balance
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("name") { columnMapping[idx] = "Payee" }
            if let idx = findExact("net") ?? findExact("gross") { columnMapping[idx] = "Amount" }
            if let idx = findExact("item title") ?? findExact("type") { columnMapping[idx] = "Memo" }

        case .venmo:
            // Venmo: ID, Datetime, Type, Status, Note, From, To, Amount (total), Amount (fee), Funding Source, Destination
            if let idx = findExact("datetime") ?? findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("from") ?? findExact("to") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount (total)") ?? findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("note") { columnMapping[idx] = "Memo" }

        case .cashApp:
            // Cash App: Transaction ID, Date, Transaction Type, Currency, Amount, Fee, Net Amount, Asset Type, Asset Price, Asset Amount, Status, Notes, Name, Account
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("name") { columnMapping[idx] = "Payee" }
            if let idx = findExact("net amount") ?? findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("notes") { columnMapping[idx] = "Memo" }
            if let idx = findExact("transaction type") { columnMapping[idx] = "Category" }

        case .rbc:
            // RBC: Account Type, Account Number, Transaction Date, Cheque Number, Description 1, Description 2, CAD$, USD$
            if let idx = findExact("transaction date") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description 1") ?? findExact("description 2") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("cad$") ?? findExact("usd$") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }

        case .td:
            // TD: Date, Description, Debit, Credit, Balance
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .scotiabank:
            // Scotiabank: Transaction Date, Institution, Account Number, Transaction Code, Transaction Description, Cheque Number, Transaction Amount
            if let idx = findExact("transaction date") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("transaction description") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("transaction amount") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }

        case .bmo:
            // BMO: First Bank Card, Transaction Type, Date Posted, Transaction Amount, Description
            if let idx = findExact("date posted") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("transaction amount") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("transaction type") { columnMapping[idx] = "Memo" }

        case .cibc:
            // CIBC: Date, Description, Withdrawals, Deposits
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("withdrawals") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("deposits") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .nationalBank:
            // National Bank: Date, Description, Debit, Credit, Balance
            if let idx = findExact("date") ?? findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") ?? findIndex(containing: "description") { columnMapping[idx] = "Payee" }
            if let idx = findExact("debit") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("credit") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .tangerine:
            // Tangerine: Date, Transaction, Name, Memo, Amount
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("name") ?? findExact("transaction") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("memo") { columnMapping[idx] = "Memo" }

        case .simplii:
            // Simplii: Date, Transaction, Description, Funds Out, Funds In
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") ?? findExact("transaction") { columnMapping[idx] = "Payee" }
            if let idx = findExact("funds out") { columnMapping[idx] = ColumnType.outflow.rawValue }
            if let idx = findExact("funds in") { columnMapping[idx] = ColumnType.inflow.rawValue }

        case .wealthsimple:
            // Wealthsimple: Date, Account, Type, Description, Reference #, Amount (CAD), Amount (USD)
            if let idx = findExact("date") { columnMapping[idx] = "Date" }
            if let idx = findExact("description") ?? findExact("type") { columnMapping[idx] = "Payee" }
            if let idx = findExact("amount (cad)") ?? findExact("amount (usd)") ?? findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findExact("reference #") { columnMapping[idx] = "Memo" }
            if let idx = findExact("account") { columnMapping[idx] = "Account" }

        case .custom:
            // Generic heuristic from before
            if let idx = findIndex(containing: "date") { columnMapping[idx] = "Date" }
            if let idx = findIndex(containing: "payee") ?? findIndex(containing: "description") ?? findIndex(containing: "name") {
                columnMapping[idx] = "Payee"
            }
            if let idx = findIndex(containing: "amount") { columnMapping[idx] = "Amount" }
            if let idx = findIndex(containing: "memo") ?? findIndex(containing: "note") { columnMapping[idx] = "Memo" }
            if let idx = findIndex(containing: "category") { columnMapping[idx] = "Category" }
            if let idx = findExact("account") ?? findExact("account name") ?? findIndex(containing: "account") ?? findIndex(containing: "acct") {
                columnMapping[idx] = "Account"
            }
            if let idx = findIndex(containing: "tag") ?? findIndex(containing: "label") { columnMapping[idx] = "Tags" }
            // Mapping Inflow/Outflow if detected (Generic)
            if let idx = findIndex(containing: "inflow") { columnMapping[idx] = ColumnType.inflow.rawValue }
            if let idx = findIndex(containing: "outflow") { columnMapping[idx] = ColumnType.outflow.rawValue }

            // Escape Budget extended columns (transfers, etc)
            if let idx = findExact("kind") ?? findIndex(containing: "kind") {
                columnMapping[idx] = ColumnType.kind.rawValue
            }
            if let idx = findExact("transfer id") ?? findExact("transferid") ?? findIndex(containing: "transfer id") ?? findIndex(containing: "transferid") {
                columnMapping[idx] = ColumnType.transferID.rawValue
            }
            if let idx = findExact("external transfer label") ?? findIndex(containing: "external transfer") {
                columnMapping[idx] = ColumnType.externalTransferLabel.rawValue
            }
            if let idx = findExact("transfer inbox dismissed") ?? findIndex(containing: "dismiss") {
                columnMapping[idx] = ColumnType.transferInboxDismissed.rawValue
            }
            if let idx = findExact("purchase items") ??
                findExact("purchased items") ??
                findExact("line items") ??
                findIndex(containing: "purchase items") ??
                findIndex(containing: "purchased items") ??
                findIndex(containing: "line items") {
                columnMapping[idx] = ColumnType.purchaseItems.rawValue
            }
        }

        // Cross-template fallbacks (don’t override existing mappings)
        if !columnMapping.values.contains("Payee") {
            if let idx = findExact("description") ?? findIndex(containing: "description") {
                columnMapping[idx] = "Payee"
            }
        }

        if !columnMapping.values.contains("Account") {
            if let idx = findExact("account") ??
                findExact("account name") ??
                findIndex(containing: "account name") ??
                findIndex(containing: "account") ??
                findIndex(containing: "acct") {
                columnMapping[idx] = "Account"
            }
        }
    }

    func requestImportConfirmation() {
        guard defaultAccount != nil else {
            errorMessage = "Please select a default account for this import."
            return
        }
        guard let signConvention else {
            errorMessage = "Please choose how positive and negative amounts should be interpreted before importing."
            return
        }
        startImport(signConvention: signConvention)
    }

    func attachPurchasedItems(from json: String?, to transaction: Transaction) {
        let decoded = PurchasedItemsCSVCodec.decode(json)
        guard !decoded.isEmpty else { return }

        for (index, payload) in decoded.prefix(TransactionTextLimits.maxPurchasedItemsPerTransaction).enumerated() {
            let name = TransactionTextLimits.normalizedPurchasedItemName(payload.name)
            let price = Decimal(string: payload.price) ?? 0
            let note = TransactionTextLimits.normalizedPurchasedItemNote(payload.note)
            let item = PurchasedItem(
                name: name,
                price: price,
                note: note,
                order: index,
                transaction: transaction,
                isDemoData: transaction.isDemoData
            )
            modelContext.insert(item)
        }
    }

    func beginImport(signConvention: AmountSignConvention) {
        self.signConvention = signConvention
        startImport(signConvention: signConvention)
    }

	func startImport(signConvention: AmountSignConvention) {
        guard let url = selectedFileURL else { return }

        if !hasConfiguredImportOptionsThisRun {
            importOptions = ImportProcessingOptions(
                normalizePayee: normalizePayeeOnImport,
                applyAutoRules: applyAutoRulesOnImport,
                detectDuplicates: detectDuplicatesOnImport,
                suggestTransfers: suggestTransfersOnImport,
                saveProcessingHistory: saveProcessingHistory
            )
        }
        
        currentStep = .importing
        importedCount = 0
        isProcessing = true
        importProgress = ImportProgressState(
            title: "Importing",
            phase: .parsing,
            message: "Parsing CSV…",
            current: 0,
            total: nil,
            canCancel: true
        )
        
        let headers = previewRows[headerRowIndex]
        let mapping = columnMapping
        let hIndex = headerRowIndex
        
        
        let dateFormat = selectedDateFormat
        let sign = signConvention
        
        // Use detached task to avoid running on MainActor (which causes UI freeze and 'no async' warning)
        importTask = Task.detached(priority: .userInitiated) {
            do {
                var localBatch: [ImportedTransaction] = []
                var rowsAfterHeader = 0
                var rowsSkipped = 0
                var skipSamples: [(rowNumber: Int, dateValue: String?, amountValue: String?, reason: String)] = []

                // Stream full file
                var rowIndex = -1
                var parsedCount = 0
                let maxRows = 1_000_000 // 1 million row limit to prevent memory exhaustion
                for try await row in RobustCSVParser.parse(url: url) {
                    if Task.isCancelled { throw CancellationError() }
                    rowIndex += 1
                    // Skip rows before data
                    if rowIndex <= hIndex { continue }
                    rowsAfterHeader += 1
                    let oneBasedRowNumber = rowIndex + 1

                    // Protect against unbounded row count
                    if parsedCount >= maxRows {
                        throw NSError(domain: "Import", code: 3, userInfo: [NSLocalizedDescriptionKey: "File exceeds maximum of \(maxRows) rows"])
                    }

                    if let data = Self.extractTransactionData(
                        from: row,
                        headers: headers,
                        columnMapping: mapping,
                        dateFormatOption: dateFormat,
                        signConvention: sign,
                        rowNumber: oneBasedRowNumber,
                        rowsSkipped: &rowsSkipped,
                        skipSamples: &skipSamples
                    ) {
                         localBatch.append(data)
                         parsedCount += 1
                         if parsedCount % 50 == 0 {
                             let count = parsedCount
                             await MainActor.run {
                                 self.importProgress?.phase = .parsing
                                 self.importProgress?.current = count
                                 self.importProgress?.message = "Parsing CSV…"
                                 self.importedCount = count
                             }
                         }
                    } else {
                        // Diagnostics already recorded when a row can't be parsed.
                    }
                }
                
                // Done parsing, now check duplicates on MainActor (requires modelContext access usually, or we fetch first)
						await MainActor.run { [localBatch, rowsAfterHeader, skipSamples] in
                            if localBatch.isEmpty, rowsAfterHeader > 0 {
                                var message = "No transactions could be parsed from this CSV.\nCheck your column mapping and date format selection."
                                if !skipSamples.isEmpty {
                                    let examples = skipSamples.map { sample in
                                        var parts: [String] = ["Row \(sample.rowNumber): \(sample.reason)"]
                                        if let date = sample.dateValue, !date.isEmpty { parts.append("date=\"\(date)\"") }
                                        if let amount = sample.amountValue, !amount.isEmpty { parts.append("amount=\"\(amount)\"") }
                                        return parts.joined(separator: " ")
                                    }
                                    message += "\n\nExamples:\n" + examples.joined(separator: "\n")
                                }

                                self.errorMessage = message
                                self.currentStep = .preview
                                self.isProcessing = false
                                self.importProgress = nil
                                return
                            }

							if self.importOptions.normalizePayee {
								self.stagedTransactions = localBatch.map { tx in
									var updated = tx
									let raw = tx.rawPayee ?? tx.payee
									updated.payee = PayeeNormalizer.normalizeDisplay(raw)
									return updated
								}
							} else {
								self.stagedTransactions = localBatch
		                        }
						self.importProgress?.phase = .preparing
						self.importProgress?.current = localBatch.count
						self.importProgress?.message = "Preparing account/category/tag mapping…"
						self.prepareAccountMappingOrContinue()
						self.isProcessing = false
						self.importProgress = nil
					}
                
                // Clean up file
                try? FileManager.default.removeItem(at: url)
                
            } catch is CancellationError {
                // Clean up temp file on cancellation
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.isProcessing = false
                    self.importProgress = nil
                }
            } catch {
                // Clean up temp file on error
                try? FileManager.default.removeItem(at: url)
                await MainActor.run {
                    self.errorMessage = (error as NSError).localizedDescription
                    self.currentStep = .preview
                    self.isProcessing = false
                    self.importProgress = nil
                }
            }
        }
    }

	    func prepareAccountMappingOrContinue() {
	        let allRaw = Set(
	            stagedTransactions
	                .compactMap { $0.rawAccount?.trimmingCharacters(in: .whitespacesAndNewlines) }
	                .filter { !$0.isEmpty }
	        )
	        let sorted = allRaw.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

	        guard !sorted.isEmpty else {
	            prepareCategoryMapping()
	            return
	        }

	        importedAccounts = sorted
	        currentStep = .mapAccounts

	        // Auto-map when the imported name matches an existing account name.
	        for raw in sorted {
	            if let match = accounts.first(where: { $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
	                accountMapping[raw] = match
	            }
	        }
	    }

	    func prepareCategoryMapping() {
	        let allRaw = Set(stagedTransactions.compactMap { $0.rawCategory })
	        let sorted = allRaw.sorted()

	        guard !sorted.isEmpty else {
	            // No categories to map, proceed to tags (or review)
	            prepareTagMappingOrReview()
	            return
	        }

	        importedCategories = sorted
	        currentStep = .mapCategories

	        // Fetch existing data for UI
	        allCategories = (try? modelContext.fetch(FetchDescriptor<Category>(sortBy: [SortDescriptor(\.name)]))) ?? []
	        allGroups = (try? modelContext.fetch(FetchDescriptor<CategoryGroup>(sortBy: [SortDescriptor(\.order)]))) ?? []

	        // Auto-map if names match exactly
	        for raw in sorted {
	            if let match = allCategories.first(where: { $0.name.lowercased() == raw.lowercased() }) {
	                categoryMapping[raw] = match
	            }
	        }
	    }

	    func prepareTagMappingOrReview() {
	        let allRaw = Set(stagedTransactions.flatMap { $0.rawTags })
	        let sorted = allRaw.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

		        guard !sorted.isEmpty else {
		            checkForDuplicates()
	                if importOptions.suggestTransfers {
	                    refreshTransferSuggestions()
	                } else {
	                    transferSuggestions = []
	                    selectedTransferSuggestionIDs = []
	                }
		            currentStep = .review
		            return
		        }

        importedTags = sorted
        currentStep = .mapTags

        allTransactionTags = (try? modelContext.fetch(FetchDescriptor<TransactionTag>(sortBy: [SortDescriptor(\.name)]))) ?? []

        for raw in sorted {
            if let match = allTransactionTags.first(where: { $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
                tagMapping[raw] = match
            }
        }
    }

    func checkForDuplicates() {
        guard !stagedTransactions.isEmpty else { return }
        guard importOptions.detectDuplicates else {
            stagedTransactions = stagedTransactions.map { tx in
                var updated = tx
                updated.isDuplicate = false
                updated.isSelected = true
                updated.duplicateReason = nil
                return updated
            }
            return
        }
        
        // Find date range
        let dates = stagedTransactions.map { $0.date }
        guard let minDate = dates.min(), let maxDate = dates.max() else { return }
        
        // Fetch existing
        let descriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { t in
                t.date >= minDate && t.date <= maxDate
            }
        )
        
        guard let existing = try? modelContext.fetch(descriptor) else { return }

        // Mark duplicates with improved matching logic
        var newStaged: [ImportedTransaction] = []
        let config = TransactionDeduper.Config(useNormalizedPayee: importOptions.normalizePayee, similarityThreshold: 0.85)

        for var tx in stagedTransactions {
            var matchReason: String?
            let isDup = existing.contains { ex in
                let result = TransactionDeduper.evaluate(imported: tx, existing: ex, config: config)
                if result.isDuplicate {
                    matchReason = result.reason
                    return true
                }
                return false
            }

            if isDup {
                tx.isDuplicate = true
                tx.isSelected = false // Default unchecked for duplicates
                tx.duplicateReason = matchReason
            } else {
                tx.isDuplicate = false
                tx.isSelected = true
                tx.duplicateReason = nil
            }
            newStaged.append(tx)
        }

        self.stagedTransactions = newStaged
    }

    func accountNameForImported(_ transaction: ImportedTransaction) -> String {
        resolveAccount(for: transaction)?.name ?? defaultAccount?.name ?? "Default"
    }

    func refreshTransferSuggestions() {
        transferSuggestionCount = stagedTransactions.compactMap(\.transferID).count / 2
        let previousSelection = selectedTransferSuggestionIDs

        let config = ImportTransferSuggester.Config(maxDaysApart: 3, maxSuggestions: 60, minScore: 0.70)
        transferSuggestions = ImportTransferSuggester.suggest(
            transactions: stagedTransactions,
            config: config,
            eligible: { tx in
                tx.isSelected &&
                !tx.isDuplicate &&
                tx.kind == .standard &&
                tx.transferID == nil &&
                tx.amount != 0 &&
                resolveAccount(for: tx) != nil
            },
            accountIDFor: { tx in
                resolveAccount(for: tx)?.persistentModelID
            },
            transferishHintFor: { tx in
                if let raw = tx.rawCategory, let mapped = categoryMapping[raw], mapped.group?.type == .transfer {
                    return true
                }
                return tx.rawCategory == nil
            }
        )

        // Safety: never auto-select transfer suggestions.
        // Keep only selections that still exist after refresh.
        let validIDs = Set(transferSuggestions.map(\.id))
        selectedTransferSuggestionIDs = previousSelection.intersection(validIDs)
    }

    func linkSelectedTransferSuggestions() {
        var linkedPairs = 0

        let suggestionsToLink = transferSuggestions.filter { selectedTransferSuggestionIDs.contains($0.id) }
        guard !suggestionsToLink.isEmpty else { return }

        for suggestion in suggestionsToLink {
            guard let outflowIndex = stagedTransactions.firstIndex(where: { $0.id == suggestion.outflowID }) else { continue }
            guard let inflowIndex = stagedTransactions.firstIndex(where: { $0.id == suggestion.inflowID }) else { continue }

            guard stagedTransactions[outflowIndex].transferID == nil,
                  stagedTransactions[inflowIndex].transferID == nil else { continue }
            guard stagedTransactions[outflowIndex].kind == .standard,
                  stagedTransactions[inflowIndex].kind == .standard else { continue }

            let id = UUID()
            stagedTransactions[outflowIndex].kind = .transfer
            stagedTransactions[outflowIndex].transferID = id
            stagedTransactions[outflowIndex].isSelected = true

            stagedTransactions[inflowIndex].kind = .transfer
            stagedTransactions[inflowIndex].transferID = id
            stagedTransactions[inflowIndex].isSelected = true

            linkedPairs += 1
        }

        transferSuggestionCount += linkedPairs
        refreshTransferSuggestions()
    }

    func unlinkTransfer(id: UUID) {
        for index in stagedTransactions.indices {
            if stagedTransactions[index].transferID == id {
                stagedTransactions[index].kind = .standard
                stagedTransactions[index].transferID = nil
            }
        }
        refreshTransferSuggestions()
    }
    
    func performFinalImport() {
        let toImport = stagedTransactions.filter { $0.isSelected }
        guard let fallbackAccount = defaultAccount else {
            errorMessage = "Please select a default account for this import."
            currentStep = .preview
            return
        }

        isProcessing = true
        importProgress = ImportProgressState(
            title: "Importing",
            phase: .saving,
            message: "Saving transactions…",
            current: 0,
            total: toImport.count,
            canCancel: true
        )

		    importTask?.cancel()
		    importTask = Task { @MainActor in
                TransactionStatsUpdateCoordinator.beginDeferringUpdates()
                TransactionStatsUpdateCoordinator.markNeedsFullRebuild()
                defer {
                    TransactionStatsUpdateCoordinator.endDeferringUpdates()
                    DataChangeTracker.bump()
                }

		            var tagCache: [String: TransactionTag] = Dictionary(uniqueKeysWithValues: allTransactionTags.map { ($0.name.lowercased(), $0) })

	                var importedTransactions: [Transaction] = []
	                importedTransactions.reserveCapacity(toImport.count)
                var originalPayeeByTransactionID: [PersistentIdentifier: String] = [:]
                originalPayeeByTransactionID.reserveCapacity(min(2048, toImport.count))

            // Capture summary details for the notification.
            let fileName = selectedFileURL?.lastPathComponent ?? "CSV"
            let totalFound = stagedTransactions.count
            let duplicatesFound = stagedTransactions.filter { $0.isDuplicate }.count
            let duplicatesImported = toImport.filter { $0.isDuplicate }.count
            let transferPairsLinked = Set(toImport.filter { $0.kind == .transfer }.compactMap(\.transferID)).count
            let accountsUsedCount: Int = {
                var ids = Set<PersistentIdentifier>()
                ids.reserveCapacity(4)
                for tx in toImport {
                    let account = resolveAccount(for: tx) ?? fallbackAccount
                    ids.insert(account.persistentModelID)
                }
                return ids.count
            }()

            for (index, txData) in toImport.enumerated() {
                if Task.isCancelled { break }

                var finalCategory: Category? = nil
                if let raw = txData.rawCategory, let mapped = categoryMapping[raw] {
                    // Ensure category has a group - if not, assign to default Expenses group
                    if mapped.group == nil {
                        let expensesGroup = getOrCreateDefaultExpensesGroup()
                        mapped.group = expensesGroup
                    }
                    finalCategory = mapped.group?.type == .transfer ? nil : mapped
                }

                let account = resolveAccount(for: txData) ?? fallbackAccount
                let resolvedTags = resolveImportedTags(txData.rawTags, cache: &tagCache)

	                // Store original payee for rule matching during processing
	                let originalPayee = txData.rawPayee ?? txData.payee
		                let newTx = Transaction(
		                    date: txData.date,
		                    payee: txData.payee,
		                    amount: txData.amount,
		                    memo: TransactionTextLimits.normalizedMemo(txData.memo),
		                    status: txData.status,
		                    kind: txData.kind,
		                    transferID: txData.transferID,
		                    account: account,
		                    category: finalCategory,
		                    tags: resolvedTags.isEmpty ? nil : resolvedTags
			                )
                        newTx.transferInboxDismissed = txData.transferInboxDismissed
                        newTx.externalTransferLabel = txData.externalTransferLabel
				                modelContext.insert(newTx)
                        attachPurchasedItems(from: txData.purchaseItemsJSON, to: newTx)
				                account.balance += newTx.amount
                    importedTransactions.append(newTx)
                    originalPayeeByTransactionID[newTx.persistentModelID] = originalPayee

                // Imported transfer links (suggestions or explicit mapping) always clear category.
                // Never auto-convert to an internal transfer during import unless the user explicitly linked a pair.
                // Also avoid persisting "Transfer" group categories (they get normalized into transfers later).
                if newTx.category?.group?.type == .transfer {
                    newTx.category = nil
                }
                if newTx.kind == .transfer {
                    newTx.category = nil
                }

	                let current = index + 1
	                if current % ImportConstants.progressUpdateInterval == 0 || current == toImport.count {
	                    importProgress?.current = current
	                    importProgress?.message = "Saving transactions…"
	                    await Task.yield()
	                }

                if current % ImportConstants.batchSaveInterval == 0 {
                    guard saveOrFail(
                        context: "ImportDataView.performFinalImport.batchSave",
                        userMessage: "Import failed while saving transactions. Please try again."
                    ) else {
                        return
                    }
                    await Task.yield()
                }
            }

	            guard !Task.isCancelled else {
	                isProcessing = false
	                importProgress = nil
	                return
	            }

	            guard saveOrFail(
                    context: "ImportDataView.performFinalImport.finalSave",
                    userMessage: "Import failed while saving transactions. Please try again."
                ) else {
	                return
	            }

                importProgress?.phase = .processing
                importProgress?.message = "Applying rules and cleaning up…"
                importProgress?.current = 0
                importProgress?.total = importedTransactions.count
                await Task.yield()

	                let processingResult = TransactionProcessor.process(
	                    transactions: importedTransactions,
	                    in: modelContext,
	                    source: .import,
	                    originalPayeeByTransactionID: originalPayeeByTransactionID,
                        configOverride: TransactionProcessor.Config(
                            normalizePayee: importOptions.normalizePayee,
                            applyAutoRules: importOptions.applyAutoRules,
                            suggestTransfers: importOptions.suggestTransfers,
                            saveDetailedHistory: importOptions.saveProcessingHistory,
                            maxDetailedTransactions: 250,
                            maxEventsPerTransaction: 8
                        )
	                )

                guard saveOrFail(
                    context: "ImportDataView.performFinalImport.processingSave",
                    userMessage: "Import failed while processing transactions. Please try again."
                ) else {
                    return
                }

	                importProcessingResult = processingResult
                    SavingsGoalEnvelopeSyncService.syncCurrentBalances(
                        modelContext: modelContext,
                        referenceDate: Date(),
                        saveContext: "ImportDataView.performFinalImport.syncSavingsGoals"
                    )

                    StatsSanityChecker.checkRecentMonths(in: modelContext, monthsBack: 3, isDemoData: false)

		            // Add a notification for the import result.
			            let summaryParts: [String] = [
			                "Imported \(toImport.count) of \(totalFound)",
		                accountsUsedCount > 1 ? "Accounts: \(accountsUsedCount)" : nil,
		                (importOptions.applyAutoRules && processingResult.summary.transactionsWithRulesApplied > 0) ? "Auto Rules: \(processingResult.summary.transactionsWithRulesApplied)" : nil,
	                    (importOptions.normalizePayee && processingResult.summary.payeesNormalizedCount > 0) ? "Payees: \(processingResult.summary.payeesNormalizedCount) cleaned" : nil,
		                importOptions.suggestTransfers && transferPairsLinked > 0 ? "Transfers: \(transferPairsLinked) pair\(transferPairsLinked == 1 ? "" : "s")" : nil,
	                    (importOptions.suggestTransfers && processingResult.summary.transferSuggestionsInvolvingProcessed > 0) ? "Transfer suggestions: \(processingResult.summary.transferSuggestionsInvolvingProcessed)" : nil,
		                importOptions.detectDuplicates && duplicatesFound > 0 ? "Duplicates: \(duplicatesFound) (imported \(duplicatesImported))" : nil
		            ].compactMap { $0 }

            let note = AppNotification(
                title: "Import Complete",
                message: "\(fileName) • \(summaryParts.joined(separator: " • "))",
                date: Date(),
                type: .success,
                isRead: false,
                isDemoData: fallbackAccount.isDemoData
            )
            InAppNotificationService.post(
                note,
                in: modelContext,
                topic: .importComplete
            )
            await MainActor.run {
                BadgeService.shared.recordImportCompleted(modelContext: modelContext)
            }

            // Log successful import
            SecurityLogger.shared.logDataImport(rowCount: toImport.count, source: selectedImportSource.rawValue)

            importedCount = toImport.count
            importedFileName = fileName
            currentStep = .complete
            isProcessing = false
            importProgress = nil

            cleanupImportedTempFiles()
        }
    }

    func cleanupImportedTempFiles() {
        if let url = selectedFileURL {
            try? FileManager.default.removeItem(at: url)
        }
        if let url = encryptedExportURL {
            try? FileManager.default.removeItem(at: url)
        }
        selectedFileURL = nil
        encryptedExportURL = nil
        encryptedExportPassword = ""
        showingEncryptedExportPasswordSheet = false
    }

    func resolveImportedTags(_ rawTags: [String], cache: inout [String: TransactionTag]) -> [TransactionTag] {
        var result: [TransactionTag] = []

        for raw in rawTags {
            if ignoredImportedTags.contains(raw) { continue }

            if let mapped = tagMapping[raw] {
                if !result.contains(where: { $0.persistentModelID == mapped.persistentModelID }) {
                    result.append(mapped)
                }
                continue
            }

            let key = raw.lowercased()
            if let existing = cache[key] {
                if !result.contains(where: { $0.persistentModelID == existing.persistentModelID }) {
                    result.append(existing)
                }
                continue
            }

            let nextOrder = (allTransactionTags.map(\.order).max() ?? -1) + 1
            let created = TransactionTag(name: raw, colorHex: TagColorPalette.defaultHex(for: appColorMode), order: nextOrder)
            modelContext.insert(created)
            cache[key] = created
            allTransactionTags.append(created)
            result.append(created)
        }

        return result
    }
    func resolveAccount(for tx: ImportedTransaction) -> Account? {
        guard let raw = tx.rawAccount?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if let mapped = accountMapping[raw] {
            return mapped
        }
        return accounts.first { $0.name.compare(raw, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }
    }

    func getOrCreateDefaultExpensesGroup() -> CategoryGroup {
        // Try to find an existing Expenses group
        let expenseType = CategoryGroupType.expense.rawValue
        let descriptor = FetchDescriptor<CategoryGroup>(predicate: #Predicate { $0.typeRawValue == expenseType })

        if let existingExpenseGroups = try? modelContext.fetch(descriptor),
           let firstExpenseGroup = existingExpenseGroups.first {
            return firstExpenseGroup
        }

        // No expense groups exist - create a default one
        let maxOrder = allGroups.map { $0.order }.max() ?? -1
        let newGroup = CategoryGroup(name: "Expenses", order: maxOrder + 1, type: .expense)
        modelContext.insert(newGroup)
        allGroups.append(newGroup)
        _ = modelContext.safeSave(context: "ImportDataView.getOrCreateDefaultExpensesGroup", showErrorToUser: false)
        return newGroup
    }

    // TransactionImportData struct removed, using ImportedTransaction from ImportModels.swift

    // Using simple creation logic consistent with old one but handling Inflow/Outflow columns
    nonisolated private static func extractTransactionData(
        from row: [String],
        headers: [String],
        columnMapping: [Int: String],
        dateFormatOption: DateFormatOption?,
        signConvention: AmountSignConvention
    ) -> ImportedTransaction? {
        var rowsSkipped = 0
        var skipSamples: [(rowNumber: Int, dateValue: String?, amountValue: String?, reason: String)] = []
        return Self.extractTransactionData(
            from: row,
            headers: headers,
            columnMapping: columnMapping,
            dateFormatOption: dateFormatOption,
            signConvention: signConvention,
            rowNumber: 0,
            rowsSkipped: &rowsSkipped,
            skipSamples: &skipSamples
        )
    }

    nonisolated private static func extractTransactionData(
        from row: [String],
        headers: [String],
        columnMapping: [Int: String],
        dateFormatOption: DateFormatOption?,
        signConvention: AmountSignConvention,
        rowNumber: Int,
        rowsSkipped: inout Int,
        skipSamples: inout [(rowNumber: Int, dateValue: String?, amountValue: String?, reason: String)]
    ) -> ImportedTransaction? {
        guard !row.isEmpty else { return nil }

        var date: Date?
        var rawDate: String?
        var payee = ""
        var memo: String?
        var finalAmount: Decimal?
        var rawAmount: String?
        var inflow: Decimal?
        var outflow: Decimal?
        var rawCategory: String?
        var rawAccount: String?
        var rawTags: [String] = []
        var status: TransactionStatus = .uncleared
        var kind: TransactionKind = .standard
        var transferID: UUID? = nil
        var transferInboxDismissed: Bool = false
        var externalTransferLabel: String? = nil
        var purchaseItemsJSON: String? = nil
        var usedSignedAmount = false
        
        // Unused lookup vars - could be used for categorization heuristics later
        // var _accountName: String?

        for (colIndex, value) in row.enumerated() {
            guard let field = columnMapping[colIndex], field != "skip" else { continue }
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            
            switch field {
            case "Date":
                rawDate = trimmed
                date = ImportParser.parseDate(from: trimmed, option: dateFormatOption)
            case "Payee":
                payee = trimmed
            case "Memo":
                memo = trimmed.isEmpty ? nil : trimmed
            case "Amount":
                rawAmount = trimmed
                finalAmount = ImportParser.parseAmount(trimmed)
                usedSignedAmount = true
            case "Category":
                 rawCategory = trimmed.isEmpty ? nil : trimmed
            case "Account":
                 rawAccount = trimmed.isEmpty ? nil : trimmed
            case "Tags":
                rawTags.append(contentsOf: ImportParser.parseTags(from: trimmed))
            case "Status":
                if trimmed.lowercased().prefix(1) == "c" { status = .cleared }
                else if trimmed.lowercased().prefix(1) == "r" { status = .reconciled }
            case ColumnType.kind.rawValue:
                let raw = trimmed.lowercased()
                if raw.contains("transfer") { kind = .transfer }
                else if raw.contains("ignored") { kind = .ignored }
                else if raw.contains("adjust") { kind = .adjustment }
                else { kind = .standard }
            case ColumnType.transferID.rawValue:
                if let id = UUID(uuidString: trimmed) {
                    transferID = id
                    kind = .transfer
                }
            case ColumnType.externalTransferLabel.rawValue:
                externalTransferLabel = trimmed.isEmpty ? nil : trimmed
            case ColumnType.transferInboxDismissed.rawValue:
                let raw = trimmed.lowercased()
                transferInboxDismissed = raw == "true" || raw == "1" || raw == "yes" || raw == "y"
            case ColumnType.purchaseItems.rawValue:
                purchaseItemsJSON = trimmed.isEmpty ? nil : trimmed
            case ColumnType.inflow.rawValue: // "Inflow"
                 if rawAmount == nil { rawAmount = trimmed }
                 inflow = ImportParser.parseAmount(trimmed)
            case ColumnType.outflow.rawValue: // "Outflow"
                 if rawAmount == nil { rawAmount = trimmed }
                 outflow = ImportParser.parseAmount(trimmed)
            default: break
            }
        }
        
        // Logic for Amount vs Inflow/Outflow
        if let inc = inflow, let out = outflow {
            // YNAB style: Inflow - Outflow
            finalAmount = inc - out
        } else if let inc = inflow {
             finalAmount = inc
        } else if let out = outflow {
             finalAmount = -out // Outflow is usually positive number in CSV representing expense
        }

        if usedSignedAmount, let value = finalAmount, signConvention == .positiveIsExpense {
            finalAmount = -value
        }
        
        guard let validDate = date, let amount = finalAmount else {
            let reason: String
            if date == nil && finalAmount == nil {
                reason = "Missing/invalid date and amount"
            } else if date == nil {
                reason = "Missing/invalid date"
            } else {
                reason = "Missing/invalid amount"
            }

            rowsSkipped += 1
            if skipSamples.count < 3 {
                skipSamples.append((rowNumber: rowNumber, dateValue: rawDate, amountValue: rawAmount, reason: reason))
            }
            return nil
        }

        let uniqueTags = Array(Set(rawTags)).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        // Transfers never import with a category; they are linked by Transfer ID.
        if kind == .transfer { rawCategory = nil }

        return ImportedTransaction(
            date: validDate,
            payee: payee,
            rawPayee: payee,
            amount: amount,
            memo: memo,
            rawCategory: rawCategory,
            rawAccount: rawAccount,
            rawTags: uniqueTags,
            status: status,
            kind: kind,
            transferID: transferID,
            transferInboxDismissed: transferInboxDismissed,
            externalTransferLabel: externalTransferLabel,
            purchaseItemsJSON: purchaseItemsJSON
        )
    }
    
    // For Preview (MainActor)
    func createTransaction(from row: [String], headers: [String], columnMapping: [Int: String], dateFormatOption: DateFormatOption?, signConvention: AmountSignConvention) -> Transaction? {
        guard let data = Self.extractTransactionData(from: row, headers: headers, columnMapping: columnMapping, dateFormatOption: dateFormatOption, signConvention: signConvention) else { return nil }
        return Transaction(date: data.date, payee: data.payee, amount: data.amount, memo: TransactionTextLimits.normalizedMemo(data.memo), status: data.status)
    }
}
