//
// TransactionFormView.swift
//

import SwiftUI
import SwiftData
import UIKit

// MARK: - SelectAllTextField (UIViewRepresentable)
struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFirstResponder: Bool

    var placeholder: String
    var keyboardType: UIKeyboardType = .default
    var onCommit: (() -> Void)? = nil

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField(frame: .zero)
        tf.delegate = context.coordinator
        tf.placeholder = placeholder
        tf.keyboardType = keyboardType
        tf.borderStyle = .none
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingDidBegin), for: .editingDidBegin)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged), for: .editingChanged)
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingDidEndOnExit), for: .editingDidEndOnExit)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }

        if isFirstResponder && !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
            // selection handled in editingDidBegin
        } else if !isFirstResponder && uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField

        init(_ parent: SelectAllTextField) {
            self.parent = parent
        }

        @objc func editingDidBegin(_ sender: UITextField) {
            // Select all text when editing begins
            DispatchQueue.main.async {
                sender.selectAll(nil)
            }
            parent.isFirstResponder = true
        }

        @objc func editingChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        @objc func editingDidEndOnExit(_ sender: UITextField) {
            parent.onCommit?()
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            parent.isFirstResponder = false
            parent.text = textField.text ?? ""
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit?()
            return true
        }
    }
}

// MARK: - TransactionFormView

struct TransactionFormView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    var transaction: Transaction?

    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Subcategory.order) private var subcategories: [Subcategory]

    @State private var amountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedParentID: UUID? = nil
    @State private var selectedSubcategoryID: UUID? = nil
    @State private var selectedType: TransactionType = .expense
    @State private var currencyCode: String = "HKD"

    @State private var currentTransaction: Transaction? = nil
    @State private var showDeleteAlert = false
    @State private var isEditing: Bool = true

    @State private var amountFieldIsFirstResponder: Bool = false
    @FocusState private var focusedField: Field?

    private let currencies = ["HKD", "USD", "JPY"]
    
    enum Field {
        case amount, note
    }

    init(transaction: Transaction? = nil, isEditing: Bool = true) {
        self.transaction = transaction
        self._isEditing = State(initialValue: transaction == nil ? true : isEditing)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Amount + Currency
                Section(header: Text(langManager.localized("form_amount"))) {
                    HStack(spacing: 12) {
                        if isEditing {
                            SelectAllTextField(
                                text: $amountText,
                                isFirstResponder: $amountFieldIsFirstResponder,
                                placeholder: langManager.localized("form_amount_placeholder"),
                                keyboardType: .decimalPad,
                                onCommit: {
                                    if let value = decimalFromString(amountText) {
                                        amountText = decimalToString(value)
                                    }
                                    focusedField = nil
                                }
                            )
                            .frame(height: 28)
                            .controlSize(.small)
                            .focused($focusedField, equals: .amount)
                            .onTapGesture {
                                // This ensures tapping on the field brings up keyboard
                                amountFieldIsFirstResponder = true
                            }

                            Menu {
                                ForEach(currencies, id: \.self) { code in
                                    Button(action: { currencyCode = code }) {
                                        HStack {
                                            Text("\(currencySymbol(for: code)) \(code)")
                                                .font(.system(size: 18))
                                            if currencyCode == code {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text("\(currencySymbol(for: currencyCode)) \(currencyCode)")
                                        .font(.system(size: 18))
                                        .foregroundColor(.primary)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(minWidth: 110, maxHeight: 28)
                            .controlSize(.small)
                        } else {
                            let displayAmount: Decimal = currentTransaction?.amount ?? (decimalFromString(amountText) ?? 0)
                            Text(formatCurrency(amount: displayAmount, code: currencyCode))
                                .font(.system(size: 18))
                                .frame(height: 28)
                                .foregroundColor(selectedType == .income ? .green : .red)
                        }
                    }
                }

                // Type
                Section(header: Text(langManager.localized("form_type"))) {
                    if isEditing {
                        Picker(langManager.localized("form_type_label"), selection: $selectedType) {
                            Text(langManager.localized("form_income")).tag(TransactionType.income)
                            Text(langManager.localized("form_expense")).tag(TransactionType.expense)
                        }
                        .pickerStyle(.segmented)
                    } else {
                        Text(selectedType == .income ? langManager.localized("form_income")
                             : langManager.localized("form_expense"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                // Category (Parent / Subcategory)
                Section(header: Text(langManager.localized("category_section_header"))) {
                    if isEditing {
                        let subsForSelectedParent: [Subcategory] = {
                            if let parent = selectedParentID {
                                return subcategories.filter { $0.parentID == parent }
                            } else {
                                return []
                            }
                        }()

                        HStack(spacing: 12) {
                            // Parent category menu
                            Menu {
                                Button(action: {
                                    selectedParentID = nil
                                    selectedSubcategoryID = nil
                                }) {
                                    HStack {
                                        Text(langManager.localized("form_none"))
                                        if selectedParentID == nil {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }

                                ForEach(categories) { cat in
                                    Button(action: {
                                        selectedParentID = cat.id
                                        if let firstSub = subcategories.first(where: { $0.parentID == cat.id }) {
                                            selectedSubcategoryID = firstSub.id
                                        } else {
                                            selectedSubcategoryID = nil
                                        }
                                    }) {
                                        HStack {
                                            Text(cat.name)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            if selectedParentID == cat.id {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedParentName)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundColor(selectedParentID == nil ? .secondary : .primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity)

                            Text("/")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))

                            // Subcategory menu
                            Menu {
                                Button(action: { selectedSubcategoryID = nil }) {
                                    HStack {
                                        Text(langManager.localized("form_none"))
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                        if selectedSubcategoryID == nil {
                                            Spacer()
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }

                                ForEach(subsForSelectedParent) { sub in
                                    Button(action: {
                                        selectedSubcategoryID = sub.id
                                    }) {
                                        HStack {
                                            Text(sub.name)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            if selectedSubcategoryID == sub.id {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text(selectedSubcategoryName)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                        .foregroundColor(selectedParentID == nil ? .secondary : .primary)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .disabled(selectedParentID == nil)
                            .frame(maxWidth: .infinity)
                        }
                        .frame(maxWidth: .infinity)
                        .onChange(of: selectedParentID) { newParent in
                            DispatchQueue.main.async {
                                if let subID = selectedSubcategoryID {
                                    if let sub = subcategories.first(where: { $0.id == subID }) {
                                        if sub.parentID != newParent {
                                            selectedSubcategoryID = nil
                                        }
                                    } else {
                                        selectedSubcategoryID = nil
                                    }
                                }
                                if newParent == nil {
                                    selectedSubcategoryID = nil
                                }
                            }
                        }
                    } else {
                        HStack {
                            Text(categoryPath(parentID: selectedParentID, subID: selectedSubcategoryID))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }

                // Note
                Section(header: Text(langManager.localized("form_note"))) {
                    if isEditing {
                        TextField(langManager.localized("form_note_placeholder"), text: $note)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .focused($focusedField, equals: .note)
                    } else {
                        Text(note.isEmpty ? langManager.localized("form_none") : note)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

                // Date
                Section(header: Text(langManager.localized("form_date"))) {
                    if isEditing {
                        DatePicker(langManager.localized("form_date_picker"), selection: $date, displayedComponents: .date)
                    } else {
                        Text(date, format: .dateTime.year().month().day())
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
            }
            .navigationTitle(currentTransaction == nil
                             ? langManager.localized("form_add_title")
                             : (isEditing ? langManager.localized("form_edit_title")
                                : langManager.localized("transaction_detail_title")))
            .toolbar {
                if isEditing {
                    ToolbarItemGroup(placement: .navigationBarTrailing) {
                        if currentTransaction != nil {
                            Button(role: .destructive) {
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                            }
                        }
                        Button(langManager.localized("form_save")) { save() }
                            .disabled(!isValid)
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(langManager.localized("form_cancel")) { dismiss() }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(langManager.localized("form_edit_title")) {
                            isEditing = true
                            // 🚫 Removed auto-focus when switching to edit
                        }
                    }
                }
            }
            .onAppear {
                if let tx = transaction {
                    currentTransaction = tx
                    amountText = decimalToString(tx.amount)
                    date = tx.date
                    note = tx.note ?? ""
                    selectedType = tx.type
                    currencyCode = tx.currencyCode
                    if let subID = tx.subcategoryID,
                       let sub = subcategories.first(where: { $0.id == subID }) {
                        selectedSubcategoryID = sub.id
                        selectedParentID = sub.parentID
                    } else {
                        selectedSubcategoryID = nil
                        selectedParentID = nil
                    }
                }
                // 🚫 Removed auto-focus for new transaction
            }
            .alert(langManager.localized("form_delete_title"), isPresented: $showDeleteAlert) {
                Button(langManager.localized("form_cancel"), role: .cancel) {}
                Button(langManager.localized("form_delete"), role: .destructive) { deleteConfirmed() }
            } message: {
                Text(langManager.localized("form_delete_message"))
            }
            // ADD THIS: Dismiss keyboard when tapping outside
            .onTapGesture {
                hideKeyboard()
            }
            // ADD THIS: Add a Done button to the keyboard toolbar
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        hideKeyboard()
                    }
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var selectedParentName: String {
        if let parentID = selectedParentID,
           let parent = categories.first(where: { $0.id == parentID }) {
            return parent.name
        } else {
            return langManager.localized("form_none")
        }
    }

    private var selectedSubcategoryName: String {
        if selectedParentID == nil {
            return langManager.localized("select_parent_first")
        } else if let subID = selectedSubcategoryID,
                  let sub = subcategories.first(where: { $0.id == subID }) {
            return sub.name
        } else {
            return langManager.localized("form_none")
        }
    }

    // MARK: - Validation

    var isValid: Bool {
        decimalFromString(amountText) != nil
    }

    // MARK: - Helper Methods

    private func save() {
        amountFieldIsFirstResponder = false
        hideKeyboard()
        DispatchQueue.main.async {
            guard let amount = decimalFromString(amountText) else {
                return
            }
            let finalSubcategoryID = selectedSubcategoryID
            if let tx = currentTransaction {
                tx.amount = amount
                tx.date = date
                tx.note = note.isEmpty ? nil : note
                tx.type = selectedType
                tx.currencyCode = currencyCode
                tx.subcategoryID = finalSubcategoryID
                try? context.save()
            } else {
                let tx = Transaction(amount: amount,
                                     date: date,
                                     note: note.isEmpty ? nil : note,
                                     subcategoryID: finalSubcategoryID,
                                     type: selectedType,
                                     currencyCode: currencyCode)
                context.insert(tx)
                try? context.save()
                currentTransaction = tx
            }
            dismiss()
        }
    }

    private func deleteConfirmed() {
        guard let tx = currentTransaction else { return }
        context.delete(tx)
        try? context.save()
        dismiss()
    }

    // MARK: - Number Helpers

    private func decimalFromString(_ string: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.usesGroupingSeparator = true
        return formatter.number(from: string)?.decimalValue
    }

    private func decimalToString(_ d: Decimal) -> String {
        let ns = d as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale.current
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: ns) ?? "\(d)"
    }

    private func formatCurrency(amount: Decimal, code: String = "HKD") -> String {
        let ns = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        return formatter.string(from: ns) ?? "\(amount)"
    }

    private func currencySymbol(for code: String) -> String {
        switch code {
        case "HKD": return "HK$"
        case "USD": return "$"
        case "JPY": return "¥"
        default: return code
        }
    }

    private func decimalToStringNoGrouping(_ d: Decimal) -> String {
        return decimalToString(d)
    }

    private func categoryPath(parentID: UUID?, subID: UUID?) -> String {
        if let subID = subID,
           let sub = subcategories.first(where: { $0.id == subID }),
           let parent = categories.first(where: { $0.id == sub.parentID }) {
            return "\(parent.name) / \(sub.name)"
        } else if let parentID = parentID,
                  let parent = categories.first(where: { $0.id == parentID }) {
            return parent.name
        } else {
            return langManager.localized("form_none")
        }
    }
    
    // ADD THIS: Helper function to hide keyboard
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                       to: nil, from: nil, for: nil)
        amountFieldIsFirstResponder = false
        focusedField = nil
    }
}
