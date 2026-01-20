import SwiftUI
import SwiftData

// MARK: - 債務結算結構
struct SettlementResult {
    let payer: Payer
    let netBalance: Decimal // 正數=應收，負數=應付
    let shouldPayTo: Payer? // 應付款給誰
    let amount: Decimal     // 應付金額
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
        let subcategoryIDs = allSubcategories
            .filter { $0.parentID == category.id }
            .map { $0.id }
        
        if subcategoryIDs.isEmpty {
            return []
        }
        
        return allTransactions.filter { transaction in
            guard let subID = transaction.subcategoryID,
                  subcategoryIDs.contains(subID) else {
                return false
            }
            
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
                Section {
                    PayerHeaderView(
                        payer: payer,
                        transactionCount: payerTransactions.count
                    )
                }
                
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
    
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Payer.order) private var allPayers: [Payer]
    
    @State private var participants: [Payer] = []
    @State private var settlementResults: [SettlementResult] = []
    @State private var settlementSteps: [(from: Payer, to: Payer, amount: Decimal)] = []
    @State private var selectedPayer: Payer?
    @State private var showPayerTransactions = false
    
    // 添加除錯狀態
    @State private var debugInfo: [String] = []
    
    private var categoryTransactions: [Transaction] {
        let subcategoryIDs = allSubcategories
            .filter { $0.parentID == category.id }
            .map { $0.id }
        
        if subcategoryIDs.isEmpty {
            return []
        }
        
        return allTransactions.filter { transaction in
            if let subID = transaction.subcategoryID {
                return subcategoryIDs.contains(subID)
            }
            return false
        }.filter { $0.type == .expense } // 只計算支出類交易
    }
    
    // MARK: - 正確的計算函數
    
    // 計算某付款人的總實付金額
    private func totalPaidByPayer(_ payer: Payer) -> Decimal {
        return categoryTransactions.reduce(Decimal(0)) { total, transaction in
            // 找出此付款人在此交易中的貢獻
            if let contribution = transaction.contributions.first(where: { $0.payer.id == payer.id }) {
                return total + contribution.amount
            }
            return total
        }
    }
    
    // 獲取此分類的所有參與者（優先使用已分配的付款人）
    private func getAllParticipants() -> [Payer] {
        // 先從已分配的付款人中獲取
        let assignedPayers = category.assignedPayers(in: context)
        if !assignedPayers.isEmpty {
            addDebugInfo("使用已分配的付款人: \(assignedPayers.map { $0.name }.joined(separator: ", "))")
            return assignedPayers
        }
        
        // 如果沒有已分配的付款人，則從交易中動態計算
        var participantIDs = Set<UUID>()
        for transaction in categoryTransactions {
            for contribution in transaction.contributions {
                participantIDs.insert(contribution.payer.id)
            }
        }
        
        let dynamicParticipants = allPayers.filter { participantIDs.contains($0.id) }
        addDebugInfo("使用動態參與者: \(dynamicParticipants.map { $0.name }.joined(separator: ", "))")
        return dynamicParticipants
    }
    
    // 計算每人應付金額（每筆交易平均分攤法）
    private func calculateAveragePerTransaction() -> [Payer: Decimal] {
        var shouldPayAmounts: [Payer: Decimal] = [:]
        
        // 初始化每人應付總額為 0
        for payer in participants {
            shouldPayAmounts[payer] = 0
        }
        
        // 逐筆交易計算平均分攤
        for transaction in categoryTransactions {
            let participantCount = Decimal(participants.count)
            if participantCount == 0 { continue }
            
            let perPersonAmount = transaction.totalAmount / participantCount
            
            addDebugInfo("交易 \(transaction.date.formatted(date: .abbreviated, time: .omitted)): \(formatCurrency(transaction.totalAmount))")
            addDebugInfo("  每人應付: \(formatCurrency(perPersonAmount))")
            
            // 每人都應付平均金額
            for payer in participants {
                shouldPayAmounts[payer] = (shouldPayAmounts[payer] ?? 0) + perPersonAmount
            }
        }
        
        // 打印每人應付總額
        for payer in participants {
            let shouldPay = shouldPayAmounts[payer] ?? 0
            addDebugInfo("\(payer.name) 應付總額: \(formatCurrency(shouldPay))")
        }
        
        return shouldPayAmounts
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
                        
                        // 計算總金額
                        let totalAmount = categoryTransactions.reduce(Decimal(0)) { $0 + $1.totalAmount }
                        Text("總金額：\(formatCurrency(totalAmount))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // 顯示分配狀態
                        let assignedPayers = category.assignedPayers(in: context)
                        if !assignedPayers.isEmpty {
                            Text("已分配付款人：\(assignedPayers.map { $0.name }.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
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
                    Text("此分類暫無交易記錄或未分配付款人")
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
            
            // 詳細計算結果
            if !settlementResults.isEmpty {
                Section("詳細計算結果") {
                    ForEach(settlementResults, id: \.payer.id) { result in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Circle()
                                    .fill(Color(hex: result.payer.colorHex ?? "#A8A8A8"))
                                    .frame(width: 12, height: 12)
                                
                                Text(result.payer.name)
                                    .font(.headline)
                                
                                Spacer()
                                
                                let paid = totalPaidByPayer(result.payer)
                                Text("實付：\(formatCurrency(paid))")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                            
                            HStack {
                                Text("淨結餘：")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(formatCurrency(result.netBalance))
                                    .font(.body)
                                    .foregroundColor(result.netBalance > 0 ? .green : (result.netBalance < 0 ? .red : .primary))
                                
                                Spacer()
                                
                                if let toPayer = result.shouldPayTo {
                                    Text("應付款給 \(toPayer.name)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            
            // 除錯信息區塊
            if !debugInfo.isEmpty {
                Section("計算詳情") {
                    ForEach(debugInfo.indices, id: \.self) { index in
                        Text(debugInfo[index])
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 1)
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
            calculateSettlement()
        }
        .sheet(isPresented: $showPayerTransactions) {
            if let payer = selectedPayer {
                PayerTransactionsView(payer: payer, category: category)
            }
        }
    }
    
    // MARK: - 方法
    
    private func addDebugInfo(_ message: String) {
        debugInfo.append(message)
        print("DEBUG: \(message)")
    }
    
    private func clearDebugInfo() {
        debugInfo.removeAll()
    }
    
    private func calculateSettlement() {
        clearDebugInfo()
        addDebugInfo("=== 開始計算結算 ===")
        addDebugInfo("分類: \(category.name)")
        addDebugInfo("計算方法: 每筆交易平均分攤法")
        
        // 獲取所有參與者
        participants = getAllParticipants()
        
        if participants.isEmpty {
            addDebugInfo("警告：沒有找到參與者")
            settlementResults = []
            settlementSteps = []
            return
        }
        
        addDebugInfo("參與者數量: \(participants.count)")
        
        // 計算分類總金額
        let totalCategoryAmount = categoryTransactions.reduce(Decimal(0)) { $0 + $1.totalAmount }
        addDebugInfo("分類總金額: \(formatCurrency(totalCategoryAmount))")
        
        // 1. 計算每人實付金額
        var paidAmounts: [Payer: Decimal] = [:]
        for payer in participants {
            let paid = totalPaidByPayer(payer)
            paidAmounts[payer] = paid
            addDebugInfo("\(payer.name) 實付: \(formatCurrency(paid))")
        }
        
        // 2. 計算每人應付金額（每筆交易平均分攤）
        let shouldPayAmounts = calculateAveragePerTransaction()
        
        // 3. 計算淨結餘
        var netBalances: [Payer: Decimal] = [:]
        var results: [SettlementResult] = []
        
        addDebugInfo("--- 淨結餘計算 ---")
        for payer in participants {
            let paid = paidAmounts[payer] ?? 0
            let shouldPay = shouldPayAmounts[payer] ?? 0
            let netBalance = paid - shouldPay
            
            netBalances[payer] = netBalance
            
            addDebugInfo("\(payer.name): 實付=\(formatCurrency(paid)), 應付=\(formatCurrency(shouldPay)), 淨結餘=\(formatCurrency(netBalance))")
            
            results.append(SettlementResult(
                payer: payer,
                netBalance: netBalance,
                shouldPayTo: nil,
                amount: 0
            ))
        }
        
        // 4. 計算最優結算步驟
        settlementSteps = calculateOptimalSettlement(balances: netBalances)
        
        // 5. 更新結算結果中的應付款信息
        for step in settlementSteps {
            if let index = results.firstIndex(where: { $0.payer.id == step.from.id }) {
                results[index] = SettlementResult(
                    payer: step.from,
                    netBalance: netBalances[step.from] ?? 0,
                    shouldPayTo: step.to,
                    amount: step.amount
                )
            }
        }
        
        settlementResults = results.sorted { $0.netBalance > $1.netBalance }
        
        // 檢查計算是否平衡
        let totalNetBalance = netBalances.values.reduce(0, +)
        if abs(totalNetBalance) > 0.01 {
            addDebugInfo("警告：計算不平衡，淨結餘總和 = \(formatCurrency(totalNetBalance))")
        } else {
            addDebugInfo("計算平衡，淨結餘總和 ≈ 0")
        }
        
        addDebugInfo("=== 計算完成 ===")
    }
    
    // 計算最優結算方案（最少轉帳次數）
    private func calculateOptimalSettlement(balances: [Payer: Decimal]) -> [(from: Payer, to: Payer, amount: Decimal)] {
        var creditors: [(payer: Payer, amount: Decimal)] = [] // 應收款人（正數）
        var debtors: [(payer: Payer, amount: Decimal)] = []   // 應付款人（負數）
        
        // 分離收款人和付款人
        for (payer, balance) in balances {
            if balance > 0 {
                creditors.append((payer: payer, amount: balance))
                addDebugInfo("收款人: \(payer.name) (+\(formatCurrency(balance)))")
            } else if balance < 0 {
                debtors.append((payer: payer, amount: -balance)) // 轉為正數
                addDebugInfo("付款人: \(payer.name) (-\(formatCurrency(-balance)))")
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
                addDebugInfo("結算步驟: \(debtor.payer.name) → \(creditor.payer.name) 金額: \(formatCurrency(settleAmount))")
            }
            
            // 更新剩餘金額
            creditors[i].amount -= settleAmount
            debtors[j].amount -= settleAmount
            
            // 如果某人金額清零，移動到下一個
            if creditors[i].amount == 0 { i += 1 }
            if debtors[j].amount == 0 { j += 1 }
        }
        
        addDebugInfo("總共需要 \(steps.count) 筆轉帳")
        return steps
    }
}
