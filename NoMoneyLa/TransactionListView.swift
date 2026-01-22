import SwiftUI
import SwiftData

// MARK: - CardModifier
struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemBackground))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
            )
    }
}

extension View {
    func cardStyle() -> some View {
        self.modifier(CardModifier())
    }
}

// MARK: - TransactionCardView
struct TransactionCardView: View {
    let transaction: Transaction
    let categoryName: String
    let formatPayerText: (Transaction) -> String
    let formatCurrency: (Decimal, String) -> String
    let format: (Decimal, String) -> String
    let getContributionStatus: (Transaction) -> (message: String, icon: String, color: Color)
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(categoryName)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if let note = transaction.note, !note.isEmpty {
                        Text(note)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    if !transaction.contributions.isEmpty {
                        Text(formatPayerText(transaction))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    Text(transaction.date, format: .dateTime.year().month().day())
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text(format(transaction.totalAmount, transaction.currencyCode))
                        .font(.title3)
                        .bold()
                        .foregroundColor(transaction.type == .expense ? .red : .green)
                    
                    // 顯示分攤狀態警告
                    if transaction.type == .expense {
                        let contributionStatus = getContributionStatus(transaction)
                        if !contributionStatus.message.isEmpty {
                            HStack(spacing: 2) {
                                Image(systemName: contributionStatus.icon)
                                    .font(.caption2)
                                    .foregroundColor(contributionStatus.color)
                                Text(contributionStatus.message)
                                    .font(.caption2)
                                    .foregroundColor(contributionStatus.color)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            }
            
            // 如果有分攤問題，顯示詳細訊息
            if transaction.type == .expense && !transaction.isAmountValid && !transaction.contributions.isEmpty {
                let totalContributed = transaction.contributions.reduce(0) { $0 + $1.amount }
                let difference = transaction.totalAmount - totalContributed
                
                if difference > 0 {
                    // 分攤不足
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.orange)
                        Text("分攤不足：\(formatCurrency(difference, transaction.currencyCode))")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                    .padding(.top, 2)
                } else if difference < 0 {
                    // 分攤過多
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                        Text("分攤過多：\(formatCurrency(abs(difference), transaction.currencyCode))")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                    .padding(.top, 2)
                }
            }
        }
    }
}

// MARK: - TransactionListView
struct TransactionListView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Subcategory.order) private var subcategories: [Subcategory]
    @Query(sort: \Payer.order) private var payers: [Payer]

    @State private var searchText = ""
    
    // 新增：可選的預設篩選參數
    let initialFilterPayer: Payer?
    let initialFilterPeriod: TimePeriod?
    let initialFilterDate: Date?
    
    // 原本的篩選狀態
    @AppStorage("filterTypeRaw") private var filterTypeRaw: String = ""
    @AppStorage("filterCategoryName") private var filterCategoryName: String = ""
    @AppStorage("filterSubcategoryName") private var filterSubcategoryName: String = ""
    @AppStorage("filterPayerName") private var filterPayerName: String = ""  // 新增：付款人篩選存儲

    @State private var filterType: TransactionType? = nil
    @State private var filterCategory: Category? = nil
    @State private var filterSubcategory: Subcategory? = nil
    @State private var filterPayer: Payer? = nil  // 新增：付款人篩選
    @State private var filterStartDate: Date? = nil  // 新增：開始日期
    @State private var filterEndDate: Date? = nil    // 新增：結束日期

    // 初始化函數
    init(
        filterPayer: Payer? = nil,
        filterPeriod: TimePeriod? = nil,
        filterDate: Date? = nil
    ) {
        self.initialFilterPayer = filterPayer
        self.initialFilterPeriod = filterPeriod
        self.initialFilterDate = filterDate
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 過濾器欄位
                if shouldShowFilterBar {
                    FilterBarView(
                        filterType: filterType,
                        filterCategory: filterCategory,
                        filterSubcategory: filterSubcategory,
                        filterPayer: filterPayer,
                        filterDateRange: formattedDateRange(),
                        searchText: searchText,
                        clearFilters: clearFilters
                    )
                }
                
                // 交易列表
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredTransactions()) { tx in
                            NavigationLink(
                                destination: TransactionFormView(transaction: tx, isEditing: false)
                            ) {
                                TransactionCardView(
                                    transaction: tx,
                                    categoryName: categoryName(for: tx.subcategoryID),
                                    formatPayerText: formatPayerText,
                                    formatCurrency: formatCurrency,
                                    format: format,
                                    getContributionStatus: getContributionStatus
                                )
                                .cardStyle()
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    delete(tx: tx)
                                } label: {
                                    Label(langManager.localized("delete_button"), systemImage: "trash")
                                }
                            }
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                }
            }
            .navigationTitle(getNavigationTitle())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ToolbarMenuView(
                        categories: categories,
                        subcategories: subcategories,
                        payers: payers,
                        filterCategory: filterCategory,
                        filterType: filterType,
                        filterSubcategory: filterSubcategory,
                        filterPayer: filterPayer,
                        onSelectType: { newType in
                            filterType = newType
                            saveFilterState()
                        },
                        onSelectCategory: { newCategory in
                            filterCategory = newCategory
                            filterSubcategory = nil
                            saveFilterState()
                        },
                        onSelectSubcategory: { newSubcategory in
                            filterSubcategory = newSubcategory
                            saveFilterState()
                        },
                        onSelectPayer: { newPayer in
                            filterPayer = newPayer
                            saveFilterState()
                        },
                        saveFilterState: saveFilterState
                    )
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(
                        destination: TransactionFormView(isEditing: true)
                    ) {
                        Label(langManager.localized("form_add_title"), systemImage: "plus.circle.fill")
                            .font(.headline)
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text(langManager.localized("search_placeholder")))
            .onAppear {
                restoreFilterState()
                applyInitialFilters()
            }
        }
    }
    
    private var shouldShowFilterBar: Bool {
        filterType != nil || filterCategory != nil || filterSubcategory != nil ||
        filterPayer != nil || filterStartDate != nil || !searchText.isEmpty
    }
    
    private func clearFilters() {
        filterType = nil
        filterCategory = nil
        filterSubcategory = nil
        filterPayer = nil
        filterStartDate = nil
        filterEndDate = nil
        searchText = ""
        saveFilterState()
    }

    private func filteredTransactions() -> [Transaction] {
        let keyword = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var result = transactions
        
        // 篩選交易類型
        if let type = filterType {
            result = result.filter { $0.type == type }
        }
        
        // 篩選分類
        if let cat = filterCategory {
            result = result.filter { tx in
                guard let txSubID = tx.subcategoryID else { return false }
                return subcategories.first(where: { $0.id == txSubID })?.parentID == cat.id
            }
        }
        
        // 篩選子分類
        if let sub = filterSubcategory {
            result = result.filter { $0.subcategoryID == sub.id }
        }
        
        // 篩選付款人
        if let payer = filterPayer {
            result = result.filter { tx in
                tx.contributions.contains { $0.payer.id == payer.id }
            }
        }
        
        // 篩選日期範圍
        if let startDate = filterStartDate, let endDate = filterEndDate {
            result = result.filter { tx in
                tx.date >= startDate && tx.date <= endDate
            }
        }
        
        // 關鍵詞搜索
        guard !keyword.isEmpty else { return result }

        return result.filter { tx in
            let catName = categoryName(for: tx.subcategoryID)
            let note = tx.note ?? ""
            let parentName: String = {
                if let subID = tx.subcategoryID,
                   let sub = subcategories.first(where: { $0.id == subID }),
                   let parent = categories.first(where: { $0.id == sub.parentID }) {
                    return parent.name
                }
                return ""
            }()
            
            let payerNames = tx.contributions.map { $0.payer.name }.joined(separator: " ")

            let haystack = [catName, note, parentName, payerNames]
                .joined(separator: " ")
                .lowercased()

            return haystack.contains(keyword)
        }
    }

    private func formatPayerText(for transaction: Transaction) -> String {
        if transaction.contributions.isEmpty {
            return "無付款人"
        }
        
        if transaction.contributions.count == 1,
           let contribution = transaction.contributions.first {
            return "\(contribution.payer.name): \(formatCurrency(contribution.amount, transaction.currencyCode))"
        } else {
            let payerCount = transaction.contributions.count
            let totalAmount = transaction.contributions.reduce(0) { $0 + $1.amount }
            return "\(payerCount)人分攤，共\(formatCurrency(totalAmount, transaction.currencyCode))"
        }
    }
    
    // 獲取分攤狀態
    private func getContributionStatus(for transaction: Transaction) -> (message: String, icon: String, color: Color) {
        if transaction.contributions.isEmpty {
            return ("未分攤", "exclamationmark.circle", .orange)
        }
        
        let totalContributed = transaction.contributions.reduce(0) { $0 + $1.amount }
        let difference = transaction.totalAmount - totalContributed
        
        if difference == 0 {
            return ("", "", .clear) // 分攤完成，不顯示警告
        } else if difference > 0 {
            // 分攤不足
            let amount = formatCurrency(difference, transaction.currencyCode)
            return ("不足 \(amount)", "exclamationmark.triangle", .orange)
        } else {
            // 分攤過多
            let amount = formatCurrency(abs(difference), transaction.currencyCode)
            return ("過多 \(amount)", "exclamationmark.triangle.fill", .red)
        }
    }
    
    private func formatCurrency(_ amount: Decimal, _ code: String) -> String {
        let ns = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        return formatter.string(from: ns) ?? "\(amount)"
    }

    private func delete(tx: Transaction) {
        context.delete(tx)
        do {
            try context.save()
        } catch {
            print("刪除失敗：\(error.localizedDescription)")
        }
    }

    private func saveFilterState() {
        filterTypeRaw = filterType?.rawValue ?? ""
        filterCategoryName = filterCategory?.name ?? ""
        filterSubcategoryName = filterSubcategory?.name ?? ""
        filterPayerName = filterPayer?.name ?? ""  // 保存付款人名稱
    }

    private func restoreFilterState() {
        filterType = TransactionType(rawValue: filterTypeRaw)

        if !filterCategoryName.isEmpty {
            filterCategory = categories.first { $0.name == filterCategoryName }
        } else {
            filterCategory = nil
        }

        if !filterSubcategoryName.isEmpty {
            filterSubcategory = subcategories.first { $0.name == filterSubcategoryName }
        } else {
            filterSubcategory = nil
        }
        
        // 恢復付款人篩選
        if !filterPayerName.isEmpty {
            filterPayer = payers.first { $0.name == filterPayerName }
        } else {
            filterPayer = nil
        }
    }
    
    private func applyInitialFilters() {
        // 應用初始篩選參數
        filterPayer = initialFilterPayer
        
        if let period = initialFilterPeriod, let date = initialFilterDate {
            let (startDate, endDate) = calculateDateRange(period: period, date: date)
            filterStartDate = startDate
            filterEndDate = endDate
        }
    }
    
    private func calculateDateRange(period: TimePeriod, date: Date) -> (startDate: Date, endDate: Date) {
        let calendar = Calendar.current
        var startDate: Date
        var endDate: Date
        
        switch period {
        case .month:
            let components = calendar.dateComponents([.year, .month], from: date)
            startDate = calendar.date(from: components)!
            
            var endComponents = DateComponents()
            endComponents.month = 1
            endComponents.day = -1
            endDate = calendar.date(byAdding: endComponents, to: startDate)!
            
        case .year:
            let components = calendar.dateComponents([.year], from: date)
            startDate = calendar.date(from: components)!
            
            var endComponents = DateComponents()
            endComponents.year = 1
            endComponents.day = -1
            endDate = calendar.date(byAdding: endComponents, to: startDate)!
        }
        
        return (startDate, endDate)
    }
    
    private func formattedDateRange() -> String? {
        guard let startDate = filterStartDate, let endDate = filterEndDate else {
            return nil
        }
        
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        
        return "\(formatter.string(from: startDate))-\(formatter.string(from: endDate))"
    }
    
    private func getNavigationTitle() -> String {
        if filterPayer != nil || filterStartDate != nil {
            var parts: [String] = []
            
        if let payer = filterPayer {
            parts.append(payer.name)
        }
        
        if let startDate = filterStartDate, let endDate = filterEndDate {
            let formatter = DateFormatter()
            if Calendar.current.isDate(startDate, equalTo: endDate, toGranularity: .month) {
                formatter.dateFormat = "yyyy年M月"
                parts.append(formatter.string(from: startDate))
            } else if Calendar.current.isDate(startDate, equalTo: endDate, toGranularity: .year) {
                formatter.dateFormat = "yyyy年"
                parts.append(formatter.string(from: startDate))
            } else {
                formatter.dateFormat = "M/d"
                parts.append("\(formatter.string(from: startDate))-\(formatter.string(from: endDate))")
            }
        }
        
        return parts.joined(separator: " - ")
    }
    
    return langManager.localized("transactions_title")
    }

    private func categoryName(for subID: UUID?) -> String {
        guard let subID = subID else { return langManager.localized("form_none") }
        if let sub = subcategories.first(where: { $0.id == subID }),
           let parent = categories.first(where: { $0.id == sub.parentID }) {
            return "\(parent.name) / \(sub.name)"
        }
        return subcategories.first(where: { $0.id == subID })?.name ?? langManager.localized("form_none")
    }

    private func format(_ amount: Decimal, _ code: String = "HKD") -> String {
        let ns = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        return formatter.string(from: ns) ?? "\(amount)"
    }
}
