import SwiftUI
import SwiftData

struct SavedReceiptsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appSettings) private var settings
    @Query(sort: \ReceiptImage.createdDate, order: .reverse) private var receipts: [ReceiptImage]
    
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
                            ReceiptRow(receipt: receipt, currencyCode: settings.currencyCode)
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
            ReceiptDetailView(receipt: receipt, currencyCode: settings.currencyCode)
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
        HStack(spacing: AppDesign.Theme.Spacing.tight) {
            // Receipt thumbnail
            if let imageData = receipt.imageData,
               let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 60, height: 60)
                    .cornerRadius(AppDesign.Theme.Radius.xSmall)
                    .clipped()
            } else {
                RoundedRectangle(cornerRadius: AppDesign.Theme.Radius.xSmall)
                    .fill(Color(.secondarySystemFill))
                    .frame(width: 60, height: 60)
                    .overlay(
                        Image(systemName: "doc.text.image")
                            .foregroundStyle(.secondary)
                    )
            }

            VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.micro) {
                Text(receipt.merchant ?? "Receipt")
                    .appSectionTitleText()

                if let date = receipt.receiptDate {
                    Text(date, style: .date)
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }

                if let total = receipt.totalAmount {
                    Text(total.formatted(.currency(code: currencyCode)))
                        .appSecondaryBodyText()
                        .foregroundStyle(.secondary)
                }

                if !receipt.items.isEmpty {
                    Text("\(receipt.items.count) item\(receipt.items.count == 1 ? "" : "s")")
                        .appCaptionText()
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .appCaptionText()
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, AppDesign.Theme.Spacing.micro)
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
                VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.large) {
                    // Receipt Image
                    if let imageData = receipt.imageData,
                       let uiImage = UIImage(data: imageData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(AppDesign.Theme.Radius.compact)
                            .shadow(radius: 4)
                    }

                    // Receipt Details
                    VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
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
                    .cornerRadius(AppDesign.Theme.Radius.compact)

                    // Line Items
                    if !receipt.items.isEmpty {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.tight) {
                            Text("Items")
                                .appSectionTitleText()
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

                            VStack(spacing: 0) {
                                ForEach(receipt.items) { item in
                                    HStack {
                                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.hairline) {
                                            Text(item.name)
                                                .appSecondaryBodyText()
                                            if item.quantity > 1 {
                                                Text("\(item.quantity) × \(item.price.formatted(.currency(code: currencyCode)))")
                                                    .appCaptionText()
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        Spacer()

                                        Text((item.price * Decimal(item.quantity)).formatted(.currency(code: currencyCode)))
                                            .appSecondaryBodyText()
                                            .fontWeight(.medium)
                                    }
                                    .padding()

                                    if item.id != receipt.items.last?.id {
                                        Divider()
                                    }
                                }
                            }
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(AppDesign.Theme.Radius.compact)
                        }
                    }

                    // Extracted Text (for debugging)
                    if let extractedText = receipt.extractedText, !extractedText.isEmpty {
                        VStack(alignment: .leading, spacing: AppDesign.Theme.Spacing.compact) {
                            Text("Extracted Text")
                                .appSectionTitleText()
                                .padding(.horizontal, AppDesign.Theme.Spacing.screenHorizontal)

                            Text(extractedText)
                                .appCaptionText()
                                .foregroundStyle(.secondary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(.secondarySystemBackground))
                                .cornerRadius(AppDesign.Theme.Radius.compact)
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
                .appSecondaryBodyText()
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .appSecondaryBodyText()
        }
    }
}

#Preview {
    SavedReceiptsView()
        .modelContainer(for: [ReceiptImage.self], inMemory: true)
}
