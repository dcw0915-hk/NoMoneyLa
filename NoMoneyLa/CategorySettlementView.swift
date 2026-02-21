import SwiftUI
import SwiftData

// MARK: - 債務結算結構（保留）
struct SettlementResult {
    let payer: Payer
    let netBalance: Decimal
    let shouldPayTo: Payer?
    let amount: Decimal
}

// MARK: - 付款人交易行視圖（支援貨幣）
struct PayerTransactionRowView: View {
    @EnvironmentObject var langManager: LanguageManager
    let transaction: Transaction
    let payer: Payer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transaction.date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatCurrency(transaction.totalAmount, code: transaction.currencyCode))
                    .font(.body)
                    .bold()
                    .foregroundColor(transaction.type == .expense ? .red : .green)
            }
            
            if let note = transaction.note, !note.isEmpty {
                Text(note)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            if let contribution = transaction.contributions.first(where: { $0.payer.id == payer.id }) {
                HStack {
                    Text("\(langManager.localized("contribution_label"))：")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(formatCurrency(contribution.amount, code: transaction.currencyCode))
                        .font(.caption2)
                        .bold()
                    
                    Text("(\(langManager.localized("total_amount_label"))\(formatCurrency(transaction.totalAmount, code: transaction.currencyCode)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            if !transaction.isAmountValid && transaction.type == .expense {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text(transaction.contributionStatusDescription)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
                .padding(.top, 2)
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatCurrency(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 付款人標題視圖
struct PayerHeaderView: View {
    @EnvironmentObject var langManager: LanguageManager
    let payer: Payer
    let transactionCount: Int
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                .frame(width: 24, height: 24)
            
            Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)
                .font(.title2)
                .bold()
            
            Spacer()
            
            Text("\(transactionCount) \(langManager.localized("transactions_label"))")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 付款人交易詳細視圖
struct PayerTransactionsView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let payer: Payer
    let category: Category
    
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    
    private var payerTransactions: [Transaction] {
        let subcategoryIDs = allSubcategories
            .filter { $0.parentID == category.id }
            .map { $0.id }
        
        if subcategoryIDs.isEmpty { return [] }
        
        return allTransactions.filter { transaction in
            guard let subID = transaction.subcategoryID,
                  subcategoryIDs.contains(subID) else { return false }
            return transaction.contributions.contains { $0.payer.id == payer.id }
        }
    }
    
    private var totalPaid: Decimal {
        payerTransactions.reduce(Decimal(0)) { total, transaction in
            let payerContributions = transaction.contributions.filter { $0.payer.id == payer.id }
            return total + payerContributions.reduce(0) { $0 + $1.amount }
        }
    }
    
    private var currencySet: Set<String> {
        Set(payerTransactions.map { $0.currencyCode })
    }
    
    private var isSingleCurrency: Bool {
        currencySet.count == 1
    }
    
    private var primaryCurrency: String {
        currencySet.first ?? "HKD"
    }
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    PayerHeaderView(payer: payer, transactionCount: payerTransactions.count)
                }
                
                Section(langManager.localized("transaction_records")) {
                    if payerTransactions.isEmpty {
                        Text(langManager.localized("no_payer_transactions_in_category"))
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(payerTransactions) { transaction in
                            PayerTransactionRowView(transaction: transaction, payer: payer)
                        }
                    }
                }
                
                Section(langManager.localized("statistics_label")) {
                    // 總支付金額
                    HStack {
                        Text(langManager.localized("total_paid_amount"))
                        Spacer()
                        if isSingleCurrency {
                            Text(formatCurrency(totalPaid, code: primaryCurrency))
                                .font(.headline)
                                .foregroundColor(.blue)
                        } else {
                            Text(String(format: langManager.localized("estimated_hkd_format"), formatCurrency(totalPaid, code: "HKD")))
                                .font(.headline)
                                .foregroundColor(.blue)
                        }
                    }
                    
                    // 交易筆數
                    HStack {
                        Text(langManager.localized("participating_transactions_count"))
                        Spacer()
                        Text("\(payerTransactions.count)")
                            .font(.headline)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle(langManager.localized("transaction_details"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(langManager.localized("done_button")) { dismiss() }
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 主要視圖
struct CategorySettlementView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let category: Category
    
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Payer.order) private var allPayers: [Payer]
    
    // 按貨幣分組的交易
    private var transactionsByCurrency: [String: [Transaction]] {
        Dictionary(grouping: categoryTransactions, by: { $0.currencyCode })
    }
    
    // 貨幣列表
    private var currencies: [String] {
        transactionsByCurrency.keys.sorted()
    }
    
    // 該分類所有支出交易
    private var categoryTransactions: [Transaction] {
        let subcategoryIDs = allSubcategories
            .filter { $0.parentID == category.id }
            .map { $0.id }
        if subcategoryIDs.isEmpty { return [] }
        return allTransactions.filter { transaction in
            guard let subID = transaction.subcategoryID,
                  subcategoryIDs.contains(subID) else { return false }
            return transaction.type == .expense
        }
    }
    
    // 貨幣集合（用於判斷單一/多貨幣）
    private var currencySet: Set<String> {
        Set(categoryTransactions.map { $0.currencyCode })
    }
    
    private var isSingleCurrency: Bool {
        currencySet.count == 1
    }
    
    private var primaryCurrency: String {
        currencySet.first ?? "HKD"
    }
    
    // 每個貨幣自己的參與者、結算結果、結算步驟
    @State private var participantsByCurrency: [String: [Payer]] = [:]
    @State private var settlementResultsByCurrency: [String: [SettlementResult]] = [:]
    @State private var settlementStepsByCurrency: [String: [(from: Payer, to: Payer, amount: Decimal)]] = [:]
    
    @State private var selectedPayer: Payer?
    @State private var showPayerTransactions = false
    
    @State private var debugInfo: [String] = []
    @State private var invalidTransactionCount: Int = 0
    @State private var missingAmount: Decimal = 0
    @State private var hasContributionIssues: Bool = false
    
    // 用於控制詳細結果摺疊的狀態
    @State private var expandedDetails: [String: Bool] = [:]
    // 用於控制 debug 資訊顯示
    @State private var showDebugInfo: Bool = false
    
    var body: some View {
        List {
            // 分攤問題警告（如果有問題先顯示）
            if hasContributionIssues {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text(langManager.localized("contribution_issue_warning"))
                                .font(.headline)
                                .foregroundColor(.orange)
                            Spacer()
                        }
                        
                        Text(String(format: langManager.localized("transactions_incomplete_format"), invalidTransactionCount))
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        
                        if missingAmount != 0 {
                            HStack {
                                Text(langManager.localized("contribution_difference_label"))
                                Text(formatCurrency(abs(missingAmount), code: "HKD") + " HKD")
                            }
                            .font(.subheadline)
                            .foregroundColor(.orange)
                        }
                        
                        Text(langManager.localized("suggestion_check_transactions"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // MARK: - 按貨幣分組顯示參與者及結算
            ForEach(currencies, id: \.self) { currency in
                let transactions = transactionsByCurrency[currency] ?? []
                let participants = participantsByCurrency[currency] ?? []
                let results = settlementResultsByCurrency[currency] ?? []
                let steps = settlementStepsByCurrency[currency] ?? []
                
                if !transactions.isEmpty {
                    // 貨幣標題
                    Section {
                        HStack {
                            Image(systemName: "dollarsign.circle")
                                .foregroundColor(.blue)
                            Text(String(format: langManager.localized("currency_header_format"), currency))
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Text("\(transactions.count) \(langManager.localized("transactions_label"))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 參與者列表（該貨幣）
                    Section(langManager.localized("participants_label")) {
                        if participants.isEmpty {
                            Text(langManager.localized("no_participants_or_transactions"))
                                .foregroundColor(.secondary)
                                .italic()
                                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        } else {
                            ForEach(participants) { payer in
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                        .frame(width: 16, height: 16)
                                    
                                    Text(payer.isDefault ? langManager.localized("default_payer_name") : payer.name)
                                        .font(.body)
                                        .lineLimit(1)
                                    
                                    Spacer()
                                    
                                    if let result = results.first(where: { $0.payer.id == payer.id }) {
                                        Text(formatCurrency(result.netBalance, code: currency))
                                            .font(.body)
                                            .foregroundColor(result.netBalance > 0 ? .green : (result.netBalance < 0 ? .red : .primary))
                                    }
                                    
                                    Button {
                                        selectedPayer = payer
                                        showPayerTransactions = true
                                    } label: {
                                        Image(systemName: "list.bullet")
                                            .foregroundColor(.blue)
                                            .frame(width: 30, height: 30)
                                    }
                                    .buttonStyle(BorderlessButtonStyle())
                                }
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                            }
                        }
                    }
                    
                    // 結算方案（該貨幣）
                    if !steps.isEmpty {
                        Section(langManager.localized("optimal_settlement_solution")) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(String(format: langManager.localized("optimal_settlement_for_currency_format"), currency))
                                    .font(.headline)
                                    .foregroundColor(.green)
                                
                                ForEach(steps.indices, id: \.self) { index in
                                    let step = steps[index]
                                    HStack {
                                        Text("\(index + 1).")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Circle()
                                            .fill(Color(hex: step.from.colorHex ?? "#A8A8A8"))
                                            .frame(width: 12, height: 12)
                                        
                                        Text(step.from.isDefault ? langManager.localized("default_payer_name") : step.from.name)
                                            .font(.body)
                                        
                                        Text(langManager.localized("pays_to"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Circle()
                                            .fill(Color(hex: step.to.colorHex ?? "#A8A8A8"))
                                            .frame(width: 12, height: 12)
                                        
                                        Text(step.to.isDefault ? langManager.localized("default_payer_name") : step.to.name)
                                            .font(.body)
                                        
                                        Spacer()
                                        
                                        Text(formatCurrency(step.amount, code: currency))
                                            .font(.body)
                                            .bold()
                                            .foregroundColor(.blue)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    
                    // 詳細計算結果（該貨幣）- 可摺疊
                    if !results.isEmpty {
                        Section {
                            DisclosureGroup(
                                isExpanded: Binding(
                                    get: { expandedDetails[currency] ?? false },
                                    set: { expandedDetails[currency] = $0 }
                                ),
                                content: {
                                    ForEach(results, id: \.payer.id) { result in
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack {
                                                Circle()
                                                    .fill(Color(hex: result.payer.colorHex ?? "#A8A8A8"))
                                                    .frame(width: 12, height: 12)
                                                
                                                Text(result.payer.isDefault ? langManager.localized("default_payer_name") : result.payer.name)
                                                    .font(.headline)
                                                
                                                Spacer()
                                                
                                                let paid = totalPaidByPayer(result.payer, in: currency)
                                                Text("\(langManager.localized("actual_paid"))：\(formatCurrency(paid, code: currency))")
                                                    .font(.caption)
                                                    .foregroundColor(.blue)
                                            }
                                            
                                            HStack {
                                                Text("\(langManager.localized("net_balance"))：")
                                                    .font(.caption)
                                                    .foregroundColor(.secondary)
                                                
                                                Text(formatCurrency(result.netBalance, code: currency))
                                                    .font(.body)
                                                    .foregroundColor(result.netBalance > 0 ? .green : (result.netBalance < 0 ? .red : .primary))
                                                
                                                Spacer()
                                                
                                                if let toPayer = result.shouldPayTo {
                                                    Text("\(langManager.localized("should_pay_to")) \(toPayer.isDefault ? langManager.localized("default_payer_name") : toPayer.name)")
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                }
                                            }
                                        }
                                        .padding(.vertical, 4)
                                    }
                                },
                                label: {
                                    Text(langManager.localized("detailed_calculation_results") + " (\(currency))")
                                        .font(.headline)
                                }
                            )
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        }
                    }
                }
            }
            
            // MARK: 計算方法說明
            Section(langManager.localized("calculation_explanation")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(langManager.localized("calc_explanation_1"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(langManager.localized("calc_explanation_2"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(langManager.localized("calc_explanation_3"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 8)
            }
            
            // MARK: 除錯信息 - 改為可摺疊
            if !debugInfo.isEmpty {
                Section {
                    DisclosureGroup(
                        isExpanded: $showDebugInfo,
                        content: {
                            ForEach(debugInfo.indices, id: \.self) { index in
                                Text(debugInfo[index])
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .padding(.vertical, 2)
                            }
                        },
                        label: {
                            HStack {
                                Image(systemName: "hammer.fill")
                                    .foregroundColor(.gray)
                                Text(langManager.localized("debug_calculation_details"))
                                    .font(.headline)
                                    .foregroundColor(.gray)
                                Spacer()
                                Text(showDebugInfo ? langManager.localized("hide_button") : langManager.localized("show_button"))
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    )
                }
            }
        }
        .navigationTitle(langManager.localized("debt_settlement"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(langManager.localized("recalculate_button")) {
                    calculateSettlement()
                }
            }
        }
        .onAppear {
            calculateSettlement()
        }
        .onChange(of: category.id) { _, _ in
            calculateSettlement()
        }
        .sheet(isPresented: $showPayerTransactions) {
            if let payer = selectedPayer {
                PayerTransactionsView(payer: payer, category: category)
            }
        }
    }
    
    // MARK: - 貨幣格式化
    private func formatCurrency(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
    
    // MARK: - 按貨幣計算結算
    private func calculateSettlement() {
        clearDebugInfo()
        addDebugInfo("=== 開始按貨幣分組結算 ===")
        addDebugInfo("分類: \(categoryDisplayName)")
        
        checkContributionIssues()
        
        // 按貨幣重置
        participantsByCurrency = [:]
        settlementResultsByCurrency = [:]
        settlementStepsByCurrency = [:]
        
        for currency in currencies {
            let transactions = transactionsByCurrency[currency] ?? []
            addDebugInfo("--- 貨幣: \(currency) (\(transactions.count) 筆交易) ---")
            
            // 獲取該貨幣的參與者
            let participants = getParticipants(for: transactions)
            participantsByCurrency[currency] = participants
            
            if participants.isEmpty {
                addDebugInfo("  無參與者")
                continue
            }
            
            // 計算每人實付及應付
            var paidAmounts: [Payer: Decimal] = [:]
            var shouldPayAmounts: [Payer: Decimal] = [:]
            
            for payer in participants {
                paidAmounts[payer] = 0
                shouldPayAmounts[payer] = 0
            }
            
            for transaction in transactions {
                let transactionParticipants = getParticipantsForTransaction(transaction)
                if transactionParticipants.isEmpty { continue }
                
                let perPersonAmount = transaction.totalAmount / Decimal(transactionParticipants.count)
                
                for participant in transactionParticipants {
                    shouldPayAmounts[participant] = (shouldPayAmounts[participant] ?? 0) + perPersonAmount
                }
                
                for contribution in transaction.contributions {
                    let payer = contribution.payer
                    if paidAmounts[payer] != nil {
                        paidAmounts[payer] = (paidAmounts[payer] ?? 0) + contribution.amount
                    }
                }
            }
            
            // 計算淨結餘
            var netBalances: [Payer: Decimal] = [:]
            var results: [SettlementResult] = []
            
            for payer in participants {
                let paid = paidAmounts[payer] ?? 0
                let shouldPay = shouldPayAmounts[payer] ?? 0
                let netBalance = paid - shouldPay
                netBalances[payer] = netBalance
                results.append(SettlementResult(
                    payer: payer,
                    netBalance: netBalance,
                    shouldPayTo: nil,
                    amount: 0
                ))
                addDebugInfo("  \(payerDisplayName(payer)): 實付=\(formatCurrency(paid, code: currency)), 應付=\(formatCurrency(shouldPay, code: currency)), 淨額=\(formatCurrency(netBalance, code: currency))")
            }
            
            // 計算最優結算步驟
            let steps = calculateOptimalSettlement(balances: netBalances)
            settlementStepsByCurrency[currency] = steps
            
            // 更新結算結果中的應付款信息
            for step in steps {
                if let index = results.firstIndex(where: { $0.payer.id == step.from.id }) {
                    results[index] = SettlementResult(
                        payer: step.from,
                        netBalance: netBalances[step.from] ?? 0,
                        shouldPayTo: step.to,
                        amount: step.amount
                    )
                }
            }
            
            settlementResultsByCurrency[currency] = results.sorted { $0.netBalance > $1.netBalance }
            addDebugInfo("  結算步驟數: \(steps.count)")
        }
    }
    
    // 獲取分類顯示名稱（用於除錯）
    private var categoryDisplayName: String {
        if category.isDefault {
            return langManager.localized("uncategorized_label")
        } else {
            return category.name
        }
    }
    
    private func payerDisplayName(_ payer: Payer) -> String {
        payer.isDefault ? langManager.localized("default_payer_name") : payer.name
    }
    
    // 獲取某組交易的參與者
    private func getParticipants(for transactions: [Transaction]) -> [Payer] {
        var participantIDs = Set<UUID>()
        for transaction in transactions {
            let participants = getParticipantsForTransaction(transaction)
            for payer in participants {
                participantIDs.insert(payer.id)
            }
        }
        if !participantIDs.isEmpty {
            return allPayers.filter { participantIDs.contains($0.id) }
        }
        return category.assignedPayers(in: context)
    }
    
    private func getParticipantsForTransaction(_ transaction: Transaction) -> [Payer] {
        if !transaction.participatingPayerIDs.isEmpty {
            return allPayers.filter { transaction.participatingPayerIDs.contains($0.id) }
        }
        return category.assignedPayers(in: context)
    }
    
    // 計算指定貨幣下某付款人的總實付
    private func totalPaidByPayer(_ payer: Payer, in currency: String) -> Decimal {
        let transactions = transactionsByCurrency[currency] ?? []
        return transactions.reduce(Decimal(0)) { total, transaction in
            if let contribution = transaction.contributions.first(where: { $0.payer.id == payer.id }) {
                return total + contribution.amount
            }
            return total
        }
    }
    
    // 最優結算算法
    private func calculateOptimalSettlement(balances: [Payer: Decimal]) -> [(from: Payer, to: Payer, amount: Decimal)] {
        var creditors: [(payer: Payer, amount: Decimal)] = []
        var debtors: [(payer: Payer, amount: Decimal)] = []
        
        for (payer, balance) in balances {
            if balance > 0 {
                creditors.append((payer: payer, amount: balance))
            } else if balance < 0 {
                debtors.append((payer: payer, amount: -balance))
            }
        }
        
        creditors.sort { $0.amount > $1.amount }
        debtors.sort { $0.amount > $1.amount }
        
        var steps: [(from: Payer, to: Payer, amount: Decimal)] = []
        var i = 0, j = 0
        
        while i < creditors.count && j < debtors.count {
            let creditor = creditors[i]
            let debtor = debtors[j]
            let settleAmount = min(creditor.amount, debtor.amount)
            if settleAmount > 0 {
                steps.append((from: debtor.payer, to: creditor.payer, amount: settleAmount))
            }
            creditors[i].amount -= settleAmount
            debtors[j].amount -= settleAmount
            if creditors[i].amount == 0 { i += 1 }
            if debtors[j].amount == 0 { j += 1 }
        }
        return steps
    }
    
    // 分攤問題檢查（匯總）
    private func checkContributionIssues() {
        invalidTransactionCount = 0
        missingAmount = 0
        hasContributionIssues = false
        
        for transaction in categoryTransactions where !transaction.isAmountValid && transaction.type == .expense {
            invalidTransactionCount += 1
            hasContributionIssues = true
            let sum = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            missingAmount += transaction.totalAmount - sum
        }
    }
    
    private func addDebugInfo(_ message: String) {
        debugInfo.append(message)
        print("DEBUG: \(message)")
    }
    
    private func clearDebugInfo() {
        debugInfo.removeAll()
    }
}
