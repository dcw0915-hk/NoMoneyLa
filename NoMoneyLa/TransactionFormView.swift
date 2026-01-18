import SwiftUI
import SwiftData
import UIKit

// MARK: - ContributionEntry (表單暫存用)
struct ContributionEntry: Identifiable {
    let id = UUID()
    var payerID: UUID?
    var amountText: String = ""
    var isRemovable: Bool = true
}

// MARK: - SelectAllTextField
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
    @Query(sort: \Payer.order) private var payers: [Payer]

    @State private var totalAmountText = ""
    @State private var date = Date()
    @State private var note = ""
    @State private var selectedParentID: UUID? = nil
    @State private var selectedSubcategoryID: UUID? = nil
    @State private var selectedType: TransactionType = .expense
    @State private var currencyCode: String = "HKD"
    
    @State private var contributions: [ContributionEntry] = []
    @State private var showAmountError = false
    @State private var showContributionSection = false
    
    @State private var currentTransaction: Transaction? = nil
    @State private var showDeleteAlert = false
    @State private var isEditing: Bool = true

    @State private var amountFieldIsFirstResponder: Bool = false
    @FocusState private var focusedField: Field?

    private let currencies = ["HKD", "USD", "JPY"]
    
    enum Field {
        case totalAmount, note
    }

    init(transaction: Transaction? = nil, isEditing: Bool = true) {
        self.transaction = transaction
        self._isEditing = State(initialValue: transaction == nil ? true : isEditing)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text(langManager.localized("form_amount"))) {
                    HStack(spacing: 12) {
                        if isEditing {
                            SelectAllTextField(
                                text: $totalAmountText,
                                isFirstResponder: $amountFieldIsFirstResponder,
                                placeholder: langManager.localized("form_amount_placeholder"),
                                keyboardType: .decimalPad,
                                onCommit: {
                                    if let value = decimalFromString(totalAmountText) {
                                        totalAmountText = decimalToString(value)
                                    }
                                }
                            )
                            .frame(height: 28)
                            .controlSize(.small)
                            .focused($focusedField, equals: .totalAmount)

                            Menu {
                                ForEach(currencies, id: \.self) { code in
                                    Button(action: {
                                        hideKeyboard()
                                        currencyCode = code
                                    }) {
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
                            .onTapGesture {
                                hideKeyboard()
                            }
                        } else {
                            let displayAmount: Decimal = currentTransaction?.totalAmount ?? (decimalFromString(totalAmountText) ?? 0)
                            Text(formatCurrency(amount: displayAmount, code: currencyCode))
                                .font(.system(size: 18))
                                .frame(height: 28)
                                .foregroundColor(selectedType == .income ? .green : .red)
                        }
                    }
                }

                Section(header: Text(langManager.localized("form_type"))) {
                    if isEditing {
                        Picker(langManager.localized("form_type_label"), selection: $selectedType) {
                            Text(langManager.localized("form_income")).tag(TransactionType.income)
                            Text(langManager.localized("form_expense")).tag(TransactionType.expense)
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: selectedType) { newType in
                            hideKeyboard()
                            handleTypeChange(newType)
                        }
                        .onTapGesture {
                            hideKeyboard()
                        }
                    } else {
                        Text(selectedType == .income ? langManager.localized("form_income")
                             : langManager.localized("form_expense"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }

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
                            Menu {
                                Button(action: {
                                    hideKeyboard()
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
                                        hideKeyboard()
                                        selectedParentID = cat.id
                                        // 自動選擇該分類下的「未分類」子分類
                                        if let uncategorizedSub = subcategories.first(where: {
                                            $0.parentID == cat.id && $0.name == "未分類"
                                        }) {
                                            selectedSubcategoryID = uncategorizedSub.id
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
                            .onTapGesture {
                                hideKeyboard()
                            }

                            Text("/")
                                .foregroundColor(.secondary)
                                .font(.system(size: 14))

                            Menu {
                                ForEach(subsForSelectedParent) { sub in
                                    Button(action: {
                                        hideKeyboard()
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
                            .onTapGesture {
                                hideKeyboard()
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .onChange(of: selectedParentID) { newParent in
                            DispatchQueue.main.async {
                                if let newParent = newParent {
                                    // 當選擇父分類時，自動選擇「未分類」子分類
                                    if let uncategorizedSub = subcategories.first(where: {
                                        $0.parentID == newParent && $0.name == "未分類"
                                    }) {
                                        selectedSubcategoryID = uncategorizedSub.id
                                    }
                                } else {
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

                Section(header: Text(langManager.localized("form_date"))) {
                    if isEditing {
                        DatePicker(langManager.localized("form_date_picker"), selection: $date, displayedComponents: .date)
                            .onChange(of: date) { _ in
                                hideKeyboard()
                            }
                    } else {
                        Text(date, format: .dateTime.year().month().day())
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                }
                
                if selectedType == .expense {
                    Section {
                        if isEditing {
                            Toggle("啟用分攤", isOn: $showContributionSection)
                                .onChange(of: showContributionSection) { show in
                                    hideKeyboard()
                                    if show {
                                        if contributions.isEmpty {
                                            let firstPayer = payers.first ?? defaultPayer
                                            contributions.append(ContributionEntry(
                                                payerID: firstPayer?.id,
                                                amountText: totalAmountText,
                                                isRemovable: true
                                            ))
                                        }
                                    } else {
                                        contributions.removeAll()
                                    }
                                }
                                .onTapGesture {
                                    hideKeyboard()
                                }
                        } else {
                            HStack {
                                Text("分攤")
                                Spacer()
                                Text(showContributionSection ? "已啟用" : "未啟用")
                                    .foregroundColor(.secondary)
                            }
                        }
                    } footer: {
                        Text(showContributionSection ? "分攤已啟用，您可以為此交易分配多個付款人" : "分攤未啟用，將使用預設付款人")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if selectedType == .expense && showContributionSection {
                    Section(header: HStack {
                        Text("付款人分攤")
                        Spacer()
                        if isEditing && !contributions.isEmpty {
                            Button(action: {
                                hideKeyboard()
                                distributeEqually()
                            }) {
                                Text("平均分攤")
                                    .font(.caption)
                            }
                        }
                    }) {
                        if isEditing {
                            ForEach(0..<contributions.count, id: \.self) { index in
                                HStack(spacing: 12) {
                                    Menu {
                                        Text("選擇付款人")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        ForEach(getAvailablePayers(for: index)) { payer in
                                            Button(action: {
                                                hideKeyboard()
                                                contributions[index].payerID = payer.id
                                            }) {
                                                HStack {
                                                    Text(payer.name)
                                                    if contributions[index].payerID == payer.id {
                                                        Spacer()
                                                        Image(systemName: "checkmark")
                                                    }
                                                }
                                            }
                                        }
                                    } label: {
                                        HStack(spacing: 6) {
                                            Circle()
                                                .fill(Color(hex: getPayerColor(for: index) ?? "#A8A8A8"))
                                                .frame(width: 12, height: 12)
                                            
                                            Text(getPayerName(for: index))
                                                .foregroundColor(contributions[index].payerID == nil ? .secondary : .primary)
                                                .frame(width: 100)
                                        }
                                    }
                                    .frame(width: 140)
                                    .onTapGesture {
                                        hideKeyboard()
                                    }
                                    
                                    TextField("金額", text: Binding(
                                        get: { contributions[index].amountText },
                                        set: { newValue in
                                            contributions[index].amountText = newValue
                                            validateAmounts()
                                        }
                                    ))
                                    .keyboardType(.decimalPad)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 80)
                                    .onTapGesture {
                                        hideKeyboard()
                                    }
                                    
                                    Text(currencyCode)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    if contributions[index].isRemovable {
                                        Button(action: {
                                            hideKeyboard()
                                            contributions.remove(at: index)
                                            validateAmounts()
                                        }) {
                                            Image(systemName: "minus.circle")
                                                .foregroundColor(.red)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                        .onTapGesture {
                                            hideKeyboard()
                                        }
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            
                            Button(action: {
                                hideKeyboard()
                                contributions.append(ContributionEntry(
                                    payerID: nil,
                                    amountText: "",
                                    isRemovable: true
                                ))
                            }) {
                                HStack {
                                    Image(systemName: "plus.circle.fill")
                                        .foregroundColor(.accentColor)
                                    Text("新增付款人")
                                }
                            }
                            .padding(.top, 4)
                            
                            if !contributions.isEmpty {
                                HStack {
                                    Text("分攤總計")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(formatCurrency(amount: distributedTotal, code: currencyCode)) / \(formatCurrency(amount: totalAmountDecimal, code: currencyCode))")
                                        .font(.caption)
                                        .foregroundColor(distributedTotal == totalAmountDecimal ? .green : .red)
                                }
                                .padding(.top, 8)
                            }
                            
                            if showAmountError {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text("分攤總金額與交易總金額不一致")
                                        .font(.caption)
                                        .foregroundColor(.orange)
                                }
                                .padding(.top, 4)
                            }
                        } else {
                            if contributions.isEmpty {
                                Text("無付款人")
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(contributions, id: \.id) { contribution in
                                    if let payerID = contribution.payerID,
                                       let payer = payers.first(where: { $0.id == payerID }),
                                       let amount = decimalFromString(contribution.amountText) {
                                        HStack {
                                            Circle()
                                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                .frame(width: 12, height: 12)
                                            
                                            Text(payer.name)
                                                .font(.body)
                                            Spacer()
                                            Text(formatCurrency(amount: amount, code: currencyCode))
                                                .font(.body)
                                        }
                                        .padding(.vertical, 2)
                                    }
                                }
                                HStack {
                                    Text("總計")
                                        .font(.headline)
                                    Spacer()
                                    Text(formatCurrency(amount: totalAmountDecimal, code: currencyCode))
                                        .font(.headline)
                                }
                                .padding(.top, 8)
                            }
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
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
                        Button(langManager.localized("form_save")) {
                            hideKeyboard()
                            save()
                        }
                        .disabled(!isValid)
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(langManager.localized("form_cancel")) {
                            hideKeyboard()
                            dismiss()
                        }
                    }
                } else {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(langManager.localized("form_edit_title")) {
                            isEditing = true
                        }
                    }
                }
            }
            .onAppear { setupInitialData() }
            .alert(langManager.localized("form_delete_title"), isPresented: $showDeleteAlert) {
                Button(langManager.localized("form_cancel"), role: .cancel) {}
                Button(langManager.localized("form_delete"), role: .destructive) { deleteConfirmed() }
            } message: {
                Text(langManager.localized("form_delete_message"))
            }
        }
    }
    
    // MARK: - Computed Properties
    
    private var navigationTitle: String {
        if currentTransaction == nil {
            return langManager.localized("form_add_title")
        } else if isEditing {
            return langManager.localized("form_edit_title")
        } else {
            return langManager.localized("transaction_detail_title")
        }
    }
    
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
            return "請先選擇主分類"
        } else if let subID = selectedSubcategoryID,
                  let sub = subcategories.first(where: { $0.id == subID }) {
            return sub.name
        } else {
            return langManager.localized("form_none")
        }
    }
    
    private var totalAmountDecimal: Decimal {
        decimalFromString(totalAmountText) ?? 0
    }
    
    private var distributedTotal: Decimal {
        contributions.reduce(0) { total, contribution in
            total + (decimalFromString(contribution.amountText) ?? 0)
        }
    }
    
    private var isValid: Bool {
        guard let total = decimalFromString(totalAmountText), total > 0 else { return false }
        
        // 檢查分類選擇
        if selectedParentID != nil && selectedSubcategoryID == nil {
            return false // 有父分類但沒有子分類
        }
        
        if selectedType == .income {
            return true
        }
        
        if showContributionSection {
            guard !contributions.isEmpty else { return false }
            
            for contribution in contributions {
                if contribution.payerID == nil { return false }
                guard let amount = decimalFromString(contribution.amountText), amount > 0 else { return false }
            }
            
            return true
        } else {
            return defaultPayer != nil
        }
    }
    
    private func getPayerName(for index: Int) -> String {
        if let payerID = contributions[index].payerID,
           let payer = payers.first(where: { $0.id == payerID }) {
            return payer.name
        } else {
            return "選擇付款人"
        }
    }
    
    private func getPayerColor(for index: Int) -> String? {
        if let payerID = contributions[index].payerID,
           let payer = payers.first(where: { $0.id == payerID }) {
            return payer.colorHex
        }
        return nil
    }
    
    private func getAvailablePayers(for index: Int) -> [Payer] {
        let selectedPayerIDs = contributions
            .enumerated()
            .filter { $0.offset != index }
            .compactMap { $0.element.payerID }
        
        let allSelectedIDs = Set(selectedPayerIDs)
        
        return payers.filter { payer in
            !allSelectedIDs.contains(payer.id)
        }
    }
    
    private var defaultPayer: Payer? {
        payers.first { $0.isDefault } ?? payers.first
    }
    
    // MARK: - Setup Methods
    
    private func setupInitialData() {
        if let tx = transaction {
            currentTransaction = tx
            totalAmountText = decimalToString(tx.totalAmount)
            date = tx.date
            note = tx.note ?? ""
            selectedType = tx.type
            currencyCode = tx.currencyCode
            
            if let subID = tx.subcategoryID,
               let sub = subcategories.first(where: { $0.id == subID }) {
                selectedSubcategoryID = sub.id
                selectedParentID = sub.parentID
            }
            
            if tx.type == .expense && !tx.contributions.isEmpty {
                showContributionSection = true
                contributions = tx.contributions.map { contribution in
                    ContributionEntry(
                        payerID: contribution.payer.id,
                        amountText: decimalToString(contribution.amount),
                        isRemovable: true
                    )
                }
            } else {
                showContributionSection = false
                contributions = []
            }
        } else {
            showContributionSection = false
            contributions = []
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func handleTypeChange(_ newType: TransactionType) {
        selectedType = newType
        if newType == .income {
            showContributionSection = false
            contributions.removeAll()
        } else {
            showContributionSection = false
            contributions.removeAll()
        }
    }
    
    private func distributeEqually() {
        guard !contributions.isEmpty else { return }
        let total = totalAmountDecimal
        let count = Decimal(contributions.count)
        let share = (count > 0) ? (total / count) : 0
        let shareString = decimalToString(share)
        for i in contributions.indices {
            contributions[i].amountText = shareString
        }
        validateAmounts()
    }
    
    private func validateAmounts() {
        showAmountError = (distributedTotal != totalAmountDecimal)
    }
    
    private func save() {
        guard let totalAmount = decimalFromString(totalAmountText), totalAmount > 0 else {
            return
        }
        
        hideKeyboard()
        
        let transactionToSave: Transaction
        
        if let existingTransaction = currentTransaction {
            transactionToSave = existingTransaction
        } else {
            transactionToSave = Transaction(
                totalAmount: totalAmount,
                date: date,
                type: selectedType,
                currencyCode: currencyCode
            )
            context.insert(transactionToSave)
        }
        
        transactionToSave.totalAmount = totalAmount
        transactionToSave.date = date
        transactionToSave.note = note.isEmpty ? nil : note
        transactionToSave.type = selectedType
        transactionToSave.currencyCode = currencyCode
        transactionToSave.subcategoryID = selectedSubcategoryID
        
        for contribution in transactionToSave.contributions {
            context.delete(contribution)
        }
        transactionToSave.contributions.removeAll()
        
        if selectedType == .expense {
            if showContributionSection && !contributions.isEmpty {
                for contribution in contributions {
                    if let payerID = contribution.payerID,
                       let payer = payers.first(where: { $0.id == payerID }),
                       let amount = decimalFromString(contribution.amountText), amount > 0 {
                        let paymentContribution = PaymentContribution(
                            amount: amount,
                            payer: payer,
                            transaction: transactionToSave
                        )
                        transactionToSave.contributions.append(paymentContribution)
                    }
                }
                
                let distributedTotal = transactionToSave.contributions.reduce(0) { $0 + $1.amount }
                if distributedTotal < totalAmount, let defaultPayer = defaultPayer {
                    let remainingAmount = totalAmount - distributedTotal
                    let remainingContribution = PaymentContribution(
                        amount: remainingAmount,
                        payer: defaultPayer,
                        transaction: transactionToSave
                    )
                    transactionToSave.contributions.append(remainingContribution)
                }
            } else {
                if let defaultPayer = defaultPayer {
                    let paymentContribution = PaymentContribution(
                        amount: totalAmount,
                        payer: defaultPayer,
                        transaction: transactionToSave
                    )
                    transactionToSave.contributions.append(paymentContribution)
                }
            }
        }
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("保存交易時出錯: \(error)")
        }
    }
    
    private func deleteConfirmed() {
        guard let transactionToDelete = currentTransaction else {
            dismiss()
            return
        }
        
        context.delete(transactionToDelete)
        
        do {
            try context.save()
            dismiss()
        } catch {
            print("刪除交易時出錯: \(error)")
        }
    }
    
    private func categoryPath(parentID: UUID?, subID: UUID?) -> String {
        if let p = parentID, let parent = categories.first(where: { $0.id == p }) {
            if let s = subID, let sub = subcategories.first(where: { $0.id == s }) {
                return "\(parent.name) / \(sub.name)"
            } else {
                return parent.name
            }
        } else {
            return langManager.localized("form_none")
        }
    }
    
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
    
    private func decimalFromString(_ text: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.number(from: text)?.decimalValue
    }
    
    private func decimalToString(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
    
    private func formatCurrency(amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
    
    private func currencySymbol(for code: String) -> String {
        let locale = Locale.availableIdentifiers
            .map { Locale(identifier: $0) }
            .first { $0.currencyCode == code } ?? Locale.current
        return locale.currencySymbol ?? code
    }
}
