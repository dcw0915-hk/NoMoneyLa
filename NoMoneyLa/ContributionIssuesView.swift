import SwiftUI
import SwiftData
import WidgetKit   // 新增

struct ContributionIssuesView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    
    @Query(sort: \Transaction.date, order: .reverse) private var allTransactions: [Transaction]
    @Query(sort: \Category.order) private var allCategories: [Category]
    @Query(sort: \Subcategory.order) private var allSubcategories: [Subcategory]
    @Query(sort: \Payer.order) private var allPayers: [Payer]
    
    @State private var isLoading = false
    @State private var showingFixAllAlert = false
    
    // 分組顯示有問題的交易
    private var invalidTransactions: [Transaction] {
        allTransactions.filter { !$0.isAmountValid && $0.type == .expense }
    }
    
    // 按分類分組
    private var transactionsByCategory: [UUID: [Transaction]] {
        var result: [UUID: [Transaction]] = [:]
        
        for transaction in invalidTransactions {
            guard let subcategoryID = transaction.subcategoryID else { continue }
            
            // 找出父分類ID
            if let subcategory = allSubcategories.first(where: { $0.id == subcategoryID }) {
                let categoryID = subcategory.parentID
                if result[categoryID] == nil {
                    result[categoryID] = []
                }
                result[categoryID]?.append(transaction)
            } else {
                // 如果找不到子分類，使用預設分類
                if let defaultCategory = allCategories.first(where: { $0.isDefault }) {
                    let categoryID = defaultCategory.id
                    if result[categoryID] == nil {
                        result[categoryID] = []
                    }
                    result[categoryID]?.append(transaction)
                }
            }
        }
        
        return result
    }
    
    // 計算總差異金額
    private var totalMissingAmount: Decimal {
        invalidTransactions.reduce(Decimal(0)) { total, transaction in
            let sum = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            let difference = transaction.totalAmount - sum
            return total + difference
        }
    }
    
    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView(langManager.localized("loading_label"))
                        .padding()
                } else if invalidTransactions.isEmpty {
                    ContentUnavailableView(
                        langManager.localized("no_contribution_issues_title"),
                        systemImage: "checkmark.circle.fill",
                        description: Text(langManager.localized("no_contribution_issues_description"))
                    )
                } else {
                    List {
                        // 摘要統計
                        Section {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.title2)
                                        .foregroundColor(.orange)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(langManager.localized("contribution_issues_found_title"))
                                            .font(.headline)
                                            .foregroundColor(.primary)
                                        
                                        Text(String(format: langManager.localized("transactions_need_fix_format"), invalidTransactions.count))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                
                                Divider()
                                
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(langManager.localized("total_difference_label"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text(formatCurrency(totalMissingAmount))
                                            .font(.title2)
                                            .bold()
                                            .foregroundColor(totalMissingAmount > 0 ? .orange : .green)
                                    }
                                    
                                    Spacer()
                                    
                                    VStack(alignment: .trailing, spacing: 2) {
                                        Text(langManager.localized("involved_categories_label"))
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        
                                        Text(String(format: langManager.localized("count_categories_format"), transactionsByCategory.keys.count))
                                            .font(.title2)
                                            .bold()
                                    }
                                }
                            }
                            .padding(.vertical, 8)
                        }
                        
                        // 按分類顯示問題交易
                        ForEach(Array(transactionsByCategory.keys.sorted()), id: \.self) { categoryID in
                            if let category = allCategories.first(where: { $0.id == categoryID }),
                               let transactions = transactionsByCategory[categoryID] {
                                
                                Section(header: HStack {
                                    if let colorHex = category.colorHex {
                                        Circle()
                                            .fill(Color(hex: colorHex))
                                            .frame(width: 12, height: 12)
                                    }
                                    
                                    Text(category.isDefault ? langManager.localized("uncategorized_label") : category.name)
                                        .font(.headline)
                                    
                                    Spacer()
                                    
                                    Text(String(format: langManager.localized("transactions_count_format"), transactions.count))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }) {
                                    ForEach(transactions) { transaction in
                                        transactionRow(transaction)
                                    }
                                }
                            }
                        }
                        
                        // 快速修復選項
                        Section {
                            VStack(alignment: .leading, spacing: 12) {
                                Text(langManager.localized("quick_fix_title"))
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                
                                Text(langManager.localized("quick_fix_description"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                                
                                Button {
                                    showingFixAllAlert = true
                                } label: {
                                    HStack {
                                        Image(systemName: "wand.and.stars")
                                            .font(.body)
                                        Text(langManager.localized("fix_all_button"))
                                            .font(.headline)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color.blue)
                                    .foregroundColor(.white)
                                    .cornerRadius(10)
                                }
                            }
                            .padding(.vertical, 8)
                        }
                    }
                }
            }
            .navigationTitle(langManager.localized("contribution_issues_nav_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(langManager.localized("done_button")) {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        reloadData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .disabled(isLoading)
                }
            }
            .alert(langManager.localized("confirm_fix_all_title"), isPresented: $showingFixAllAlert) {
                Button(langManager.localized("cancel_button"), role: .cancel) { }
                Button(langManager.localized("fix_button"), role: .destructive) {
                    fixAllContributionIssues()
                }
            } message: {
                Text(String(format: langManager.localized("confirm_fix_all_message_format"), invalidTransactions.count))
            }
            .onAppear {
                reloadData()
            }
        }
    }
    
    private func transactionRow(_ transaction: Transaction) -> some View {
        let sum = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
        let difference = transaction.totalAmount - sum
        
        return NavigationLink {
            TransactionFormView(transaction: transaction)
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    // 日期
                    Text(transaction.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    // 金額
                    Text(formatCurrency(transaction.totalAmount))
                        .font(.body)
                        .bold()
                        .foregroundColor(.red)
                }
                
                // 備註或分類
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text(categoryName(for: transaction.subcategoryID))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                // 分攤狀態
                HStack {
                    Image(systemName: difference > 0 ? "arrow.down.circle" : "arrow.up.circle")
                        .font(.caption2)
                        .foregroundColor(difference > 0 ? .orange : .green)
                    
                    Text(transaction.contributionStatusDescription)
                        .font(.caption)
                        .foregroundColor(difference > 0 ? .orange : .green)
                    
                    Spacer()
                    
                    // 現有分攤
                    if !transaction.contributions.isEmpty {
                        Text(String(format: langManager.localized("people_count_format"), transaction.contributions.count) + " " + langManager.localized("split_label"))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                
                // 付款人列表
                if !transaction.contributions.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(transaction.contributions.prefix(3)) { contribution in
                            HStack(spacing: 2) {
                                Circle()
                                    .fill(Color(hex: contribution.payer.colorHex ?? "#A8A8A8"))
                                    .frame(width: 6, height: 6)
                                
                                Text(contribution.payer.isDefault ? langManager.localized("default_payer_name") : contribution.payer.name)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if transaction.contributions.count > 3 {
                            Text(String(format: langManager.localized("people_extra_format"), transaction.contributions.count - 3))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
            .padding(.vertical, 4)
        }
    }
    
    private func categoryName(for subID: UUID?) -> String {
        guard let subID = subID else { return langManager.localized("uncategorized_label") }
        
        if let sub = allSubcategories.first(where: { $0.id == subID }),
           let parent = allCategories.first(where: { $0.id == sub.parentID }) {
            let parentName = parent.isDefault ? langManager.localized("uncategorized_label") : parent.name
            let subName = sub.isUncategorized ? langManager.localized("uncategorized_label") : sub.name
            return "\(parentName) / \(subName)"
        }
        
        return langManager.localized("uncategorized_label")
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
    
    private func reloadData() {
        isLoading = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            isLoading = false
        }
    }
    
    private func fixAllContributionIssues() {
        var fixedCount = 0
        
        for transaction in invalidTransactions {
            if fixContribution(for: transaction) {
                fixedCount += 1
            }
        }
        
        // 保存所有更改
        do {
            try context.save()
            WidgetCenter.shared.reloadTimelines(ofKind: "NoMoneyLaWidget") // 新增
            print("成功修復 \(fixedCount) 筆交易的分攤問題")
            
            // 重新載入數據
            reloadData()
        } catch {
            print("保存修復結果時出錯: \(error)")
        }
    }
    
    private func fixContribution(for transaction: Transaction) -> Bool {
        guard transaction.type == .expense else { return false }
        
        if transaction.contributions.isEmpty {
            // 如果沒有分攤，使用預設付款人
            if let defaultPayer = allPayers.first(where: { $0.isDefault }) ?? allPayers.first {
                let contribution = PaymentContribution(
                    amount: transaction.totalAmount,
                    payer: defaultPayer,
                    transaction: transaction
                )
                context.insert(contribution)
                transaction.contributions.append(contribution)
                return true
            }
            return false
        } else {
            // 如果有分攤但金額不匹配，嘗試平均分配
            let sum = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            let difference = transaction.totalAmount - sum
            
            if abs(difference) > Decimal(0.01) {
                // 平均分配差異
                let perPersonAdjustment = difference / Decimal(transaction.contributions.count)
                
                for contribution in transaction.contributions {
                    contribution.amount += perPersonAdjustment
                }
                return true
            }
        }
        
        return false
    }
}
