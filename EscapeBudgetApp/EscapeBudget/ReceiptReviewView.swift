import SwiftUI

struct ReceiptReviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppStorage("currencyCode") private var currencyCode = "USD"

    let image: UIImage
    let parsedReceipt: ReceiptOCRService.ParsedReceipt

    @State private var merchant: String
    @State private var date: Date
    @State private var total: String
    @State private var items: [ReceiptItem]
    @State private var selectedItems: Set<UUID> = []

    let onConfirm: (ReceiptImage, Set<UUID>) -> Void

    init(
        image: UIImage,
        parsedReceipt: ReceiptOCRService.ParsedReceipt,
        onConfirm: @escaping (ReceiptImage, Set<UUID>) -> Void
    ) {
        self.image = image
        self.parsedReceipt = parsedReceipt
        self.onConfirm = onConfirm

        _merchant = State(initialValue: parsedReceipt.merchant ?? "")
        _date = State(initialValue: parsedReceipt.date ?? Date())
        _total = State(initialValue: parsedReceipt.total.map { String(format: "%.2f", NSDecimalNumber(decimal: $0).doubleValue) } ?? "")
        _items = State(initialValue: parsedReceipt.items)
    }

    var body: some View {
        NavigationStack {
            List {
                // Receipt Image Preview
                Section {
                    if let thumbnail = image.compressedData(maxSizeKB: 100),
                       let previewImage = UIImage(data: thumbnail) {
	                        Image(uiImage: previewImage)
	                            .resizable()
	                            .scaledToFit()
	                            .frame(maxHeight: 200)
	                            .cornerRadius(AppDesign.Theme.Radius.xSmall)
	                    }
	                }

                // Receipt Details
                Section("Receipt Details") {
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                        Text("Merchant")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        TextField("Merchant name", text: $merchant)
                            .textFieldStyle(.plain)
                    }

                    DatePicker("Date", selection: $date, displayedComponents: .date)

                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                        Text("Total Amount")
                            .appCaptionText()
                            .foregroundStyle(.secondary)
                        HStack {
                            Text(currencyCode)
                                .foregroundStyle(.secondary)
                            TextField("0.00", text: $total)
                                .keyboardType(.decimalPad)
                                .textFieldStyle(.plain)
                        }
                    }
                }

                // Line Items
                if !items.isEmpty {
                    Section {
                        ForEach(items) { item in
                            HStack {
                                Button {
                                    toggleSelection(for: item.id)
                                } label: {
                                    Image(systemName: selectedItems.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedItems.contains(item.id) ? .blue : .secondary)
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                    Text(item.name)
                                        .appSecondaryBodyText()
                                    Text("\(item.quantity) × \(item.price.formatted(.currency(code: currencyCode)))")
                                        .appCaptionText()
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Text((item.price * Decimal(item.quantity)).formatted(.currency(code: currencyCode)))
                                    .appSecondaryBodyText()
                                    .fontWeight(.medium)
                            }
                        }
                        .onDelete { indexSet in
                            items.remove(atOffsets: indexSet)
                        }
                    } header: {
                        Text("Purchased Items")
                    } footer: {
                        Text("Select items to add to transaction. Tap to select, swipe to delete.")
                            .appCaptionText()
                    }

                    Button {
                        addItem()
                    } label: {
                        Label("Add Item", systemImage: "plus.circle.fill")
                    }
                }
            }
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .globalKeyboardDoneToolbar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Confirm") {
                        saveReceipt()
                    }
                }
            }
        }
    }

    private func toggleSelection(for itemId: UUID) {
        if selectedItems.contains(itemId) {
            selectedItems.remove(itemId)
        } else {
            selectedItems.insert(itemId)
        }
    }

    private func addItem() {
        let newItem = ReceiptItem(name: "", price: 0, quantity: 1)
        items.append(newItem)
    }

    private func saveReceipt() {
        guard let compressedImageData = image.compressedData(maxSizeKB: 100) else {
            return
        }

        let receiptImage = ReceiptImage(
            imageData: compressedImageData,
            extractedText: parsedReceipt.rawText,
            items: items,
            totalAmount: Decimal(string: total),
            merchant: merchant.isEmpty ? nil : merchant,
            receiptDate: date
        )

        onConfirm(receiptImage, selectedItems)
        dismiss()
    }
}

#Preview {
    ReceiptReviewView(
        image: UIImage(systemName: "doc.text.image")!,
        parsedReceipt: ReceiptOCRService.ParsedReceipt(
            merchant: "Sample Store",
            date: Date(),
            total: 25.99,
            items: [
                ReceiptItem(name: "Coffee", price: 4.50, quantity: 2),
                ReceiptItem(name: "Sandwich", price: 8.99, quantity: 1),
                ReceiptItem(name: "Chips", price: 3.50, quantity: 2)
            ],
            rawText: "Sample receipt text"
        ),
        onConfirm: { _, _ in }
    )
}
