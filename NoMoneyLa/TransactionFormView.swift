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

// MARK: - ParticipantEntry (參與者選擇暫存用)
struct ParticipantEntry: Identifiable {
    let id = UUID()
    let payer: Payer
    var isParticipating: Bool
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
    
    // ✅ 新增：參與者選擇相關狀態
    @State private var participantEntries: [ParticipantEntry] = []
    @State private var showParticipantSelection = false
    @State private var assignedPayersForCategory: [Payer] = []
    
    // ✅ 新增：用於顯示分攤警告的狀態
    @State private var showContributionMismatchAlert = false
    @State private var contributionDifference: Decimal = 0
    @State private var allowSaveAnyway = false
    
    // ✅ 新增：收入交易收款人ID
    @State private var selectedIncomePayerID: UUID? = nil
    
    // ✅ 修改：分攤模式狀態 - 默認為 .simple（一人支付全部）
    @State private var contributionMode: ContributionMode = .simple  // 默認一人支付全部
    
    // ✅ 新增：付款人選擇相關狀態
    @State private var showPayerSelectionForNew = false
    @State private var selectedPayerForNew: Payer? = nil
    
    private let currencies = ["HKD", "USD", "JPY"]
    
    enum Field {
        case totalAmount, note
    }
    
    enum ContributionMode {
        case simple      // 一人支付全額（默認）
        case detailed    // 多人分攤支付
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
                            // ✅ 修正：當總金額改變時，更新簡化模式嘅支付金額
                            .onChange(of: totalAmountText) { oldValue, newValue in
                                updateContributionAmountsOnTotalChange()
                            }

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
                                ForEach(categories) { cat in
                                    Button(action: {
                                        hideKeyboard()
                                        selectedParentID = cat.id
                                        // 自動選擇該分類下的「未分類」子分類
                                        if let uncategorizedSub = subcategories.first(where: {
                                            $0.parentID == cat.id && $0.name == langManager.localized("uncategorized_label")
                                        }) {
                                            selectedSubcategoryID = uncategorizedSub.id
                                        }
                                        
                                        // ✅ 更新：當選擇分類時，更新該分類的已分配付款人及參與者
                                        updateAssignedPayersForCategory(cat)
                                        
                                        // ✅ 更新：重置收入收款人選擇（如果切換分類）
                                        if selectedType == .income {
                                            selectedIncomePayerID = nil
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
                                        .foregroundColor(.primary)
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
                        .onChange(of: selectedParentID) { oldValue, newParent in
                            handleParentCategoryChange(oldValue: oldValue, newParent: newParent)
                        }
                    } else {
                        HStack {
                            Text(categoryPath(parentID: selectedParentID, subID: selectedSubcategoryID))
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                
                // ✅ 新增：參與者選擇區域
                if selectedType == .expense {
                    Section(header: Text(langManager.localized("participants_section"))) {
                        if isEditing {
                            Button {
                                showParticipantSelection = true
                            } label: {
                                HStack {
                                    Image(systemName: "person.2")
                                        .foregroundColor(.blue)
                                    Text(langManager.localized("select_participants"))
                                    Spacer()
                                    Text("\(selectedParticipantCount)人")
                                        .foregroundColor(.secondary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // 顯示已選擇的參與者預覽
                            if !selectedParticipantIDs.isEmpty {
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 8) {
                                        ForEach(participantEntries.filter { $0.isParticipating }) { entry in
                                            ParticipantChip(payer: entry.payer)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                }
                            }
                        } else {
                            // 查看模式：顯示參與者
                            if !participantEntries.isEmpty {
                                let participating = participantEntries.filter { $0.isParticipating }
                                if participating.isEmpty {
                                    Text(langManager.localized("no_participants"))
                                        .foregroundColor(.secondary)
                                } else {
                                    ScrollView(.horizontal, showsIndicators: false) {
                                        HStack(spacing: 8) {
                                            ForEach(participating) { entry in
                                                ParticipantChip(payer: entry.payer)
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                }
                            }
                        }
                    }
                    
                    // ✅ 修改：支付方式選擇
                    Section(header: Text("支付方式")) {
                        if isEditing {
                            VStack(alignment: .leading, spacing: 12) {
                                // 支付方式選擇
                                Picker("", selection: $contributionMode) {
                                    Text("一人支付全額（默認）").tag(ContributionMode.simple)
                                    Text("多人分攤支付").tag(ContributionMode.detailed)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: contributionMode) { newMode in
                                    handleContributionModeChange(newMode)
                                }
                                
                                // 說明文字
                                Text(getContributionModeDescription())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        } else {
                            // 查看模式
                            HStack {
                                Text("支付方式")
                                Spacer()
                                Text(contributionMode == .simple ? "一人支付全額" : "多人分攤支付")
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // ✅ 修改：支付詳情（根據模式顯示）
                    if contributionMode == .simple {
                        Section(header: Text("支付詳情")) {
                            if isEditing {
                                // 簡化模式：選擇誰支付了全額
                                Menu {
                                    ForEach(getAvailablePayersForPayment()) { payer in
                                        Button(action: {
                                            hideKeyboard()
                                            setSinglePayerPayment(payer)
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                    .frame(width: 8, height: 8)
                                                Text(payer.name)
                                                if contributions.count == 1 && contributions.first?.payerID == payer.id {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                } label: {
                                    HStack {
                                        if let payerID = contributions.first?.payerID,
                                           let payer = payers.first(where: { $0.id == payerID }) {
                                            Circle()
                                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                .frame(width: 12, height: 12)
                                            Text(payer.name)
                                                .foregroundColor(.primary)
                                        } else {
                                            Text("選擇支付人")
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.down")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .onTapGesture {
                                    hideKeyboard()
                                }
                                
                                // 顯示支付金額（自動設置為交易全額）
                                if let contribution = contributions.first,
                                   let amount = decimalFromString(contribution.amountText),
                                   amount > 0 {
                                    HStack {
                                        Text("支付金額")
                                        Spacer()
                                        Text(formatCurrency(amount: amount, code: currencyCode))
                                            .foregroundColor(.blue)
                                            .bold()
                                    }
                                    .padding(.top, 8)
                                }
                            } else {
                                // 查看模式
                                if let contribution = contributions.first,
                                   let payerID = contribution.payerID,
                                   let payer = payers.first(where: { $0.id == payerID }),
                                   let amount = decimalFromString(contribution.amountText) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Circle()
                                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                .frame(width: 12, height: 12)
                                            Text(payer.name)
                                                .font(.body)
                                            Spacer()
                                            Text("支付全額")
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        HStack {
                                            Text("支付金額")
                                            Spacer()
                                            Text(formatCurrency(amount: amount, code: currencyCode))
                                                .font(.headline)
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        // ✅ 修改：詳細模式 - 不自動列出所有付款人
                        Section(header: HStack {
                            Text("分攤支付詳情")
                            Spacer()
                            if isEditing && !contributions.isEmpty {
                                Button(action: {
                                    hideKeyboard()
                                    calculateRemainingDistribution()
                                }) {
                                    Text("自動分配剩餘金額")
                                        .font(.caption)
                                }
                            }
                        }) {
                            if isEditing {
                                // ✅ 修改：如果冇付款記錄，顯示添加按鈕
                                if contributions.isEmpty {
                                    VStack(spacing: 16) {
                                        Button(action: {
                                            hideKeyboard()
                                            showPayerSelectionForNew = true
                                        }) {
                                            HStack {
                                                Image(systemName: "plus.circle.fill")
                                                    .foregroundColor(.accentColor)
                                                    .font(.title2)
                                                Text("添加付款人")
                                                    .font(.headline)
                                                    .foregroundColor(.primary)
                                                Spacer()
                                                Image(systemName: "chevron.right")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                            }
                                            .padding(.vertical, 12)
                                            .padding(.horizontal, 16)
                                            .background(Color.accentColor.opacity(0.1))
                                            .cornerRadius(10)
                                        }
                                        
                                        Text("開始記錄誰支付了多少金額")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                } else {
                                    // 現有付款記錄列表
                                    ForEach(0..<contributions.count, id: \.self) { index in
                                        HStack(spacing: 12) {
                                            Menu {
                                                ForEach(getAvailablePayers(for: index)) { payer in
                                                    Button(action: {
                                                        hideKeyboard()
                                                        contributions[index].payerID = payer.id
                                                        updateContributionAmounts()
                                                    }) {
                                                        HStack {
                                                            Circle()
                                                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                                .frame(width: 8, height: 8)
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
                                    
                                    // ✅ 修改：添加付款人按鈕（永遠顯示）
                                    Button(action: {
                                        hideKeyboard()
                                        if canAddNewContribution() {
                                            showPayerSelectionForNew = true
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(canAddNewContribution() ? .accentColor : .gray)
                                            Text("添加付款人")
                                                .foregroundColor(canAddNewContribution() ? .primary : .gray)
                                        }
                                    }
                                    .disabled(!canAddNewContribution())
                                    .padding(.top, 8)
                                }
                                
                                if !contributions.isEmpty {
                                    HStack {
                                        Text("支付總額")
                                            .font(.caption)
                                        Spacer()
                                        
                                        // 改進：根據差異顯示不同顏色
                                        let totalColor = getTotalColor()
                                        let diffText = getDifferenceText()
                                        
                                        Text("\(formatCurrency(amount: distributedTotal, code: currencyCode)) / \(formatCurrency(amount: totalAmountDecimal, code: currencyCode))")
                                            .font(.caption)
                                            .foregroundColor(totalColor)
                                        
                                        if !diffText.isEmpty {
                                            Text("(\(diffText))")
                                                .font(.caption2)
                                                .foregroundColor(totalColor)
                                        }
                                    }
                                    .padding(.top, 8)
                                }
                                
                                if showAmountError {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.orange)
                                        Text("支付金額不匹配")
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.top, 4)
                                }
                            } else {
                                // 查看模式
                                if contributions.isEmpty {
                                    Text("無支付記錄")
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
                                        Text("支付總額")
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

                // ✅ 新增：收入交易收款人選擇
                if selectedType == .income {
                    Section(header: Text(langManager.localized("income_recipient_section"))) {
                        if isEditing {
                            Menu {
                                // ✅ 收入交易只能選擇已分配給當前分類的付款人
                                let availablePayersForIncome = getAvailablePayersForIncome()
                                
                                if availablePayersForIncome.isEmpty {
                                    Text("當前分類未分配付款人")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("選擇收款人（只能選擇已分配給此分類的付款人）")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    
                                    ForEach(availablePayersForIncome) { payer in
                                        Button(action: {
                                            hideKeyboard()
                                            selectedIncomePayerID = payer.id
                                        }) {
                                            HStack {
                                                Circle()
                                                    .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                    .frame(width: 8, height: 8)
                                                Text(payer.name)
                                                if selectedIncomePayerID == payer.id {
                                                    Spacer()
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack {
                                    if let payerID = selectedIncomePayerID,
                                       let payer = payers.first(where: { $0.id == payerID }) {
                                        Circle()
                                            .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                            .frame(width: 12, height: 12)
                                        Text(payer.name)
                                            .foregroundColor(.primary)
                                    } else {
                                        Text(langManager.localized("select_income_recipient"))
                                            .foregroundColor(.secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .onTapGesture {
                                hideKeyboard()
                            }
                            
                            // ✅ 顯示付款人限制提示
                            if let parentID = selectedParentID,
                               let category = categories.first(where: { $0.id == parentID }) {
                                let assignedPayers = category.assignedPayers(in: context)
                                if !assignedPayers.isEmpty {
                                    Text("只能選擇已分配給「\(category.name)」的付款人")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                        } else {
                            // 查看模式
                            if let payerID = selectedIncomePayerID,
                               let payer = payers.first(where: { $0.id == payerID }) {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 12, height: 12)
                                    Text(payer.name)
                                    Spacer()
                                    Text(langManager.localized("income_recipient_label"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            } else if let defaultPayer = getDefaultIncomePayer() {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: defaultPayer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 12, height: 12)
                                    Text(defaultPayer.name)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(langManager.localized("income_recipient_label"))（預設）")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
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
                            saveWithValidation()
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
            .sheet(isPresented: $showParticipantSelection) {
                ParticipantSelectionSheet(
                    assignedPayers: assignedPayersForCategory,
                    allPayers: payers,
                    selectedParticipantIDs: selectedParticipantIDs,
                    onSave: { selectedIDs in
                        updateParticipantEntries(selectedIDs: selectedIDs)
                        // 更新支付設置
                        updatePaymentSetup()
                    }
                )
                .environment(\.modelContext, context)
            }
            .sheet(isPresented: $showPayerSelectionForNew) {
                // ✅ 新增：付款人選擇彈窗
                PayerSelectionSheetForNew(
                    availablePayers: getAvailablePayersForNewContribution(),
                    onSelect: { payer in
                        addNewContribution(payer: payer)
                    }
                )
                .environment(\.modelContext, context)
            }
            .alert(langManager.localized("form_delete_title"), isPresented: $showDeleteAlert) {
                Button(langManager.localized("form_cancel"), role: .cancel) {}
                Button(langManager.localized("form_delete"), role: .destructive) { deleteConfirmed() }
            } message: {
                Text(langManager.localized("form_delete_message"))
            }
            .alert("支付金額不匹配", isPresented: $showContributionMismatchAlert) {
                Button("取消", role: .cancel) {
                    allowSaveAnyway = false
                }
                Button("修復並保存") {
                    fixContributionAmountsAndSave()
                }
                Button("仍然保存", role: .destructive) {
                    allowSaveAnyway = true
                    saveTransaction()
                }
            } message: {
                Text(getContributionMismatchMessage())
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
            // ✅ 如果冇選擇分類，顯示「未分類」而非「無」
            return langManager.localized("uncategorized_label")
        }
    }
    
    private var selectedSubcategoryName: String {
        if selectedParentID == nil {
            // ✅ 如果冇選擇父分類，顯示「未分類」而非「請先選擇父分類」
            return langManager.localized("uncategorized_label")
        } else if let subID = selectedSubcategoryID,
                  let sub = subcategories.first(where: { $0.id == subID }) {
            return sub.name
        } else {
            return langManager.localized("uncategorized_label")
        }
    }
    
    private var totalAmountDecimal: Decimal {
        decimalFromString(totalAmountText) ?? 0
    }
    
    private var distributedTotal: Decimal {
        contributions.reduce(Decimal(0)) { total, contribution in
            total + (decimalFromString(contribution.amountText) ?? 0)
        }
    }
    
    // ✅ 新增：已選擇的參與者ID集合
    private var selectedParticipantIDs: Set<UUID> {
        Set(participantEntries.filter { $0.isParticipating }.map { $0.payer.id })
    }
    
    // ✅ 新增：已選擇的參與者數量
    private var selectedParticipantCount: Int {
        selectedParticipantIDs.count
    }
    
    private var isValid: Bool {
        guard let total = decimalFromString(totalAmountText), total > 0 else { return false }
        
        // ✅ 移除分類檢查，因為現在總會有分類（預設未分類）
        if selectedType == .income {
            // ✅ 收入交易：必須有收款人
            return true // 允許保存，即使未選擇收款人（會使用默認收款人）
        }
        
        // ✅ 支出交易：必須至少有一個參與者
        if selectedParticipantIDs.isEmpty {
            return false
        }
        
        // ✅ 簡化模式：必須有一個付款人
        if contributionMode == .simple {
            guard !contributions.isEmpty else { return false }
            guard contributions.first?.payerID != nil else { return false }
            return true
        }
        
        // ✅ 詳細模式：檢查每個分攤項
        if contributionMode == .detailed {
            guard !contributions.isEmpty else { return false }
            
            for contribution in contributions {
                if contribution.payerID == nil { return false }
                guard let amount = decimalFromString(contribution.amountText), amount > 0 else { return false }
            }
            
            return true
        }
        
        return false
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
    
    // ✅ 修改：只顯示當前分類已分配的付款人
    private func getAvailablePayers(for index: Int) -> [Payer] {
        // 1. 優先使用已選擇的參與者（按 order 排序）
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }  // ✅ 確保排序
        
        if !participatingPayers.isEmpty {
            // 只顯示參與者中的付款人
            var availableFromParticipants = participatingPayers
            
            // 排除已被其他分攤項選中的付款人
            let selectedPayerIDs = contributions
                .enumerated()
                .filter { $0.offset != index }
                .compactMap { $0.element.payerID }
            
            let selectedIDsSet = Set(selectedPayerIDs)
            
            return availableFromParticipants.filter { !selectedIDsSet.contains($0.id) }
        }
        
        // 2. 如果沒有參與者，使用分類的已分配付款人（按 order 排序）
        var availablePayers: [Payer]
        
        if !assignedPayersForCategory.isEmpty {
            availablePayers = assignedPayersForCategory.sorted { $0.order < $1.order }
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            if !assignedPayers.isEmpty {
                availablePayers = assignedPayers.sorted { $0.order < $1.order }
            } else {
                // 3. 如果分類沒有分配付款人，使用所有付款人（按 order 排序）
                availablePayers = payers.sorted { $0.order < $1.order }
            }
        } else {
            // 4. 沒有選擇分類，使用所有付款人（按 order 排序）
            availablePayers = payers.sorted { $0.order < $1.order }
        }
        
        // 排除已被其他分攤項選中的付款人
        let selectedPayerIDs = contributions
            .enumerated()
            .filter { $0.offset != index }
            .compactMap { $0.element.payerID }
        
        let selectedIDsSet = Set(selectedPayerIDs)
        
        return availablePayers.filter { !selectedIDsSet.contains($0.id) }
    }
    
    // ✅ 新增：獲取可用的支付人（用於簡化模式）
    private func getAvailablePayersForPayment() -> [Payer] {
        // 簡化模式：只能選擇參與者
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }  // ✅ 確保排序
        
        if !participatingPayers.isEmpty {
            return participatingPayers
        }
        
        // 如果沒有參與者，使用已分配付款人
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.sorted { $0.order < $1.order }  // ✅ 確保排序
        }
        
        // 最後備選：所有付款人
        return payers
    }
    
    // ✅ 新增：獲取收入交易可用的付款人
    private func getAvailablePayersForIncome() -> [Payer] {
        // 收入交易只能選擇已分配給當前分類的付款人
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.sorted { $0.order < $1.order }  // ✅ 確保排序
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            return assignedPayers.sorted { $0.order < $1.order }  // ✅ 確保排序
        } else {
            // 沒有選擇分類，顯示所有付款人
            return payers.sorted { $0.order < $1.order }  // ✅ 確保排序
        }
    }
    
    // ✅ 新增：獲取新付款人可用的付款人
    private func getAvailablePayersForNewContribution() -> [Payer] {
        // 獲取可用的付款人（包括參與者和已分配付款人）
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        var availablePayers: [Payer]
        
        if !participatingPayers.isEmpty {
            availablePayers = participatingPayers
        } else if !assignedPayersForCategory.isEmpty {
            availablePayers = assignedPayersForCategory.sorted { $0.order < $1.order }
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            availablePayers = assignedPayers.isEmpty ? payers.sorted { $0.order < $1.order } : assignedPayers.sorted { $0.order < $1.order }
        } else {
            availablePayers = payers.sorted { $0.order < $1.order }
        }
        
        // 排除已被選中的付款人
        let selectedPayerIDs = contributions.compactMap { $0.payerID }
        let selectedIDsSet = Set(selectedPayerIDs)
        
        return availablePayers.filter { !selectedIDsSet.contains($0.id) }
    }
    
    private var defaultPayer: Payer? {
        // ✅ 修改：優先使用當前分類已分配付款人中的第一個
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.first
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            if !assignedPayers.isEmpty {
                return assignedPayers.first
            }
        }
        
        // 如果沒有已分配的付款人，使用預設付款人或第一個付款人
        return payers.first { $0.isDefault } ?? payers.first
    }
    
    // ✅ 新增：獲取收入交易的默認收款人
    private func getDefaultIncomePayer() -> Payer? {
        // 優先使用已分配付款人中的第一個
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.first
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            if !assignedPayers.isEmpty {
                return assignedPayers.first
            }
        }
        
        // 如果沒有已分配的付款人，使用預設付款人
        return payers.first { $0.isDefault } ?? payers.first
    }
    
    // ✅ 修改：檢查是否可以添加新的分攤項
    private func canAddNewContribution() -> Bool {
        // 詳細模式才需要檢查
        guard contributionMode == .detailed else { return false }
        
        // 檢查是否還有可用的付款人
        let availablePayers = getAvailablePayersForNewContribution()
        return !availablePayers.isEmpty
    }
    
    // ✅ 新增：獲取支付模式描述
    private func getContributionModeDescription() -> String {
        switch contributionMode {
        case .simple:
            return "通常情況下，由一個人先墊付全額，其他人之後還錢。（默認模式）"
        case .detailed:
            return "多人即時分攤支付，每人支付自己部分。"
        }
    }
    
    // ✅ 新增：更新當前分類的已分配付款人
    private func updateAssignedPayersForCategory(_ category: Category) {
        let assignedPayers = category.assignedPayers(in: context)
        
        // ✅ 修改：按 order 排序
        assignedPayersForCategory = assignedPayers.sorted { $0.order < $1.order }
        
        // ✅ 修改：更新參與者條目
        updateParticipantEntriesForNewCategory(assignedPayersForCategory)
    }
    
    // ✅ 新增：從已分配付款人更新參與者條目
    private func updateParticipantEntriesFromAssignedPayers() {
        // ✅ 修改：按 order 排序後再創建條目
        participantEntries = assignedPayersForCategory
            .sorted { $0.order < $1.order }
            .map { payer in
                ParticipantEntry(payer: payer, isParticipating: true)
            }
        updatePaymentSetup()
    }
    
    // ✅ 新增：為新分類更新參與者條目
    private func updateParticipantEntriesForNewCategory(_ newAssignedPayers: [Payer]) {
        // 創建新嘅參與者條目
        var newParticipantEntries: [ParticipantEntry] = []
        
        // 遍歷新分類嘅付款人
        for payer in newAssignedPayers {
            // 檢查呢個付款人是否已經喺舊嘅參與者列表中
            if let existingEntry = participantEntries.first(where: { $0.payer.id == payer.id }) {
                // 保留原有嘅參與狀態
                newParticipantEntries.append(existingEntry)
            } else {
                // 新付款人，默認參與
                newParticipantEntries.append(ParticipantEntry(payer: payer, isParticipating: true))
            }
        }
        
        // 設置新嘅參與者條目
        participantEntries = newParticipantEntries
        
        // ✅ 新增：重置支付詳情
        resetPaymentDetailsForNewCategory()
    }
    
    // ✅ 修改：更新參與者條目（根據選擇的ID）
    private func updateParticipantEntries(selectedIDs: Set<UUID>) {
        for i in participantEntries.indices {
            participantEntries[i].isParticipating = selectedIDs.contains(participantEntries[i].payer.id)
        }
        // 更新支付設置
        updatePaymentSetup()
        
        // ✅ 修改：詳細模式唔再自動重新計算
        // 保持用戶控制權，唔好自動填寫金額
    }
    
    // ✅ 修改：更新支付設置 - 默認使用簡化模式
    private func updatePaymentSetup() {
        // ✅ 新增：檢查當前支付記錄中嘅付款人是否屬於當前分類
        cleanupInvalidContributions()
        
        let participatingCount = selectedParticipantCount
        
        // ✅ 修改：默認使用簡化模式（一人支付全部）
        if participatingCount == 0 {
            // 沒有人參與：清空支付記錄
            contributionMode = .simple
            contributions = []
        } else {
            // ✅ 修改：保持當前模式，但默認為簡化模式
            // 唔會自動跳去詳細模式，俾用戶自己選擇
            if contributionMode == .simple {
                setupSinglePayerPayment()
            } else if contributionMode == .detailed {
                // ✅ 修改：詳細模式唔再自動添加所有參與者
                // 保持現有支付記錄，唔做任何自動添加
            }
        }
    }
    
    // ✅ 修正：設置單人支付 - 改進邏輯
    private func setupSinglePayerPayment() {
        // 獲取當前分類嘅參與者
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        if let firstParticipant = participatingPayers.first {
            // 設置第一個參與者支付全額
            contributions = [
                ContributionEntry(
                    payerID: firstParticipant.id,
                    amountText: "",
                    isRemovable: false
                )
            ]
        } else {
            // 冇參與者，使用默認付款人
            if let defaultPayer = defaultPayer {
                contributions = [
                    ContributionEntry(
                        payerID: defaultPayer.id,
                        amountText: "",
                        isRemovable: false
                    )
                ]
            } else {
                // 冇默認付款人，清空支付記錄
                contributions = []
            }
        }
    }
    
    // ✅ 修改：設置詳細支付（不再自動添加所有參與者）
    private func setupDetailedPayments() {
        // ✅ 修改：唔再清空現有支付記錄
        // 保持用戶可能已經設置嘅支付記錄
        
        // 如果原本係簡化模式，保留現有嘅單一付款記錄
        // 如果原本就係詳細模式，保持現狀
        
        // 唔再做任何自動添加
        // 等用戶自己手動添加付款人
    }
    
    // ✅ 修改：處理支付模式變化
    private func handleContributionModeChange(_ newMode: ContributionMode) {
        hideKeyboard()
        
        if newMode == .simple {
            // 轉為簡化模式
            setupSinglePayerPayment()
        } else {
            // 轉為詳細模式
            // ✅ 修改：唔再自動設置詳細支付，保持現有記錄
            // 如果現有記錄為空，唔做任何嘢，等用戶自己添加
        }
    }
    
    // ✅ 新增：添加新付款人
    private func addNewContribution(payer: Payer) {
        hideKeyboard()
        
        // 檢查是否已選擇該付款人
        let alreadySelected = contributions.contains { $0.payerID == payer.id }
        guard !alreadySelected else {
            showPayerSelectionForNew = false
            return
        }
        
        // 添加新付款記錄（金額空白）
        contributions.append(ContributionEntry(
            payerID: payer.id,
            amountText: "",  // ✅ 保持空白，等用戶自己輸入
            isRemovable: true
        ))
        
        selectedPayerForNew = nil
        showPayerSelectionForNew = false
        
        // 驗證金額
        validateAmounts()
    }
    
    // ✅ 新增：設置單人支付
    private func setSinglePayerPayment(_ payer: Payer) {
        contributions = [
            ContributionEntry(
                payerID: payer.id,
                amountText: "",
                isRemovable: false
            )
        ]
    }
    
    // ✅ 修改：計算平均分配
    private func calculateEqualDistribution() {
        let participatingCount = selectedParticipantCount
        guard participatingCount > 0, totalAmountDecimal > 0 else { return }
        
        // 計算每人應付金額
        let total = totalAmountDecimal
        let share = total / Decimal(participatingCount)
        let shareString = decimalToString(share)
        
        // 只更新未設置金額或金額為0嘅分攤項
        var updatedCount = 0
        for i in contributions.indices {
            if let currentAmount = decimalFromString(contributions[i].amountText), currentAmount > 0 {
                // 保留已輸入嘅金額
                continue
            } else {
                contributions[i].amountText = shareString
                updatedCount += 1
            }
        }
        
        // 如果全部都係空白，更新全部
        if updatedCount == 0 && !contributions.isEmpty {
            for i in contributions.indices {
                contributions[i].amountText = shareString
            }
        }
        
        // 處理四捨五入誤差
        adjustRoundingErrors()
        validateAmounts()
    }
    
    // ✅ 修正：自動分配剩餘金額 - 簡單直接邏輯
    private func calculateRemainingDistribution() {
        guard !contributions.isEmpty else { return }
        
        let total = totalAmountDecimal
        let currentTotal = distributedTotal
        let remaining = total - currentTotal
        
        // 如果冇剩餘金額或者差異好細，唔使做任何嘢
        guard abs(remaining) > Decimal(0.01) else { return }
        
        // **核心邏輯：將剩餘金額分配俾金額為0或空白嘅項目**
        
        // 1. 找出金額為0或空白嘅項目索引
        var zeroOrEmptyIndices: [Int] = []
        
        for i in contributions.indices {
            if let amount = decimalFromString(contributions[i].amountText) {
                if amount <= 0 {
                    zeroOrEmptyIndices.append(i)
                }
            } else {
                // 金額為空字串
                zeroOrEmptyIndices.append(i)
            }
        }
        
        // 2. 情況A：有空白/0金額項目
        if !zeroOrEmptyIndices.isEmpty {
            // 將剩餘金額平均分配俾呢啲項目
            let share = remaining / Decimal(zeroOrEmptyIndices.count)
            let shareString = decimalToString(share)
            
            for index in zeroOrEmptyIndices {
                contributions[index].amountText = shareString
            }
        }
        // 3. 情況B：全部項目都有金額（>0）
        else {
            // 將剩餘金額平均分配俾所有人
            let share = remaining / Decimal(contributions.count)
            
            for i in contributions.indices {
                if let currentAmount = decimalFromString(contributions[i].amountText) {
                    let newAmount = currentAmount + share
                    contributions[i].amountText = decimalToString(newAmount)
                }
            }
        }
        
        // 4. 最後檢查並修正四捨五入誤差
        adjustRoundingErrors()
        validateAmounts()
    }
    
    // ✅ 新增：處理四捨五入誤差
    private func adjustRoundingErrors() {
        guard contributionMode == .detailed else { return }
        
        let total = totalAmountDecimal
        let currentTotal = distributedTotal
        let difference = total - currentTotal
        
        // 如果誤差好細（小於 0.01），忽略
        if abs(difference) < Decimal(0.01) {
            return
        }
        
        // 將誤差加到第一個分攤項度
        if !contributions.isEmpty, let firstAmount = decimalFromString(contributions[0].amountText) {
            let adjustedAmount = firstAmount + difference
            contributions[0].amountText = decimalToString(adjustedAmount)
        }
    }
    
    // ✅ 新增：當總金額改變時更新分攤
    private func updateContributionAmountsOnTotalChange() {
        guard !contributions.isEmpty else { return }
        
        if contributionMode == .simple {
            // 簡化模式：更新單一支付金額
            if contributions.count == 1 {
                contributions[0].amountText = totalAmountText
            }
        }
        // 詳細模式唔會自動更新，保持用戶控制權
        // 用戶可以自己點擊「自動分配剩餘金額」
        
        validateAmounts()
    }
    
    // ✅ 新增：更新分攤金額
    private func updateContributionAmounts() {
        // 確保每個分攤項都有合理的金額
        for i in contributions.indices {
            if contributions[i].amountText.isEmpty || decimalFromString(contributions[i].amountText) == 0 {
                // 如果金額為空或0，設置為平均份額
                let participatingCount = max(selectedParticipantCount, 1)
                let share = totalAmountDecimal / Decimal(participatingCount)
                contributions[i].amountText = decimalToString(share)
            }
        }
        validateAmounts()
    }
    
    // ✅ 新增：獲取總額顏色
    private func getTotalColor() -> Color {
        let difference = abs(distributedTotal - totalAmountDecimal)
        
        if difference <= Decimal(0.01) {
            return .green
        } else if difference <= Decimal(1.00) {
            return .orange
        } else {
            return .red
        }
    }
    
    // ✅ 新增：獲取差異文字
    private func getDifferenceText() -> String {
        let difference = distributedTotal - totalAmountDecimal
        
        if abs(difference) <= Decimal(0.01) {
            return ""
        } else if difference > 0 {
            let diffStr = formatCurrency(amount: difference, code: currencyCode)
            return "+\(diffStr)"
        } else {
            let diffStr = formatCurrency(amount: abs(difference), code: currencyCode)
            return "-\(diffStr)"
        }
    }
    
    // ✅ 新增：清理無效嘅支付記錄（付款人不屬於當前分類）
    private func cleanupInvalidContributions() {
        guard !contributions.isEmpty else { return }
        
        // 獲取當前分類嘅付款人ID集合
        let validPayerIDs = Set(assignedPayersForCategory.map { $0.id })
        
        // 如果冇已分配付款人，使用所有付款人
        let allPayerIDs = validPayerIDs.isEmpty ? Set(payers.map { $0.id }) : validPayerIDs
        
        // 過濾無效嘅支付記錄
        contributions = contributions.filter { entry in
            if let payerID = entry.payerID {
                return allPayerIDs.contains(payerID)
            }
            return true // 冇選擇付款人嘅記錄保留
        }
        
        // 如果支付記錄被清空，重新設置
        if contributions.isEmpty {
            setupPaymentBasedOnParticipants()
        }
    }
    
    // ✅ 修改：根據參與者設置支付 - 默認使用簡化模式
    private func setupPaymentBasedOnParticipants() {
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        if participatingPayers.isEmpty {
            contributions = []
            return
        }
        
        // ✅ 修改：無論參與人數多少，默認使用簡化模式
        contributionMode = .simple
        contributions = [
            ContributionEntry(
                payerID: participatingPayers[0].id,  // 選擇第一個參與者
                amountText: "",
                isRemovable: false
            )
        ]
    }
    
    // ✅ 修改：重置支付詳情（當分類變更時） - 默認使用簡化模式
    private func resetPaymentDetailsForNewCategory() {
        // 1. 清除所有現有支付記錄
        contributions.removeAll()
        
        // 2. 重置參與者選擇（如果已有選擇）
        if !participantEntries.isEmpty {
            // 只保留仍然在 assignedPayersForCategory 中嘅付款人
            for i in participantEntries.indices {
                let payerID = participantEntries[i].payer.id
                if assignedPayersForCategory.contains(where: { $0.id == payerID }) {
                    participantEntries[i].isParticipating = true
                } else {
                    participantEntries[i].isParticipating = false
                }
            }
        }
        
        // 3. 根據新分類重新設置支付
        // ✅ 修改：默認使用簡化模式
        contributionMode = .simple
        setupSinglePayerPayment()  // ✅ 這個方法已經修改為空白金額
    }
    
    // ✅ 新增：處理父分類變化
    private func handleParentCategoryChange(oldValue: UUID?, newParent: UUID?) {
        hideKeyboard()
        
        // 如果分類冇變，唔使做任何嘢
        guard oldValue != newParent else { return }
        
        DispatchQueue.main.async {
            if let newParent = newParent {
                // 當選擇父分類時，自動選擇「未分類」子分類
                if let uncategorizedSub = subcategories.first(where: {
                    $0.parentID == newParent && $0.name == langManager.localized("uncategorized_label")
                }) {
                    selectedSubcategoryID = uncategorizedSub.id
                }
                
                // ✅ 重要修改：更新已分配付款人及參與者
                if let category = categories.first(where: { $0.id == newParent }) {
                    updateAssignedPayersForCategory(category)
                }
                
                // ✅ 更新：重置收入收款人選擇
                if selectedType == .income {
                    selectedIncomePayerID = nil
                }
            } else {
                selectedSubcategoryID = nil
                assignedPayersForCategory = []
                participantEntries = []
                selectedIncomePayerID = nil
                
                // ✅ 新增：重置支付詳情
                contributions.removeAll()
                contributionMode = .simple
            }
        }
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
                selectedParentID = sub.parentID
                selectedSubcategoryID = sub.id
                
                // ✅ 更新：設置當前分類的已分配付款人
                if let category = categories.first(where: { $0.id == sub.parentID }) {
                    updateAssignedPayersForCategory(category)
                    
                    // ✅ 設置參與者選擇（優先使用交易記錄的參與者）
                    if !tx.participatingPayerIDs.isEmpty {
                        // 使用交易記錄的參與者
                        let selectedIDs = Set(tx.participatingPayerIDs)
                        updateParticipantEntries(selectedIDs: selectedIDs)
                    } else {
                        // 舊交易沒有參與者記錄，默認所有已分配付款人都參與
                        updateParticipantEntriesFromAssignedPayers()
                    }
                }
                
                // ✅ 新增：設置收入交易的收款人
                if tx.type == .income && !tx.contributions.isEmpty {
                    // 收入交易應該只有一個分攤（收款人）
                    if let contribution = tx.contributions.first {
                        selectedIncomePayerID = contribution.payer.id
                    }
                }
            } else {
                // ✅ 如果交易原本 subcategoryID 為 nil，設置為預設未分類
                setDefaultUncategorized()
            }
            
            // ✅ 修改：設置支付記錄
            if tx.type == .expense && !tx.contributions.isEmpty {
                contributions = tx.contributions.map { contribution in
                    ContributionEntry(
                        payerID: contribution.payer.id,
                        amountText: decimalToString(contribution.amount),  // ✅ 這裡應該保留原始金額
                        isRemovable: true
                    )
                }
                
                // ✅ 修改：簡化模式只檢查是否是單人支付
                if tx.contributions.count == 1 {
                    contributionMode = .simple
                } else {
                    contributionMode = .detailed
                }
            } else {
                // 新交易或沒有支付記錄
                // ✅ 修改：默認使用簡化模式
                contributionMode = .simple
                updatePaymentSetup()  // ✅ 這個方法調用 setupSinglePayerPayment()
            }
        } else {
            // ✅ 新增交易時，自動選擇預設「未分類」分類
            setDefaultUncategorized()
            
            selectedIncomePayerID = nil
            
            // ✅ 修改：設置默認支付模式為簡化模式
            contributionMode = .simple
            updatePaymentSetup()
        }
    }
    
    // ✅ 新方法：設置預設未分類分類
    private func setDefaultUncategorized() {
        if let defaultCategory = categories.first(where: { $0.isDefault }),
           let defaultSubcategory = subcategories.first(where: {
               $0.parentID == defaultCategory.id && $0.name == langManager.localized("uncategorized_label")
           }) {
            selectedParentID = defaultCategory.id
            selectedSubcategoryID = defaultSubcategory.id
            
            // ✅ 更新：設置預設分類的已分配付款人
            updateAssignedPayersForCategory(defaultCategory)
        } else if let firstCategory = categories.first {
            // 如果沒有預設分類，使用第一個分類
            selectedParentID = firstCategory.id
            if let firstSubcategory = subcategories.first(where: { $0.parentID == firstCategory.id }) {
                selectedSubcategoryID = firstSubcategory.id
            }
            
            // ✅ 更新：設置第一個分類的已分配付款人
            updateAssignedPayersForCategory(firstCategory)
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func handleTypeChange(_ newType: TransactionType) {
        selectedType = newType
        if newType == .income {
            // 收入交易：清空支付記錄
            contributions.removeAll()
        } else {
            // 支出交易：重新設置支付
            updatePaymentSetup()
        }
    }
    
    private func validateAmounts() {
        let difference = abs(distributedTotal - totalAmountDecimal)
        showAmountError = difference > Decimal(0.01)
    }
    
    // ✅ 改進：保存前驗證
    private func saveWithValidation() {
        guard let totalAmount = decimalFromString(totalAmountText), totalAmount > 0 else {
            return
        }
        
        hideKeyboard()
        
        // 確保總會有分類（如果未選擇，使用預設未分類）
        if selectedSubcategoryID == nil {
            setDefaultUncategorized()
        }
        
        // ✅ 檢查支付金額是否匹配
        let difference = abs(distributedTotal - totalAmount)
        
        if difference > Decimal(0.01) {
            // 顯示警告，讓用戶選擇
            contributionDifference = distributedTotal - totalAmount
            showContributionMismatchAlert = true
            return
        }
        
        // 如果沒有支付問題，直接保存
        saveTransaction()
    }
    
    // ✅ 新增：修復支付金額並保存
    private func fixContributionAmountsAndSave() {
        guard let totalAmount = decimalFromString(totalAmountText) else { return }
        
        if !contributions.isEmpty {
            let difference = totalAmount - distributedTotal
            
            if contributionMode == .simple {
                // 簡化模式：調整單一支付金額
                if contributions.count == 1 {
                    contributions[0].amountText = decimalToString(totalAmount)
                }
            } else {
                // 詳細模式：平均分配差異
                let perPersonAdjustment = difference / Decimal(contributions.count)
                let adjustmentString = decimalToString(perPersonAdjustment)
                
                for i in contributions.indices {
                    if let currentAmount = decimalFromString(contributions[i].amountText) {
                        let newAmount = currentAmount + perPersonAdjustment
                        contributions[i].amountText = decimalToString(newAmount)
                    }
                }
            }
        }
        
        saveTransaction()
    }
    
    private func saveTransaction() {
        guard let totalAmount = decimalFromString(totalAmountText), totalAmount > 0 else {
            return
        }
        
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
        transactionToSave.subcategoryID = selectedSubcategoryID // ✅ 總會有值
        
        // ✅ 保存參與者信息
        if selectedType == .expense {
            transactionToSave.participatingPayerIDs = Array(selectedParticipantIDs)
        } else {
            // 收入交易不需要參與者列表
            transactionToSave.participatingPayerIDs = []
        }
        
        // 清除舊的支付記錄
        for contribution in transactionToSave.contributions {
            context.delete(contribution)
        }
        transactionToSave.contributions.removeAll()
        
        if selectedType == .expense {
            // 保存支付記錄
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
            
            // 確保至少有一個支付記錄
            if transactionToSave.contributions.isEmpty {
                if let defaultPayer = defaultPayer {
                    let paymentContribution = PaymentContribution(
                        amount: totalAmount,
                        payer: defaultPayer,
                        transaction: transactionToSave
                    )
                    transactionToSave.contributions.append(paymentContribution)
                }
            }
        } else {
            // ✅ 新增：收入交易 - 添加收款人支付記錄
            let incomePayerID: UUID?
            
            // 優先使用用戶選擇的收款人
            if let payerID = selectedIncomePayerID {
                incomePayerID = payerID
            } else {
                // 如果未選擇收款人，使用默認收款人
                incomePayerID = getDefaultIncomePayer()?.id
            }
            
            if let payerID = incomePayerID,
               let payer = payers.first(where: { $0.id == payerID }) {
                // 收入交易：收款人收到全部金額
                let paymentContribution = PaymentContribution(
                    amount: totalAmount,
                    payer: payer,
                    transaction: transactionToSave
                )
                transactionToSave.contributions.append(paymentContribution)
            } else if let defaultPayer = getDefaultIncomePayer() {
                // 後備：使用默認付款人
                let paymentContribution = PaymentContribution(
                    amount: totalAmount,
                    payer: defaultPayer,
                    transaction: transactionToSave
                )
                transactionToSave.contributions.append(paymentContribution)
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
            return langManager.localized("uncategorized_label") // ✅ 顯示「未分類」而非「無」
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
    
    // ✅ 新增：獲取支付不匹配的警告信息
    private func getContributionMismatchMessage() -> String {
        let difference = abs(contributionDifference)
        let amountStr = formatCurrency(amount: difference, code: currencyCode)
        
        if contributionDifference > 0 {
            return "支付總額比交易金額多 \(amountStr)。\n\n建議修復支付金額以確保計算準確。"
        } else {
            return "支付總額比交易金額少 \(amountStr)。\n\n建議修復支付金額以確保計算準確。"
        }
    }
}

// MARK: - ParticipantChip
struct ParticipantChip: View {
    let payer: Payer
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                .frame(width: 8, height: 8)
            Text(payer.name)
                .font(.caption)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.blue.opacity(0.1))
        .cornerRadius(8)
    }
}

// MARK: - ParticipantSelectionSheet
struct ParticipantSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let assignedPayers: [Payer]
    let allPayers: [Payer]
    let selectedParticipantIDs: Set<UUID>
    let onSave: (Set<UUID>) -> Void
    
    @State private var tempSelectedIDs: Set<UUID> = []
    
    // ✅ 修改：確保 assignedPayers 按 order 排序
    private var sortedAssignedPayers: [Payer] {
        assignedPayers.sorted { $0.order < $1.order }
    }
    
    // ✅ 修改：otherPayers 按 order 排序
    private var sortedOtherPayers: [Payer] {
        allPayers
            .filter { payer in
                !assignedPayers.contains(where: { $0.id == payer.id })
            }
            .sorted { $0.order < $1.order }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 已分配付款人區
                if !sortedAssignedPayers.isEmpty {
                    Section("此分類嘅付款人") {
                        ForEach(sortedAssignedPayers) { payer in
                            payerRow(payer)
                        }
                    }
                }
                
                // 其他付款人區
                if !sortedOtherPayers.isEmpty {
                    Section("其他付款人") {
                        ForEach(sortedOtherPayers) { payer in
                            payerRow(payer)
                        }
                    }
                }
                
                // 統計信息
                Section {
                    HStack {
                        Text("已選擇")
                        Spacer()
                        Text("\(tempSelectedIDs.count)人")
                            .foregroundColor(.blue)
                    }
                }
            }
            .navigationTitle("選擇參與者")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        onSave(tempSelectedIDs)
                        dismiss()
                    }
                }
            }
            .onAppear {
                tempSelectedIDs = selectedParticipantIDs
            }
        }
    }
    
    private func payerRow(_ payer: Payer) -> some View {
        HStack {
            Circle()
                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                .frame(width: 12, height: 12)
            
            Text(payer.name)
            
            Spacer()
            
            if tempSelectedIDs.contains(payer.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.blue)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            toggleSelection(payer.id)
        }
    }
    
    private func toggleSelection(_ payerID: UUID) {
        if tempSelectedIDs.contains(payerID) {
            tempSelectedIDs.remove(payerID)
        } else {
            tempSelectedIDs.insert(payerID)
        }
    }
}

// MARK: - PayerSelectionSheetForNew (新付款人選擇)
struct PayerSelectionSheetForNew: View {
    @Environment(\.dismiss) private var dismiss
    
    let availablePayers: [Payer]
    let onSelect: (Payer) -> Void
    
    var body: some View {
        NavigationStack {
            List {
                if availablePayers.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.slash")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                            .opacity(0.7)
                        
                        Text("冇可用嘅付款人")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text("所有付款人都已經被選擇")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    Section("可選擇嘅付款人") {
                        ForEach(availablePayers) { payer in
                            Button(action: {
                                onSelect(payer)
                            }) {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 12, height: 12)
                                    
                                    Text(payer.name)
                                        .foregroundColor(.primary)
                                    
                                    Spacer()
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(.vertical, 8)
                            }
                        }
                    }
                    
                    Section {
                        HStack {
                            Text("可選擇")
                            Spacer()
                            Text("\(availablePayers.count)人")
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle("選擇付款人")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
        }
    }
}
