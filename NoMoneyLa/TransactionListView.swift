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

// MARK: - FilterBarView
struct FilterBarView: View {
    @EnvironmentObject var langManager: LanguageManager
    let filterType: TransactionType?
    let filterCategory: Category?
    let filterSubcategory: Subcategory?
    let searchText: String
    let clearFilters: () -> Void
    
    var body: some View {
        HStack {
            Text(langManager.localized("filter_current"))
                .font(.caption)
                .foregroundStyle(.secondary)
            
            if let type = filterType {
                Text(type == .expense ? langManager.localized("expense_label") : langManager.localized("income_label"))
                    .font(.caption)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2)))
            }
            
            if let cat = filterCategory {
                Text(cat.name)
                    .font(.caption)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2)))
            }
            
            if let sub = filterSubcategory {
                Text(sub.name)
                    .font(.caption)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2)))
            }
            
            if !searchText.isEmpty {
                Text("\(langManager.localized("search_label"))：\(searchText)")
                    .font(.caption)
                    .padding(4)
                    .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.2)))
            }
            
            Spacer()
            
            Button(langManager.localized("clear_button")) {
                clearFilters()
            }
            .font(.caption)
            .foregroundColor(.blue)
        }
        .padding(.horizontal)
    }
}

// MARK: - ToolbarMenuView
struct ToolbarMenuView: View {
    @EnvironmentObject var langManager: LanguageManager
    let categories: [Category]
    let subcategories: [Subcategory]
    let filterCategory: Category?
    let filterType: TransactionType?
    let filterSubcategory: Subcategory?
    let onSelectType: (TransactionType?) -> Void
    let onSelectCategory: (Category?) -> Void
    let onSelectSubcategory: (Subcategory?) -> Void
    let saveFilterState: () -> Void
    
    var body: some View {
        HStack {
            Menu {
                Button(langManager.localized("all_label")) {
                    onSelectType(nil)
                    saveFilterState()
                }
                Button(langManager.localized("expense_label")) {
                    onSelectType(.expense)
                    saveFilterState()
                }
                Button(langManager.localized("income_label")) {
                    onSelectType(.income)
                    saveFilterState()
                }
            } label: {
                Label(filterType?.rawValue ?? langManager.localized("type_label"), systemImage: "line.3.horizontal.decrease.circle")
            }
            
            Menu {
                Button(langManager.localized("all_parent_category")) {
                    onSelectCategory(nil)
                    onSelectSubcategory(nil)
                    saveFilterState()
                }
                ForEach(categories) { cat in
                    Button(cat.name) {
                        onSelectCategory(cat)
                        onSelectSubcategory(nil)
                        saveFilterState()
                    }
                }
            } label: {
                Label(filterCategory?.name ?? langManager.localized("form_parent_category"), systemImage: "folder")
            }
            
            Menu {
                Button(langManager.localized("all_subcategory")) {
                    onSelectSubcategory(nil)
                    saveFilterState()
                }
                ForEach(subcategories.filter { $0.parentID == filterCategory?.id }) { sub in
                    Button(sub.name) {
                        onSelectSubcategory(sub)
                        saveFilterState()
                    }
                }
            } label: {
                Label(filterSubcategory?.name ?? langManager.localized("form_subcategory"), systemImage: "tag")
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

    @AppStorage("filterTypeRaw") private var filterTypeRaw: String = ""
    @AppStorage("filterCategoryName") private var filterCategoryName: String = ""
    @AppStorage("filterSubcategoryName") private var filterSubcategoryName: String = ""

    @State private var filterType: TransactionType? = nil
    @State private var filterCategory: Category? = nil
    @State private var filterSubcategory: Subcategory? = nil

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // 過濾器欄位
                if shouldShowFilterBar {
                    FilterBarView(
                        filterType: filterType,
                        filterCategory: filterCategory,
                        filterSubcategory: filterSubcategory,
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
            .navigationTitle(langManager.localized("transactions_title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ToolbarMenuView(
                        categories: categories,
                        subcategories: subcategories,
                        filterCategory: filterCategory,
                        filterType: filterType,
                        filterSubcategory: filterSubcategory,
                        onSelectType: { newType in
                            filterType = newType
                        },
                        onSelectCategory: { newCategory in
                            filterCategory = newCategory
                        },
                        onSelectSubcategory: { newSubcategory in
                            filterSubcategory = newSubcategory
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
            .onAppear { restoreFilterState() }
        }
    }
    
    private var shouldShowFilterBar: Bool {
        filterType != nil || filterCategory != nil || filterSubcategory != nil || !searchText.isEmpty
    }
    
    private func clearFilters() {
        filterType = nil
        filterCategory = nil
        filterSubcategory = nil
        searchText = ""
        saveFilterState()
    }

    private func filteredTransactions() -> [Transaction] {
        let keyword = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        var result = filterType == nil ? transactions : transactions.filter { $0.type == filterType }

        if let cat = filterCategory {
            result = result.filter { tx in
                guard let txSubID = tx.subcategoryID else { return false }
                return subcategories.first(where: { $0.id == txSubID })?.parentID == cat.id
            }
        }

        if let sub = filterSubcategory {
            result = result.filter { $0.subcategoryID == sub.id }
        }

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
