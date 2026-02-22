import SwiftUI
import SwiftData
import UIKit
import WidgetKit   // 新增

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
    
    // 參與者選擇相關狀態
    @State private var participantEntries: [ParticipantEntry] = []
    @State private var showParticipantSelection = false
    @State private var assignedPayersForCategory: [Payer] = []
    
    // 用於顯示分攤警告的狀態
    @State private var showContributionMismatchAlert = false
    @State private var contributionDifference: Decimal = 0
    @State private var allowSaveAnyway = false
    
    // 收入交易收款人ID
    @State private var selectedIncomePayerID: UUID? = nil
    
    // 分攤模式狀態 - 默認為 .simple（一人支付全部）
    @State private var contributionMode: ContributionMode = .simple
    
    // 付款人選擇相關狀態
    @State private var showPayerSelectionForNew = false
    @State private var selectedPayerForNew: Payer? = nil
    
    // 追踪每個支付金額輸入框嘅激活狀態
    @State private var contributionAmountFocusStates: [UUID: Bool] = [:]
    
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
                                            $0.parentID == cat.id && $0.isUncategorized
                                        }) {
                                            selectedSubcategoryID = uncategorizedSub.id
                                        }
                                        
                                        // 更新該分類的已分配付款人及參與者
                                        updateAssignedPayersForCategory(cat)
                                        
                                        // 如果切換分類，重置收入收款人選擇
                                        if selectedType == .income {
                                            selectedIncomePayerID = nil
                                        }
                                    }) {
                                        HStack {
                                            Text(categoryDisplayName(cat))
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
                                            // ✅ 使用 isUncategorized 判斷顯示名稱
                                            Text(sub.isUncategorized ? langManager.localized("uncategorized_label") : sub.name)
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
                
                // 參與者選擇區域 - 只有當分類有分配付款人時才顯示
                if selectedType == .expense && !assignedPayersForCategory.isEmpty {
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
                                    Text(String(format: langManager.localized("people_count_format"), selectedParticipantCount))
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
                }
                
                // 支付方式選擇 - 支出交易才顯示
                if selectedType == .expense {
                    Section(header: Text(langManager.localized("payment_method_section"))) {
                        if isEditing {
                            VStack(alignment: .leading, spacing: 12) {
                                Picker("", selection: $contributionMode) {
                                    Text(langManager.localized("simple_payment_mode")).tag(ContributionMode.simple)
                                    Text(langManager.localized("detailed_payment_mode")).tag(ContributionMode.detailed)
                                }
                                .pickerStyle(.segmented)
                                .onChange(of: contributionMode) { newMode in
                                    handleContributionModeChange(newMode)
                                }
                                
                                Text(getContributionModeDescription())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                            }
                            .padding(.vertical, 4)
                        } else {
                            HStack {
                                Text(langManager.localized("payment_method_label"))
                                Spacer()
                                Text(contributionMode == .simple ? langManager.localized("simple_payment_mode") : langManager.localized("detailed_payment_mode"))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // 支付詳情（根據模式顯示）
                    if contributionMode == .simple {
                        Section(header: Text(langManager.localized("payment_details_section"))) {
                            if isEditing {
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
                                                Text(payerDisplayName(payer))
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
                                            Text(payerDisplayName(payer))
                                                .foregroundColor(.primary)
                                        } else {
                                            Text(langManager.localized("select_payer_placeholder"))
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
                                
                                if let contribution = contributions.first,
                                   let amount = decimalFromString(contribution.amountText),
                                   amount > 0 {
                                    HStack {
                                        Text(langManager.localized("payment_amount_label"))
                                        Spacer()
                                        Text(formatCurrency(amount: amount, code: currencyCode))
                                            .foregroundColor(.blue)
                                            .bold()
                                    }
                                    .padding(.top, 8)
                                }
                            } else {
                                if let contribution = contributions.first,
                                   let payerID = contribution.payerID,
                                   let payer = payers.first(where: { $0.id == payerID }),
                                   let amount = decimalFromString(contribution.amountText) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            Circle()
                                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                                .frame(width: 12, height: 12)
                                            Text(payerDisplayName(payer))
                                                .font(.body)
                                            Spacer()
                                            Text(langManager.localized("pays_full_amount"))
                                                .font(.caption)
                                                .foregroundColor(.secondary)
                                        }
                                        
                                        HStack {
                                            Text(langManager.localized("payment_amount_label"))
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
                        Section(header: HStack {
                            Text(langManager.localized("detailed_payment_header"))
                            Spacer()
                            if isEditing && !contributions.isEmpty {
                                Button(action: {
                                    hideKeyboard()
                                    calculateRemainingDistribution()
                                }) {
                                    Text(langManager.localized("auto_distribute_remaining_button"))
                                        .font(.caption)
                                }
                            }
                        }) {
                            if isEditing {
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
                                                Text(langManager.localized("add_payer_button"))
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
                                        
                                        Text(langManager.localized("start_recording_payments"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                                } else {
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
                                                            Text(payerDisplayName(payer))
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
                                                        .frame(width: 100, alignment: .leading)
                                                        .lineLimit(1)
                                                }
                                            }
                                            .frame(width: 120)
                                            .onTapGesture {
                                                hideKeyboard()
                                            }
                                            
                                            SelectAllTextField(
                                                text: Binding(
                                                    get: { contributions[index].amountText },
                                                    set: { newValue in
                                                        contributions[index].amountText = newValue
                                                        validateAmounts()
                                                    }
                                                ),
                                                isFirstResponder: Binding(
                                                    get: { contributionAmountFocusStates[contributions[index].id] ?? false },
                                                    set: { newValue in
                                                        contributionAmountFocusStates[contributions[index].id] = newValue
                                                        
                                                        if newValue {
                                                            for (id, _) in contributionAmountFocusStates {
                                                                if id != contributions[index].id {
                                                                    contributionAmountFocusStates[id] = false
                                                                }
                                                            }
                                                        }
                                                    }
                                                ),
                                                placeholder: langManager.localized("amount_placeholder"),
                                                keyboardType: .decimalPad,
                                                onCommit: {
                                                    if let value = decimalFromString(contributions[index].amountText) {
                                                        contributions[index].amountText = decimalToString(value)
                                                    }
                                                    contributionAmountFocusStates[contributions[index].id] = false
                                                }
                                            )
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 90, height: 28)
                                            
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
                                        if canAddNewContribution() {
                                            showPayerSelectionForNew = true
                                        }
                                    }) {
                                        HStack {
                                            Image(systemName: "plus.circle.fill")
                                                .foregroundColor(canAddNewContribution() ? .accentColor : .gray)
                                            Text(langManager.localized("add_payer_button"))
                                                .foregroundColor(canAddNewContribution() ? .primary : .gray)
                                        }
                                    }
                                    .disabled(!canAddNewContribution())
                                    .padding(.top, 8)
                                }
                                
                                if !contributions.isEmpty {
                                    HStack {
                                        Text(langManager.localized("total_paid_label"))
                                            .font(.caption)
                                        Spacer()
                                        
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
                                        Text(langManager.localized("amount_mismatch_warning"))
                                            .font(.caption)
                                            .foregroundColor(.orange)
                                    }
                                    .padding(.top, 4)
                                }
                            } else {
                                if contributions.isEmpty {
                                    Text(langManager.localized("no_payment_records"))
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
                                                
                                                Text(payerDisplayName(payer))
                                                    .font(.body)
                                                Spacer()
                                                Text(formatCurrency(amount: amount, code: currencyCode))
                                                    .font(.body)
                                            }
                                            .padding(.vertical, 2)
                                        }
                                    }
                                    HStack {
                                        Text(langManager.localized("total_paid_label"))
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

                // 收入交易收款人選擇
                if selectedType == .income {
                    Section(header: Text(langManager.localized("income_recipient_section"))) {
                        if isEditing {
                            Menu {
                                let availablePayersForIncome = getAvailablePayersForIncome()
                                
                                if availablePayersForIncome.isEmpty {
                                    Text(langManager.localized("no_assigned_payers_for_category"))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                } else {
                                    Text(langManager.localized("income_recipient_constraint_description"))
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
                                                Text(payerDisplayName(payer))
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
                                        Text(payerDisplayName(payer))
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
                            
                            if let parentID = selectedParentID,
                               let category = categories.first(where: { $0.id == parentID }) {
                                let assignedPayers = category.assignedPayers(in: context)
                                if !assignedPayers.isEmpty {
                                    Text(String(format: langManager.localized("income_recipient_constraint_format"), categoryDisplayName(category)))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                        .padding(.top, 4)
                                }
                            }
                        } else {
                            if let payerID = selectedIncomePayerID,
                               let payer = payers.first(where: { $0.id == payerID }) {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 12, height: 12)
                                    Text(payerDisplayName(payer))
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
                                    Text(payerDisplayName(defaultPayer))
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text("\(langManager.localized("income_recipient_label")) (\(langManager.localized("default_label")))")
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
                    selectedParticipantIDs: selectedParticipantIDs,
                    onSave: { selectedIDs in
                        updateParticipantEntries(selectedIDs: selectedIDs)
                        updatePaymentSetup()
                    }
                )
                .environment(\.modelContext, context)
            }
            .sheet(isPresented: $showPayerSelectionForNew) {
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
            .alert(langManager.localized("contribution_mismatch_alert_title"), isPresented: $showContributionMismatchAlert) {
                Button(langManager.localized("cancel_button"), role: .cancel) {
                    allowSaveAnyway = false
                }
                Button(langManager.localized("fix_and_save_button")) {
                    fixContributionAmountsAndSave()
                }
                Button(langManager.localized("save_anyway_button"), role: .destructive) {
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
            return categoryDisplayName(parent)
        } else {
            return langManager.localized("select_category_placeholder")
        }
    }
    
    private var selectedSubcategoryName: String {
        if selectedParentID == nil {
            return ""
        } else if let subID = selectedSubcategoryID,
                  let sub = subcategories.first(where: { $0.id == subID }) {
            // ✅ 使用 isUncategorized 判斷顯示名稱
            return sub.isUncategorized ? langManager.localized("uncategorized_label") : sub.name
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
    
    private var selectedParticipantIDs: Set<UUID> {
        Set(participantEntries.filter { $0.isParticipating }.map { $0.payer.id })
    }
    
    private var selectedParticipantCount: Int {
        selectedParticipantIDs.count
    }
    
    private var isValid: Bool {
        guard let total = decimalFromString(totalAmountText), total > 0 else { return false }
        
        if selectedType == .expense {
            if contributionMode == .simple {
                guard !contributions.isEmpty else { return false }
                guard contributions.first?.payerID != nil else { return false }
            } else if contributionMode == .detailed {
                guard !contributions.isEmpty else { return false }
                for contribution in contributions {
                    if contribution.payerID == nil { return false }
                    guard let amount = decimalFromString(contribution.amountText), amount > 0 else { return false }
                }
            }
        }
        
        return true
    }
    
    private func payerDisplayName(_ payer: Payer) -> String {
        payer.isDefault ? langManager.localized("default_payer_name") : payer.name
    }
    
    private func getPayerName(for index: Int) -> String {
        if let payerID = contributions[index].payerID,
           let payer = payers.first(where: { $0.id == payerID }) {
            return payerDisplayName(payer)
        } else {
            return langManager.localized("select_payer_placeholder")
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
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        if !participatingPayers.isEmpty {
            var availableFromParticipants = participatingPayers
            let selectedPayerIDs = contributions
                .enumerated()
                .filter { $0.offset != index }
                .compactMap { $0.element.payerID }
            let selectedIDsSet = Set(selectedPayerIDs)
            return availableFromParticipants.filter { !selectedIDsSet.contains($0.id) }
        }
        
        var availablePayers: [Payer]
        
        if !assignedPayersForCategory.isEmpty {
            availablePayers = assignedPayersForCategory.sorted { $0.order < $1.order }
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            if !assignedPayers.isEmpty {
                availablePayers = assignedPayers.sorted { $0.order < $1.order }
            } else {
                availablePayers = payers.sorted { $0.order < $1.order }
            }
        } else {
            availablePayers = payers.sorted { $0.order < $1.order }
        }
        
        let selectedPayerIDs = contributions
            .enumerated()
            .filter { $0.offset != index }
            .compactMap { $0.element.payerID }
        let selectedIDsSet = Set(selectedPayerIDs)
        
        return availablePayers.filter { !selectedIDsSet.contains($0.id) }
    }
    
    private func getAvailablePayersForPayment() -> [Payer] {
        if assignedPayersForCategory.isEmpty {
            return payers.sorted { $0.order < $1.order }
        }
        
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        if !participatingPayers.isEmpty {
            return participatingPayers
        }
        
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.sorted { $0.order < $1.order }
        }
        
        return payers.sorted { $0.order < $1.order }
    }
    
    private func getAvailablePayersForIncome() -> [Payer] {
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.sorted { $0.order < $1.order }
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            return assignedPayers.sorted { $0.order < $1.order }
        } else {
            return payers.sorted { $0.order < $1.order }
        }
    }
    
    private func getAvailablePayersForNewContribution() -> [Payer] {
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
        
        let selectedPayerIDs = contributions.compactMap { $0.payerID }
        let selectedIDsSet = Set(selectedPayerIDs)
        
        return availablePayers.filter { !selectedIDsSet.contains($0.id) }
    }
    
    private var defaultPayer: Payer? {
        if assignedPayersForCategory.isEmpty {
            return payers.sorted { $0.order < $1.order }.first
        }
        
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.first
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            if !assignedPayers.isEmpty {
                return assignedPayers.first
            }
        }
        
        return payers.first { $0.isDefault } ?? payers.first
    }
    
    private func getDefaultIncomePayer() -> Payer? {
        if !assignedPayersForCategory.isEmpty {
            return assignedPayersForCategory.first
        } else if let parentID = selectedParentID,
                  let category = categories.first(where: { $0.id == parentID }) {
            let assignedPayers = category.assignedPayers(in: context)
            if !assignedPayers.isEmpty {
                return assignedPayers.first
            }
        }
        return payers.first { $0.isDefault } ?? payers.first
    }
    
    private func canAddNewContribution() -> Bool {
        guard contributionMode == .detailed else { return false }
        let availablePayers = getAvailablePayersForNewContribution()
        return !availablePayers.isEmpty
    }
    
    private func getContributionModeDescription() -> String {
        switch contributionMode {
        case .simple:
            return langManager.localized("simple_payment_description")
        case .detailed:
            return langManager.localized("detailed_payment_description")
        }
    }
    
    private func updateAssignedPayersForCategory(_ category: Category) {
        let assignedPayers = category.assignedPayers(in: context)
        assignedPayersForCategory = assignedPayers.sorted { $0.order < $1.order }
        
        if assignedPayersForCategory.isEmpty {
            participantEntries = []
            if let defaultPayer = payers.sorted(by: { $0.order < $1.order }).first {
                contributionMode = .simple
                contributions = [
                    ContributionEntry(
                        payerID: defaultPayer.id,
                        amountText: totalAmountText.isEmpty ? "" : totalAmountText,
                        isRemovable: false
                    )
                ]
            }
        } else {
            participantEntries = assignedPayersForCategory
                .sorted { $0.order < $1.order }
                .map { payer in
                    ParticipantEntry(payer: payer, isParticipating: true)
                }
            updatePaymentSetup()
        }
    }
    
    private func updateParticipantEntriesFromAssignedPayers() {
        participantEntries = assignedPayersForCategory
            .sorted { $0.order < $1.order }
            .map { payer in
                ParticipantEntry(payer: payer, isParticipating: true)
            }
        updatePaymentSetup()
    }
    
    private func updateParticipantEntriesForNewCategory(_ newAssignedPayers: [Payer]) {
        var newParticipantEntries: [ParticipantEntry] = []
        
        for payer in newAssignedPayers {
            if let existingEntry = participantEntries.first(where: { $0.payer.id == payer.id }) {
                newParticipantEntries.append(existingEntry)
            } else {
                newParticipantEntries.append(ParticipantEntry(payer: payer, isParticipating: true))
            }
        }
        
        participantEntries = newParticipantEntries
        resetPaymentDetailsForNewCategory()
    }
    
    private func updateParticipantEntries(selectedIDs: Set<UUID>) {
        for i in participantEntries.indices {
            participantEntries[i].isParticipating = selectedIDs.contains(participantEntries[i].payer.id)
        }
        updatePaymentSetup()
    }
    
    private func updatePaymentSetup() {
        cleanupInvalidContributions()
        
        if assignedPayersForCategory.isEmpty {
            contributionMode = .simple
            if let defaultPayer = payers.sorted(by: { $0.order < $1.order }).first {
                contributions = [
                    ContributionEntry(
                        payerID: defaultPayer.id,
                        amountText: totalAmountText.isEmpty ? "" : totalAmountText,
                        isRemovable: false
                    )
                ]
            }
            return
        }
        
        let participatingCount = selectedParticipantCount
        
        if participatingCount == 0 {
            contributionMode = .simple
            contributions = []
        } else {
            if contributionMode == .simple {
                setupSinglePayerPayment()
            }
        }
    }
    
    private func setupSinglePayerPayment() {
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        if let firstParticipant = participatingPayers.first {
            contributions = [
                ContributionEntry(
                    payerID: firstParticipant.id,
                    amountText: totalAmountText.isEmpty ? "" : totalAmountText,
                    isRemovable: false
                )
            ]
        } else {
            if let defaultPayer = defaultPayer {
                contributions = [
                    ContributionEntry(
                        payerID: defaultPayer.id,
                        amountText: totalAmountText.isEmpty ? "" : totalAmountText,
                        isRemovable: false
                    )
                ]
            } else {
                contributions = []
            }
        }
    }
    
    private func handleContributionModeChange(_ newMode: ContributionMode) {
        hideKeyboard()
        
        if newMode == .simple {
            setupSinglePayerPayment()
        } else {
            // 轉為詳細模式時，保留現有支付記錄，唔做任何自動添加
        }
    }
    
    private func addNewContribution(payer: Payer) {
        hideKeyboard()
        
        let alreadySelected = contributions.contains { $0.payerID == payer.id }
        guard !alreadySelected else {
            showPayerSelectionForNew = false
            return
        }
        
        contributions.append(ContributionEntry(
            payerID: payer.id,
            amountText: "",
            isRemovable: true
        ))
        
        selectedPayerForNew = nil
        showPayerSelectionForNew = false
        validateAmounts()
    }
    
    private func setSinglePayerPayment(_ payer: Payer) {
        contributions = [
            ContributionEntry(
                payerID: payer.id,
                amountText: totalAmountText.isEmpty ? "" : totalAmountText,
                isRemovable: false
            )
        ]
    }
    
    private func calculateEqualDistribution() {
        let participatingCount = selectedParticipantCount
        guard participatingCount > 0, totalAmountDecimal > 0 else { return }
        
        let total = totalAmountDecimal
        let share = total / Decimal(participatingCount)
        let shareString = decimalToString(share)
        
        var updatedCount = 0
        for i in contributions.indices {
            if let currentAmount = decimalFromString(contributions[i].amountText), currentAmount > 0 {
                continue
            } else {
                contributions[i].amountText = shareString
                updatedCount += 1
            }
        }
        
        if updatedCount == 0 && !contributions.isEmpty {
            for i in contributions.indices {
                contributions[i].amountText = shareString
            }
        }
        
        adjustRoundingErrors()
        validateAmounts()
    }
    
    private func calculateRemainingDistribution() {
        guard !contributions.isEmpty else { return }
        
        let total = totalAmountDecimal
        let currentTotal = distributedTotal
        let remaining = total - currentTotal
        
        guard abs(remaining) > Decimal(0.01) else { return }
        
        var zeroOrEmptyIndices: [Int] = []
        
        for i in contributions.indices {
            if let amount = decimalFromString(contributions[i].amountText) {
                if amount <= 0 {
                    zeroOrEmptyIndices.append(i)
                }
            } else {
                zeroOrEmptyIndices.append(i)
            }
        }
        
        if !zeroOrEmptyIndices.isEmpty {
            let share = remaining / Decimal(zeroOrEmptyIndices.count)
            let shareString = decimalToString(share)
            
            for index in zeroOrEmptyIndices {
                contributions[index].amountText = shareString
            }
        } else {
            let share = remaining / Decimal(contributions.count)
            
            for i in contributions.indices {
                if let currentAmount = decimalFromString(contributions[i].amountText) {
                    let newAmount = currentAmount + share
                    contributions[i].amountText = decimalToString(newAmount)
                }
            }
        }
        
        adjustRoundingErrors()
        validateAmounts()
    }
    
    private func adjustRoundingErrors() {
        guard contributionMode == .detailed else { return }
        
        let total = totalAmountDecimal
        let currentTotal = distributedTotal
        let difference = total - currentTotal
        
        if abs(difference) < Decimal(0.01) {
            return
        }
        
        if !contributions.isEmpty, let firstAmount = decimalFromString(contributions[0].amountText) {
            let adjustedAmount = firstAmount + difference
            contributions[0].amountText = decimalToString(adjustedAmount)
        }
    }
    
    private func updateContributionAmountsOnTotalChange() {
        guard !contributions.isEmpty else { return }
        
        if contributionMode == .simple {
            if contributions.count == 1 {
                contributions[0].amountText = totalAmountText
            }
        }
        
        validateAmounts()
    }
    
    private func updateContributionAmounts() {
        for i in contributions.indices {
            if contributions[i].amountText.isEmpty || decimalFromString(contributions[i].amountText) == 0 {
                let participatingCount = max(selectedParticipantCount, 1)
                let share = totalAmountDecimal / Decimal(participatingCount)
                contributions[i].amountText = decimalToString(share)
            }
        }
        validateAmounts()
    }
    
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
    
    private func cleanupInvalidContributions() {
        guard !contributions.isEmpty else { return }
        
        let validPayerIDs = Set(assignedPayersForCategory.map { $0.id })
        let allPayerIDs = validPayerIDs.isEmpty ? Set(payers.map { $0.id }) : validPayerIDs
        
        contributions = contributions.filter { entry in
            if let payerID = entry.payerID {
                return allPayerIDs.contains(payerID)
            }
            return true
        }
        
        if contributions.isEmpty {
            setupPaymentBasedOnParticipants()
        }
    }
    
    private func setupPaymentBasedOnParticipants() {
        let participatingPayers = participantEntries
            .filter { $0.isParticipating }
            .map { $0.payer }
            .sorted { $0.order < $1.order }
        
        if participatingPayers.isEmpty {
            contributions = []
            return
        }
        
        contributionMode = .simple
        contributions = [
            ContributionEntry(
                payerID: participatingPayers[0].id,
                amountText: totalAmountText.isEmpty ? "" : totalAmountText,
                isRemovable: false
            )
        ]
    }
    
    private func resetPaymentDetailsForNewCategory() {
        contributions.removeAll()
        
        if !participantEntries.isEmpty {
            for i in participantEntries.indices {
                let payerID = participantEntries[i].payer.id
                if assignedPayersForCategory.contains(where: { $0.id == payerID }) {
                    participantEntries[i].isParticipating = true
                } else {
                    participantEntries[i].isParticipating = false
                }
            }
        }
        
        contributionMode = .simple
        setupSinglePayerPayment()
    }
    
    private func handleParentCategoryChange(oldValue: UUID?, newParent: UUID?) {
        hideKeyboard()
        guard oldValue != newParent else { return }
        
        if let newParent = newParent {
            if let uncategorizedSub = subcategories.first(where: {
                $0.parentID == newParent && $0.isUncategorized
            }) {
                selectedSubcategoryID = uncategorizedSub.id
            } else {
                let newSub = Subcategory(
                    name: "uncategorized",
                    parentID: newParent,
                    order: 0,
                    colorHex: "#A8A8A8",
                    isUncategorized: true
                )
                context.insert(newSub)
                selectedSubcategoryID = newSub.id
            }
            
            if let category = categories.first(where: { $0.id == newParent }) {
                updateAssignedPayersForCategory(category)
            }
            
            if selectedType == .income {
                selectedIncomePayerID = nil
            }
        } else {
            selectedSubcategoryID = nil
            assignedPayersForCategory = []
            participantEntries = []
            selectedIncomePayerID = nil
            contributions.removeAll()
            contributionMode = .simple
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
                
                if let category = categories.first(where: { $0.id == sub.parentID }) {
                    updateAssignedPayersForCategory(category)
                    
                    if !tx.participatingPayerIDs.isEmpty {
                        let selectedIDs = Set(tx.participatingPayerIDs)
                        updateParticipantEntries(selectedIDs: selectedIDs)
                    } else {
                        updateParticipantEntriesFromAssignedPayers()
                    }
                }
                
                if tx.type == .income && !tx.contributions.isEmpty {
                    if let contribution = tx.contributions.first {
                        selectedIncomePayerID = contribution.payer.id
                    }
                }
            } else {
                assignToDefaultUncategorized()
            }
            
            if tx.type == .expense && !tx.contributions.isEmpty && !assignedPayersForCategory.isEmpty {
                contributions = tx.contributions.map { contribution in
                    ContributionEntry(
                        payerID: contribution.payer.id,
                        amountText: decimalToString(contribution.amount),
                        isRemovable: true
                    )
                }
                
                if tx.contributions.count == 1 {
                    contributionMode = .simple
                } else {
                    contributionMode = .detailed
                }
            } else {
                contributionMode = .simple
                updatePaymentSetup()
            }
        } else {
            selectedParentID = nil
            selectedSubcategoryID = nil
            assignedPayersForCategory = []
            participantEntries = []
            selectedIncomePayerID = nil
            contributions.removeAll()
            contributionMode = .simple
            
            if let defaultPayer = payers.sorted(by: { $0.order < $1.order }).first {
                contributions = [
                    ContributionEntry(
                        payerID: defaultPayer.id,
                        amountText: "",
                        isRemovable: false
                    )
                ]
            }
        }
    }
    
    private func assignToDefaultUncategorized() {
        if let defaultCategory = categories.first(where: { $0.isDefault }),
           let defaultSubcategory = subcategories.first(where: {
               $0.parentID == defaultCategory.id && $0.isUncategorized
           }) {
            selectedParentID = defaultCategory.id
            selectedSubcategoryID = defaultSubcategory.id
            updateAssignedPayersForCategory(defaultCategory)
        } else if let firstCategory = categories.first {
            selectedParentID = firstCategory.id
            if let firstSubcategory = subcategories.first(where: { $0.parentID == firstCategory.id }) {
                selectedSubcategoryID = firstSubcategory.id
            }
            updateAssignedPayersForCategory(firstCategory)
        }
    }
    
    // MARK: - Actions & Helpers
    
    private func handleTypeChange(_ newType: TransactionType) {
        selectedType = newType
        if newType == .income {
            contributions.removeAll()
        } else {
            updatePaymentSetup()
        }
    }
    
    private func validateAmounts() {
        let difference = abs(distributedTotal - totalAmountDecimal)
        showAmountError = difference > Decimal(0.01)
    }
    
    private func saveWithValidation() {
        guard let totalAmount = decimalFromString(totalAmountText), totalAmount > 0 else {
            return
        }
        
        hideKeyboard()
        
        if selectedSubcategoryID == nil {
            assignToDefaultUncategorized()
        }
        
        let difference = abs(distributedTotal - totalAmount)
        
        if difference > Decimal(0.01) {
            contributionDifference = distributedTotal - totalAmount
            showContributionMismatchAlert = true
            return
        }
        
        saveTransaction()
    }
    
    private func fixContributionAmountsAndSave() {
        guard let totalAmount = decimalFromString(totalAmountText) else { return }
        
        if !contributions.isEmpty {
            let difference = totalAmount - distributedTotal
            
            if contributionMode == .simple {
                if contributions.count == 1 {
                    contributions[0].amountText = decimalToString(totalAmount)
                }
            } else {
                let perPersonAdjustment = difference / Decimal(contributions.count)
                
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
        transactionToSave.subcategoryID = selectedSubcategoryID
        
        if selectedType == .expense {
            transactionToSave.participatingPayerIDs = Array(selectedParticipantIDs)
        } else {
            transactionToSave.participatingPayerIDs = []
        }
        
        for contribution in transactionToSave.contributions {
            context.delete(contribution)
        }
        transactionToSave.contributions.removeAll()
        
        if selectedType == .expense {
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
            let incomePayerID: UUID?
            
            if let payerID = selectedIncomePayerID {
                incomePayerID = payerID
            } else {
                incomePayerID = getDefaultIncomePayer()?.id
            }
            
            if let payerID = incomePayerID,
               let payer = payers.first(where: { $0.id == payerID }) {
                let paymentContribution = PaymentContribution(
                    amount: totalAmount,
                    payer: payer,
                    transaction: transactionToSave
                )
                transactionToSave.contributions.append(paymentContribution)
            } else if let defaultPayer = getDefaultIncomePayer() {
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
            WidgetCenter.shared.reloadTimelines(ofKind: "NoMoneyLaWidget") // 新增
            WidgetCenter.shared.reloadTimelines(ofKind: "RecentTransactionWidget")
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
            WidgetCenter.shared.reloadTimelines(ofKind: "NoMoneyLaWidget") // 新增
            WidgetCenter.shared.reloadTimelines(ofKind: "RecentTransactionWidget")
            dismiss()
        } catch {
            print("刪除交易時出錯: \(error)")
        }
    }
    
    private func categoryPath(parentID: UUID?, subID: UUID?) -> String {
        if let p = parentID, let parent = categories.first(where: { $0.id == p }) {
            let parentName = categoryDisplayName(parent)
            if let s = subID, let sub = subcategories.first(where: { $0.id == s }) {
                let subName = sub.isUncategorized ? langManager.localized("uncategorized_label") : sub.name
                return "\(parentName) / \(subName)"
            } else {
                return parentName
            }
        } else {
            return langManager.localized("uncategorized_label")
        }
    }
    
    private func categoryDisplayName(_ category: Category) -> String {
        if category.isDefault {
            return langManager.localized("uncategorized_label")
        } else {
            return category.name
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
    
    private func getContributionMismatchMessage() -> String {
        let difference = abs(contributionDifference)
        let amountStr = formatCurrency(amount: difference, code: currencyCode)
        
        if contributionDifference > 0 {
            return String(format: langManager.localized("contribution_excess_alert_message_format"), amountStr)
        } else {
            return String(format: langManager.localized("contribution_insufficient_alert_message_format"), amountStr)
        }
    }
}

// MARK: - ParticipantChip
struct ParticipantChip: View {
    @EnvironmentObject var langManager: LanguageManager
    let payer: Payer
    
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                .frame(width: 8, height: 8)
            Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)
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
    @EnvironmentObject var langManager: LanguageManager

    let assignedPayers: [Payer]
    let selectedParticipantIDs: Set<UUID>
    let onSave: (Set<UUID>) -> Void

    @State private var tempSelectedIDs: Set<UUID> = []

    private var sortedAssignedPayers: [Payer] {
        assignedPayers.sorted { $0.order < $1.order }
    }

    var body: some View {
        NavigationStack {
            List {
                if sortedAssignedPayers.isEmpty {
                    ContentUnavailableView(
                        langManager.localized("no_assigned_payers_for_category"),
                        systemImage: "person.slash",
                        description: Text(langManager.localized("assign_payers_first"))
                    )
                } else {
                    Section {
                        ForEach(sortedAssignedPayers) { payer in
                            HStack {
                                Circle()
                                    .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                    .frame(width: 12, height: 12)

                                Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)

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
                    }

                    Section {
                        HStack {
                            Text(langManager.localized("selected_label"))
                            Spacer()
                            Text(String(format: langManager.localized("people_count_format"), tempSelectedIDs.count))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle(langManager.localized("select_participants"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("cancel_button")) {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button(langManager.localized("done_button")) {
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

    private func toggleSelection(_ payerID: UUID) {
        if tempSelectedIDs.contains(payerID) {
            tempSelectedIDs.remove(payerID)
        } else {
            tempSelectedIDs.insert(payerID)
        }
    }
}

// MARK: - PayerSelectionSheetForNew
struct PayerSelectionSheetForNew: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var langManager: LanguageManager
    
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
                        
                        Text(langManager.localized("no_available_payers_title"))
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        Text(langManager.localized("all_payers_already_selected"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    Section(langManager.localized("available_payers_section_header")) {
                        ForEach(availablePayers) { payer in
                            Button(action: {
                                onSelect(payer)
                            }) {
                                HStack {
                                    Circle()
                                        .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 12, height: 12)
                                    
                                    Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)
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
                            Text(langManager.localized("available_label"))
                            Spacer()
                            Text(String(format: langManager.localized("people_count_format"), availablePayers.count))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .navigationTitle(langManager.localized("select_payer_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("cancel_button")) {
                        dismiss()
                    }
                }
            }
        }
    }
}
