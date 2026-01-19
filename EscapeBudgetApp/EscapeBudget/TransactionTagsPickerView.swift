import SwiftUI
import SwiftData

struct TransactionTagsPickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TransactionTag.order) private var allTags: [TransactionTag]
    @Environment(\.appColorMode) private var appColorMode

    @Binding var selectedTags: [TransactionTag]
    @State private var searchText: String = ""
    @State private var showingCreateTag = false
    @State private var editingTag: TransactionTag?
    @State private var deletingTag: TransactionTag?
    @State private var editMode: EditMode = .inactive

    var body: some View {
        List {
            if filteredTags.isEmpty {
                ContentUnavailableView(
                    "No Tags",
                    systemImage: "tag",
                    description: Text(searchText.isEmpty ? "Create a tag to get started." : "No tags match your search.")
                )
                .listRowSeparator(.hidden)
            } else {
                ForEach(filteredTags) { tag in
                    Button {
                        toggle(tag)
                    } label: {
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color(hex: tag.colorHex) ?? AppColors.tint(for: appColorMode))
                                .frame(width: 14, height: 14)

                            Text(tag.name)
                                .foregroundStyle(.primary)

                            Spacer()

                            if isSelected(tag) {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(AppColors.success(for: appColorMode))
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            deletingTag = tag
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        Button {
                            editingTag = tag
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(AppColors.tint(for: appColorMode))
                    }
                }
                .onMove(perform: moveTags)
            }
        }
        .navigationTitle("Tags")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .environment(\.editMode, $editMode)
        .onLongPressGesture(minimumDuration: 0.45) {
            guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            withAnimation {
                editMode = .active
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingCreateTag = true
                } label: {
                    Label("New Tag", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingCreateTag) {
            NavigationStack {
                CreateTransactionTagView(
                    onCreate: { created in
                        if !selectedTags.contains(where: { $0.persistentModelID == created.persistentModelID }) {
                            selectedTags.append(created)
                        }
                    }
                )
            }
        }
        .sheet(item: $editingTag) { tag in
            NavigationStack {
                EditTransactionTagView(tag: tag)
            }
        }
        .confirmationDialog(
            deletingTag == nil ? "" : "Delete \"\(deletingTag?.name ?? "")\"?",
            isPresented: Binding(
                get: { deletingTag != nil },
                set: { if !$0 { deletingTag = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete Tag", role: .destructive) {
                guard let tag = deletingTag else { return }
                deletingTag = nil
                delete(tag)
            }
            Button("Cancel", role: .cancel) { deletingTag = nil }
        } message: {
            Text("This will remove the tag from all transactions.")
        }
        .onAppear {
            ensureStableOrdering()
        }
    }

    private var filteredTags: [TransactionTag] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = allTags.sorted {
            if $0.order == $1.order {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.order < $1.order
        }
        guard !trimmed.isEmpty else { return base }
        return base.filter { $0.name.localizedCaseInsensitiveContains(trimmed) }
    }

    private func isSelected(_ tag: TransactionTag) -> Bool {
        selectedTags.contains { $0.persistentModelID == tag.persistentModelID }
    }

    private func toggle(_ tag: TransactionTag) {
        if isSelected(tag) {
            selectedTags.removeAll { $0.persistentModelID == tag.persistentModelID }
        } else {
            selectedTags.append(tag)
        }
    }

    private func moveTags(from source: IndexSet, to destination: Int) {
        guard searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        var tags = filteredTags
        tags.move(fromOffsets: source, toOffset: destination)
        for (index, tag) in tags.enumerated() {
            tag.order = index
        }
        modelContext.safeSave(context: "TransactionTagsPickerView.moveTags")
    }

    private func ensureStableOrdering() {
        guard !allTags.isEmpty else { return }
        let hasAnyCustomOrder = allTags.contains { $0.order != 0 }
        guard !hasAnyCustomOrder else { return }

        let sortedByName = allTags.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        for (index, tag) in sortedByName.enumerated() {
            tag.order = index
        }
        modelContext.safeSave(context: "TransactionTagsPickerView.ensureStableOrdering", showErrorToUser: false)
    }

    private func delete(_ tag: TransactionTag) {
        if let transactions = tag.transactions {
            for tx in transactions {
                tx.tags?.removeAll { $0.persistentModelID == tag.persistentModelID }
            }
        }
        modelContext.delete(tag)
        modelContext.safeSave(context: "TransactionTagsPickerView.deleteTag")

        selectedTags.removeAll { $0.persistentModelID == tag.persistentModelID }
    }
}

private struct CreateTransactionTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \TransactionTag.order) private var existingTags: [TransactionTag]
    @Environment(\.appColorMode) private var appColorMode

    var onCreate: (TransactionTag) -> Void

    @State private var name: String = ""
    @State private var selectedColorHex: String = TagColorPalette.defaultHex
    @State private var customColor: Color = .blue

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        Form {
            Section("Name") {
                TextField("Tag Name", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section("Color") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TagColorPalette.options(for: appColorMode), id: \.hex) { option in
                        Circle()
                            .fill(Color(hex: option.hex) ?? AppColors.tint(for: appColorMode))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(selectedColorHex == option.hex ? Color.primary : Color.clear, lineWidth: 3)
                            )
                            .onTapGesture {
                                selectedColorHex = option.hex
                            }
                            .accessibilityLabel(Text(option.name))
                    }
                }
                .padding(.vertical, 4)

                ColorPicker("Color Wheel", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newValue in
                        if let hex = colorHex(from: newValue) {
                            selectedColorHex = hex
                        }
                    }
            }
        }
        .navigationTitle("New Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Create") {
                    createOrSelectExisting()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            if let initial = Color(hex: selectedColorHex) {
                customColor = initial
            }
        }
        .onAppear {
            if customColor == .blue {
                customColor = AppColors.tint(for: appColorMode)
            }
        }
    }

    private func createOrSelectExisting() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if let existing = existingTags.first(where: { $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame }) {
            onCreate(existing)
            dismiss()
            return
        }

        let nextOrder = (existingTags.map(\.order).max() ?? -1) + 1
        let tag = TransactionTag(name: trimmed, colorHex: selectedColorHex, order: nextOrder)
        modelContext.insert(tag)
        onCreate(tag)
        dismiss()
    }

    private func colorHex(from color: Color) -> String? {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

private struct EditTransactionTagView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.appColorMode) private var appColorMode

    let tag: TransactionTag

    @State private var name: String = ""
    @State private var selectedColorHex: String = TagColorPalette.defaultHex
    @State private var customColor: Color = .blue

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        Form {
            Section("Name") {
                TextField("Tag Name", text: $name)
                    .textInputAutocapitalization(.words)
            }

            Section("Color") {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TagColorPalette.options(for: appColorMode), id: \.hex) { option in
                        Circle()
                            .fill(Color(hex: option.hex) ?? AppColors.tint(for: appColorMode))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Circle()
                                    .stroke(selectedColorHex == option.hex ? Color.primary : Color.clear, lineWidth: 3)
                            )
                            .onTapGesture {
                                selectedColorHex = option.hex
                                if let initial = Color(hex: option.hex) {
                                    customColor = initial
                                }
                            }
                            .accessibilityLabel(Text(option.name))
                    }
                }
                .padding(.vertical, 4)

                ColorPicker("Color Wheel", selection: $customColor, supportsOpacity: false)
                    .onChange(of: customColor) { _, newValue in
                        if let hex = colorHex(from: newValue) {
                            selectedColorHex = hex
                        }
                    }
            }
        }
        .navigationTitle("Edit Tag")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    save()
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .onAppear {
            name = tag.name
            selectedColorHex = tag.colorHex
            if let initial = Color(hex: tag.colorHex) {
                customColor = initial
            } else if customColor == .blue {
                customColor = AppColors.tint(for: appColorMode)
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        tag.name = trimmed
        tag.colorHex = selectedColorHex
        modelContext.safeSave(context: "EditTransactionTagView.saveTag")
    }

    private func colorHex(from color: Color) -> String? {
        let uiColor = UIColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        guard uiColor.getRed(&red, green: &green, blue: &blue, alpha: &alpha) else { return nil }
        return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
    }
}

struct TransactionTagChip: View {
    let tag: TransactionTag
    @Environment(\.appColorMode) private var appColorMode

    var body: some View {
        let fallback = AppColors.tint(for: appColorMode)
        Text(tag.name)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.primary)
            .padding(.horizontal, AppTheme.Spacing.small)
            .padding(.vertical, 4)
            .background(
                Capsule().fill((Color(hex: tag.colorHex) ?? fallback).opacity(0.18))
            )
            .overlay(
                Capsule().stroke((Color(hex: tag.colorHex) ?? fallback).opacity(0.35), lineWidth: 1)
            )
    }
}
