import SwiftUI
import SwiftData

struct SavedReceiptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ReceiptImage.createdDate, order: .reverse) private var receipts: [ReceiptImage]
    @AppStorage("currencyCode") private var currencyCode = "USD"

    @State private var selectedReceipt: ReceiptImage?

    var body: some View {
        Group {
            if receipts.isEmpty {
                ContentUnavailableView(
                    "No Receipts",
                    systemImage: "doc.text.image",
                    description: Text("Receipt images you scan will appear here.")
                )
            } else {
                List {
                    ForEach(receipts) { receipt in
                        Button {
                            selectedReceipt = receipt
                        } label: {
                            ReceiptRow(receipt: receipt, currencyCode: currencyCode)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteReceipts)
                }
            }
        }
        .navigationTitle("Saved Receipts")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedReceipt) { receipt in
            ReceiptDetailView(receipt: receipt, currencyCode: currencyCode)
        }
    }

    private func deleteReceipts(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(receipts[index])
        }
    }
}

// MARK: - Receipt Row

struct ReceiptRow: View {
    let receipt: ReceiptImage
    let currencyCode: String

    var body: some View {
        HStack(spacing: 12) {
            // Receipt thumbnail
            if let imageData = receipt.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(8)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "doc.text.image")
                            .foregroundColor(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(receipt.merchant ?? "Receipt")
                    .font(.headline)

                if let date = receipt.receiptDate {
                    Text(date, style: .date)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if let total = receipt.totalAmount {
                    Text(total.formatted(.currency(code: currencyCode)))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }

                if !receipt.items.isEmpty {
                    Text("\(receipt.items.count) item\(receipt.items.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Receipt Detail View

struct ReceiptDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let receipt: ReceiptImage
    let currencyCode: String

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Receipt Image
                    if let imageData = receipt.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .shadow(radius: 4)
                    }

                    // Receipt Details
                    VStack(alignment: .leading, spacing: 12) {
                        if let merchant = receipt.merchant {
                            DetailRow(label: "Merchant", value: merchant)
                        }

                        if let date = receipt.receiptDate {
                            DetailRow(label: "Date", value: date.formatted(date: .long, time: .omitted))
                        }

                        if let total = receipt.totalAmount {
                            DetailRow(label: "Total", value: total.formatted(.currency(code: currencyCode)))
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(12)

                    // Line Items
                    if !receipt.items.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Items")
                                .font(.headline)
                                .padding(.horizontal)

                            VStack(spacing: 0) {
                                ForEach(receipt.items) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(item.name)
                                                .font(.subheadline)
                                            if item.quantity > 1 {
                                                Text("\(item.quantity) × \(item.price.formatted(.currency(code: currencyCode)))")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Text((item.price * Decimal(item.quantity)).formatted(.currency(code: currencyCode)))
                                            .font(.subheadline.weight(.medium))
                                    }
                                    .padding()

                                    if item.id != receipt.items.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(12)
                        }
                    }

                    // Extracted Text (for debugging)
                    if let extractedText = receipt.extractedText, !extractedText.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Extracted Text")
                                .font(.headline)
                                .padding(.horizontal)

                            Text(extractedText)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(12)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Receipt Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline)
        }
    }
}

#Preview {
    SavedReceiptsView()
        .modelContainer(for: [ReceiptImage.self], inMemory: true)
}
