import SwiftUI
import SwiftData

struct TransactionFormView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    var transaction: Transaction?
    
    @Query(sort: \Category.order) private var categories: [Category]
    
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
    
    private let currencies = ["HKD", "USD", "JPY"]
    
    init(transaction: Transaction? = nil, isEditing: Bool = true) {
        self.transaction = transaction
        self._isEditing = State(initialValue: transaction == nil ? true : isEditing)
    }
    
    var body: some View {
        NavigationStack {
            Form {
                // 金額 + 貨幣
                Section(header: Text(langManager.localized("form_amount"))) {
                    HStack(spacing: 12) {
                        if isEditing {
                            TextField(langManager.localized("form_amount_placeholder"), text: $amountText)
                                .keyboardType(.decimalPad)
                            
                            Menu {
                                ForEach(currencies, id: \.self) { code in
                                    Button(action: { currencyCode = code }) {
                                        HStack {
                                            Text("\(currencySymbol(for: code)) \(code)")
                                            if currencyCode == code {
                                                Spacer()
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    Text("\(currencySymbol(for: currencyCode)) \(currencyCode)")
                                    Image(systemName: "chevron.down")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .fixedSize()
                        } else {
                            Text(format(amount: Decimal(string: amountText) ?? 0, code: currencyCode))
                        }
                    }
                }
                
                // 類型
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
                    }
                }
                
                // 分類
                Section(header: Text(langManager.localized("form_category"))) {
                    if isEditing {
                        Picker(langManager.localized("form_parent_category"), selection: $selectedParentID) {
                            Text(langManager.localized("form_none")).tag(UUID?.none)
                            ForEach(categories.filter { $0.parentID == nil }) { cat in
                                Text(cat.name).tag(Optional(cat.id))
                            }
                        }
                        .pickerStyle(.menu)
                        
                        let subsForSelectedParent: [Category] = {
                            if let parent = selectedParentID {
                                return categories.filter { $0.parentID == parent }
                            } else {
                                return categories.filter { $0.parentID != nil }
                            }
                        }()
                        
                        Picker(langManager.localized("form_subcategory"), selection: $selectedSubcategoryID) {
                            Text(langManager.localized("form_none")).tag(UUID?.none)
                            ForEach(subsForSelectedParent) { sub in
                                HStack {
                                    Circle()
                                        .fill(Color(hex: sub.colorHex ?? "#A8A8A8"))
                                        .frame(width: 12, height: 12)
                                    Text(sub.name)
                                }
                                .tag(Optional(sub.id))
                            }
                        }
                        .pickerStyle(.menu)
                        .disabled(selectedParentID == nil)
                        .foregroundColor(selectedParentID == nil ? .secondary : .primary)
                        
                    } else {
                        HStack {
                            Text(categoryPath(parentID: selectedParentID, subID: selectedSubcategoryID))
                            if let subID = selectedSubcategoryID,
                               let sub = categories.first(where: { $0.id == subID }) {
                                Circle()
                                    .fill(Color(hex: sub.colorHex ?? "#A8A8A8"))
                                    .frame(width: 20, height: 20)
                            }
                        }
                    }
                }
                
                // 備註
                Section(header: Text(langManager.localized("form_note"))) {
                    if isEditing {
                        TextField(langManager.localized("form_note_placeholder"), text: $note)
                    } else {
                        Text(note.isEmpty ? "-" : note)
                    }
                }
                
                // 日期
                Section(header: Text(langManager.localized("form_date"))) {
                    if isEditing {
                        DatePicker(langManager.localized("form_date_picker"), selection: $date, displayedComponents: .date)
                    } else {
                        Text(date, format: .dateTime.year().month().day())
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
                    if let catID = tx.categoryID {
                        if let cat = categories.first(where: { $0.id == catID }) {
                            if let parent = cat.parentID {
                                selectedParentID = parent
                                selectedSubcategoryID = cat.id
                            } else {
                                selectedParentID = cat.id
                                selectedSubcategoryID = nil
                            }
                        }
                    }
                }
            }
            .alert(langManager.localized("form_delete_title"), isPresented: $showDeleteAlert) {
                Button(langManager.localized("form_cancel"), role: .cancel) {}
                Button(langManager.localized("form_delete"), role: .destructive) { deleteConfirmed() }
            } message: {
                Text(langManager.localized("form_delete_message"))
            }
        }
    }
    
    var isValid: Bool {
        Decimal(string: amountText) != nil
    }
    
    private func save() {
        guard let amount = Decimal(string: amountText) else { return }
        let finalCategoryID = selectedSubcategoryID ?? selectedParentID
        
        if let tx = currentTransaction {
            tx.amount = amount
            tx.date = date
            tx.note = note.isEmpty ? nil : note
            tx.type = selectedType
            tx.currencyCode = currencyCode
            tx.categoryID = finalCategoryID
            try? context.save()
        } else {
            let tx = Transaction(amount: amount,
                                 date: date,
                                 note: note.isEmpty ? nil : note,
                                 categoryID: finalCategoryID,
                                 type: selectedType,
                                 currencyCode: currencyCode)
            context.insert(tx)
            try? context.save()
            currentTransaction = tx
        }
        dismiss()
    }
    
    private func deleteConfirmed() {
        guard let tx = currentTransaction else { return }
        context.delete(tx)
        try? context.save()
        dismiss()
    }
    
    private func decimalToString(_ d: Decimal) -> String {
        let ns = d as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: ns) ?? "\(d)"
    }
    
    private func format(amount: Decimal, code: String = "HKD") -> String {
        let ns = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
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
    
    private func categoryPath(parentID: UUID?, subID: UUID?) -> String {
        if let subID = subID,
           let sub = categories.first(where: { $0.id == subID }),
           let parent = categories.first(where: { $0.id == sub.parentID }) {
            // 同時顯示父分類 / 子分類
            return "\(parent.name) / \(sub.name)"
        } else if let parentID = parentID,
                  let parent = categories.first(where: { $0.id == parentID }) {
            // 只選父分類
            return parent.name
        } else {
            // 無選擇
            return langManager.localized("form_none")
        }
    }
}
