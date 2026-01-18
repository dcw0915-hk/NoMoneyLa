import SwiftUI
import SwiftData

// MARK: - 債務結算結構
struct SettlementResult {
    let payer: Payer
    let netBalance: Decimal // 正數=應收，負數=應付
    let shouldPayTo: Payer? // 應付款給誰
    let amount: Decimal     // 應付金額
}

// MARK: - 工具函數
func formatCurrency(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "HKD"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
}

// MARK: - 付款人交易行視圖
struct PayerTransactionRowView: View {
    let transaction: Transaction
    let payer: Payer
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(transaction.date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text(formatCurrency(transaction.totalAmount))
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
            
            // 顯示此付款人在此交易中的分攤
            if let contribution = transaction.contributions.first(where: { $0.payer.id == payer.id }) {
                HStack {
                    Text("分攤：")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Text(formatCurrency(contribution.amount))
                        .font(.caption2)
                        .bold()
                    
                    Text("(總額\(formatCurrency(transaction.totalAmount)))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - 統計行視圖
struct PayerStatsRowView: View {
    let title: String
    let value: String
    let valueColor: Color
    
    init(title: String, value: Decimal, valueColor: Color = .primary) {
        self.title = title
        self.value = formatCurrency(value)
        self.valueColor = valueColor
    }
    
    init(title: String, value: Int, valueColor: Color = .primary) {
        self.title = title
        self.value = "\(value)"
        self.valueColor = valueColor
    }
    
    var body: some View {
        HStack {
            Text(title)
                .font(.body)
            
            Spacer()
            
            Text(value)
                .font(.headline)
                .foregroundColor(valueColor)
        }
    }
}

// MARK: - 付款人標題視圖
struct PayerHeaderView: View {
    let payer: Payer
    let transactionCount: Int
    
    var body: some View {
        HStack {
            Circle()
                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                .frame(width: 24, height: 24)
            
            Text(payer.name)
                .font(.title2)
                .bold()
            
            Spacer()
            
            Text("\(transactionCount) 筆交易")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - 付款人交易詳細視圖
struct PayerTransactionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    
    let payer: Payer
    let category: Category
    
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    
    private var payerTransactions: [Transaction] {
        // 獲取此分類的所有子分類ID
        let subcategoryIDs = allSubcategories
            .filter { $0.parentID == category.id }
            .map { $0.id }
        
        if subcategoryIDs.isEmpty {
            return []
        }
        
        // 篩選：屬於此分類且包含此付款人
        return allTransactions.filter { transaction in
            // 檢查是否屬於此分類
            guard let subID = transaction.subcategoryID,
                  subcategoryIDs.contains(subID) else {
                return false
            }
            
            // 檢查是否包含此付款人
            return transaction.contributions.contains { $0.payer.id == payer.id }
        }
    }
    
    private var totalPaid: Decimal {
        payerTransactions.reduce(Decimal(0)) { total, transaction in
            let payerContributions = transaction.contributions.filter { $0.payer.id == payer.id }
            let contributionSum = payerContributions.reduce(Decimal(0)) { $0 + $1.amount }
            return total + contributionSum
        }
    }
    
    var body: some View {
        NavigationStack {
            List {
                // 標題
                Section {
                    PayerHeaderView(
                        payer: payer,
                        transactionCount: payerTransactions.count
                    )
                }
                
                // 交易列表
                Section("交易記錄") {
                    if payerTransactions.isEmpty {
                        Text("此分類中無此付款人的交易記錄")
                            .foregroundColor(.secondary)
                            .italic()
                    } else {
                        ForEach(payerTransactions) { transaction in
                            PayerTransactionRowView(
                                transaction: transaction,
                                payer: payer
                            )
                        }
                    }
                }
                
                // 統計
                Section("統計") {
                    PayerStatsRowView(
                        title: "實付總額",
                        value: totalPaid,
                        valueColor: .blue
                    )
                    
                    PayerStatsRowView(
                        title: "參與交易數",
                        value: payerTransactions.count,
                        valueColor: .secondary
                    )
                }
            }
            .navigationTitle("交易詳情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - 主要視圖
struct CategorySettlementView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    let category: Category
    
    // 查詢
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Payer.order) private var allPayers: [Payer]
    
    // 狀態
    @State private var participants: [Payer] = []
    @State private var settlementResults: [SettlementResult] = []
    @State private var settlementSteps: [(from: Payer, to: Payer, amount: Decimal)] = []
    @State private var selectedPayer: Payer?
    @State private var showPayerTransactions = false
    
    // 計算此分類下的交易
    private var categoryTransactions: [Transaction] {
        // 獲取此分類的所有子分類ID
        let subcategoryIDs = allSubcategories
            .filter { $0.parentID == category.id }
            .map { $0.id }
        
        if subcategoryIDs.isEmpty {
            return []
        }
        
        // 篩選屬於此分類的交易
        return allTransactions.filter { transaction in
            if let subID = transaction.subcategoryID {
                return subcategoryIDs.contains(subID)
            }
            return false
        }
    }
    
    // MARK: - 修正的計算函數
    
    // 計算某付款人在此分類的總支出（已支付的金額）
    private func totalPaidByPayer(_ payer: Payer) -> Decimal {
        return categoryTransactions.reduce(Decimal(0)) { total, transaction in
            let payerContributions = transaction.contributions.filter { $0.payer.id == payer.id }
            let contributionSum = payerContributions.reduce(Decimal(0)) { $0 + $1.amount }
            return total + contributionSum
        }
    }
    
    // 計算某付款人應付金額（修正版本）
    private func totalShouldPayByPayer(_ payer: Payer) -> Decimal {
        // 先找出此付款人參與的所有交易
        let relevantTransactions = categoryTransactions.filter { transaction in
            transaction.contributions.contains { $0.payer.id == payer.id }
        }
        
        // 如果沒有參與任何交易，應付為0
        if relevantTransactions.isEmpty {
            return 0
        }
        
        // 計算所有參與交易的總金額
        let totalTransactionsAmount = relevantTransactions.reduce(Decimal(0)) { $0 + $1.totalAmount }
        
        // 計算此付款人在所有交易中的總貢獻
        let totalPaidByThisPayer = relevantTransactions.reduce(Decimal(0)) { total, transaction in
            let payerContribution = transaction.contributions
                .first { $0.payer.id == payer.id }?.amount ?? 0
            return total + payerContribution
        }
        
        // 如果總貢獻為0，應付為0
        if totalPaidByThisPayer == 0 {
            return 0
        }
        
        // 計算此付款人佔總貢獻的比例
        let payerContributionRatio = totalPaidByThisPayer / totalTransactionsAmount
        
        // 計算應付金額 = 參與交易的總金額 × 貢獻比例
        return totalTransactionsAmount * payerContributionRatio
    }
    
    var body: some View {
        List {
            // 分類摘要
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(category.name)
                            .font(.title2)
                            .bold()
                        
                        Text("總交易數：\(categoryTransactions.count)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Text("總金額：\(formatCurrency(category.totalAmount(in: context)))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let colorHex = category.colorHex {
                        Circle()
                            .fill(Color(hex: colorHex))
                            .frame(width: 40, height: 40)
                    }
                }
                .padding(.vertical, 4)
            }
            
            // 參與者列表
            Section("參與者") {
                if participants.isEmpty {
                    Text("此分類暫無交易記錄")
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    ForEach(participants) { payer in
                        HStack {
                            Circle()
                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                .frame(width: 16, height: 16)
                            
                            Text(payer.name)
                                .font(.body)
                            
                            Spacer()
                            
                            // 顯示淨結餘
                            if let result = settlementResults.first(where: { $0.payer.id == payer.id }) {
                                Text(formatCurrency(result.netBalance))
                                    .font(.body)
                                    .foregroundColor(result.netBalance > 0 ? .green : (result.netBalance < 0 ? .red : .primary))
                            }
                            
                            Button {
                                selectedPayer = payer
                                showPayerTransactions = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(.blue)
                            }
                            .buttonStyle(BorderlessButtonStyle())
                            .padding(.leading, 8)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // 結算方案
            if !settlementSteps.isEmpty {
                Section("最優結算方案") {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("只需 \(settlementSteps.count) 筆轉帳即可清零所有債務")
                            .font(.headline)
                            .foregroundColor(.green)
                        
                        ForEach(settlementSteps.indices, id: \.self) { index in
                            let step = settlementSteps[index]
                            HStack {
                                Text("\(index + 1).")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Circle()
                                    .fill(Color(hex: step.from.colorHex ?? "#A8A8A8"))
                                    .frame(width: 12, height: 12)
                                
                                Text(step.from.name)
                                    .font(.body)
                                
                                Text("付款")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Circle()
                                    .fill(Color(hex: step.to.colorHex ?? "#A8A8A8"))
                                    .frame(width: 12, height: 12)
                                
                                Text(step.to.name)
                                    .font(.body)
                                
                                Spacer()
                                
                                Text(formatCurrency(step.amount))
                                    .font(.body)
                                    .bold()
                                    .foregroundColor(.blue)
                            }
                            .padding(.vertical, 2)
                        }
                        
                        Text("完成後所有人債務清零 ✅")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
            
            // 詳細計算（用於調試）
            if !settlementResults.isEmpty {
                Section("詳細計算（調試）") {
                    ForEach(settlementResults, id: \.payer.id) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: result.payer.colorHex ?? "#A8A8A8"))
                                    .frame(width: 12, height: 12)
                                
                                Text(result.payer.name)
                                    .font(.headline)
                                
                                Spacer()
                                
                                Text("淨結餘：\(formatCurrency(result.netBalance))")
                                    .font(.body)
                                    .foregroundColor(result.netBalance > 0 ? .green : (result.netBalance < 0 ? .red : .primary))
                            }
                            
                            let paid = totalPaidByPayer(result.payer)
                            let shouldPay = totalShouldPayByPayer(result.payer)
                            
                            HStack {
                                Text("實付：\(formatCurrency(paid))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("應付：\(formatCurrency(shouldPay))")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text("差值：\(formatCurrency(paid - shouldPay))")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("債務結算")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("重新計算") {
                    calculateSettlement()
                }
            }
        }
        .onAppear {
            loadParticipants()
            calculateSettlement()
        }
        .sheet(isPresented: $showPayerTransactions) {
            if let payer = selectedPayer {
                PayerTransactionsView(payer: payer, category: category)
            }
        }
    }
    
    // MARK: - 方法
    
    private func loadParticipants() {
        participants = category.participants(in: context)
    }
    
    private func calculateSettlement() {
        // 1. 計算每人淨結餘
        var balances: [Payer: Decimal] = [:]
        
        for payer in participants {
            let paid = totalPaidByPayer(payer)
            let shouldPay = totalShouldPayByPayer(payer)
            let netBalance = paid - shouldPay
            balances[payer] = netBalance
            print("\(payer.name): 實付=\(paid), 應付=\(shouldPay), 淨結餘=\(netBalance)")
        }
        
        // 2. 生成結算結果
        var results: [SettlementResult] = []
        for (payer, balance) in balances {
            results.append(SettlementResult(
                payer: payer,
                netBalance: balance,
                shouldPayTo: nil,
                amount: 0
            ))
        }
        
        // 3. 計算最優結算步驟
        settlementSteps = calculateOptimalSettlement(balances: balances)
        
        // 4. 更新結算結果中的應付款信息
        for step in settlementSteps {
            if let index = results.firstIndex(where: { $0.payer.id == step.from.id }) {
                results[index] = SettlementResult(
                    payer: step.from,
                    netBalance: balances[step.from] ?? 0,
                    shouldPayTo: step.to,
                    amount: step.amount
                )
            }
        }
        
        settlementResults = results.sorted { $0.netBalance > $1.netBalance }
    }
    
    // 計算最優結算方案（最少轉帳次數）
    private func calculateOptimalSettlement(balances: [Payer: Decimal]) -> [(from: Payer, to: Payer, amount: Decimal)] {
        var creditors: [(payer: Payer, amount: Decimal)] = [] // 應收款人（正數）
        var debtors: [(payer: Payer, amount: Decimal)] = []   // 應付款人（負數）
        
        // 分離收款人和付款人
        for (payer, balance) in balances {
            if balance > 0 {
                creditors.append((payer: payer, amount: balance))
            } else if balance < 0 {
                debtors.append((payer: payer, amount: -balance)) // 轉為正數
            }
        }
        
        // 排序：金額大的優先處理
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
            
            // 更新剩餘金額
            creditors[i].amount -= settleAmount
            debtors[j].amount -= settleAmount
            
            // 如果某人金額清零，移動到下一個
            if creditors[i].amount == 0 { i += 1 }
            if debtors[j].amount == 0 { j += 1 }
        }
        
        return steps
    }
}
