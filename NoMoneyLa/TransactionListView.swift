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

// MARK: - TransactionListView
struct TransactionListView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context

    @Query(sort: \Transaction.date, order: .reverse) private var transactions: [Transaction]
    @Query(sort: \Category.order) private var categories: [Category]
    @Query(sort: \Subcategory.order) private var subcategories: [Subcategory]

    @State private var searchText = ""

    // Persisted filter state
    @AppStorage("filterTypeRaw") private var filterTypeRaw: String = ""
    @AppStorage("filterCategoryName") private var filterCategoryName: String = ""
    @AppStorage("filterSubcategoryName") private var filterSubcategoryName: String = ""

    @State private var filterType: TransactionType? = nil
    @State private var filterCategory: Category? = nil
    @State private var filterSubcategory: Subcategory? = nil

    var body: some View {
        NavigationStack {
            VStack {
                // 篩選狀態顯示列
                if filterType != nil || filterCategory != nil || filterSubcategory != nil || !searchText.isEmpty {
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
                            filterType = nil
                            filterCategory = nil
                            filterSubcategory = nil
                            searchText = ""
                            saveFilterState()
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    }
                    .padding(.horizontal)
                }

                // 交易卡片清單（保留 cardStyle）
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(filteredTransactions()) { tx in
                            NavigationLink(
                                destination: TransactionFormView(transaction: tx, isEditing: false)
                            ) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(categoryName(for: tx.subcategoryID))
                                            .font(.headline)
                                            .foregroundColor(.primary)

                                        if let note = tx.note, !note.isEmpty {
                                            Text(note)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                                .lineLimit(1)
                                        }

                                        Text(tx.date, format: .dateTime.year().month().day())
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }

                                    Spacer()

                                    Text(format(amount: tx.amount, code: tx.currencyCode))
                                        .font(.title3)
                                        .bold()
                                        .foregroundColor(tx.type == .expense ? .red : .green)
                                }
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
                // 類型篩選（左上）
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(langManager.localized("all_label")) { filterType = nil; saveFilterState() }
                        Button(langManager.localized("expense_label")) { filterType = .expense; saveFilterState() }
                        Button(langManager.localized("income_label")) { filterType = .income; saveFilterState() }
                    } label: {
                        Label(filterType?.rawValue ?? langManager.localized("type_label"), systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                // 主要分類（Category）篩選（左上）
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(langManager.localized("all_parent_category")) { filterCategory = nil; filterSubcategory = nil; saveFilterState() }
                        ForEach(categories) { cat in
                            Button(cat.name) {
                                filterCategory = cat
                                filterSubcategory = nil
                                saveFilterState()
                            }
                        }
                    } label: {
                        Label(filterCategory?.name ?? langManager.localized("form_parent_category"), systemImage: "folder")
                    }
                }

                // 子分類（Subcategory）篩選（左上）
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button(langManager.localized("all_subcategory")) { filterSubcategory = nil; saveFilterState() }
                        ForEach(subcategories.filter { $0.parentID == filterCategory?.id }) { sub in
                            Button(sub.name) {
                                filterSubcategory = sub
                                saveFilterState()
                            }
                        }
                    } label: {
                        Label(filterSubcategory?.name ?? langManager.localized("form_subcategory"), systemImage: "tag")
                    }
                }

                // 新增按鈕（右上）
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

    // MARK: - Filtered Transactions
    private func filteredTransactions() -> [Transaction] {
        let keyword = searchText.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

        // 先依 type 篩選
        var result = filterType == nil ? transactions : transactions.filter { $0.type == filterType }

        // 若選了主要分類（Category），保留其子分類下的交易
        if let cat = filterCategory {
            result = result.filter { tx in
                guard let txSubID = tx.subcategoryID else { return false }
                return subcategories.first(where: { $0.id == txSubID })?.parentID == cat.id
            }
        }

        // 若選了子分類（Subcategory），再進一步過濾
        if let sub = filterSubcategory {
            result = result.filter { $0.subcategoryID == sub.id }
        }

        // 搜尋文字（分類名稱、備註、主要分類名稱）
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

            let haystack = [catName, note, parentName]
                .joined(separator: " ")
                .lowercased()

            return haystack.contains(keyword)
        }
    }

    // MARK: - Helpers
    private func delete(tx: Transaction) {
        context.delete(tx)
        do {
            try context.save()
        } catch {
            print("\(langManager.localized("delete_failed"))：\(error.localizedDescription)")
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

    private func format(amount: Decimal, code: String = "HKD") -> String {
        let ns = amount as NSDecimalNumber
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.locale = Locale.current
        return formatter.string(from: ns) ?? "\(amount)"
    }
}
