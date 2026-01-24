// MainTabView.swift 完整修正版：

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @EnvironmentObject var langManager: LanguageManager  // 新增呢行
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Query(sort: \Category.order) private var categories: [Category]
    
    var body: some View {
        TabView {
            // 交易頁面
            NavigationStack {
                TransactionListView()
            }
            .tabItem {
                Label(langManager.localized("transactions_tab"), systemImage: "list.bullet")
            }

            // 分析頁面
            NavigationStack {
                DashboardView()
            }
            .tabItem {
                Label(langManager.localized("analysis_tab"), systemImage: "chart.bar.fill")
            }

            // 設定頁面
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label(langManager.localized("settings_tab"), systemImage: "gear")
            }
            
            // 債務結算頁面（獨立頁面）
            NavigationStack {
                SettlementTabView()
            }
            .tabItem {
                Label(langManager.localized("settlement_tab"), systemImage: "dollarsign.circle")
            }
        }
    }
}

// MARK: - 債務結算主頁面
struct SettlementTabView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    
    @State private var selectedCategory: Category?
    @State private var showCategoryList = false
    @State private var searchText = ""
    
    private var filteredCategories: [Category] {
        if searchText.isEmpty {
            return categories
        } else {
            return categories.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // 選擇分類區域
            VStack(spacing: 16) {
                HStack {
                    Text(langManager.localized("settlement_select_category"))
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    Button {
                        showCategoryList = true
                    } label: {
                        Image(systemName: "list.bullet")
                            .font(.body)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                
                // 已選擇分類卡片
                if let category = selectedCategory {
                    categoryCard(category)
                        .padding(.horizontal, 16)
                } else {
                    emptyCategoryCard()
                        .padding(.horizontal, 16)
                }
            }
            .padding(.bottom, 16)
            .background(Color(.secondarySystemBackground))
            
            // 結算內容區域
            if let category = selectedCategory {
                CategorySettlementView(category: category)
                    .id(category.id)  // 關鍵修改：加呢行，強制視圖重建
                    .navigationBarHidden(true)
            } else {
                emptyStateView
                    .frame(maxHeight: .infinity)
            }
        }
        .navigationTitle(langManager.localized("settlement_title"))
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, prompt: Text(langManager.localized("search_categories")))
        .sheet(isPresented: $showCategoryList) {
            categorySelectionSheet
        }
    }
    
    private func categoryCard(_ category: Category) -> some View {
        HStack(spacing: 16) {
            if let colorHex = category.colorHex {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 40, height: 40)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(category.name)
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                
                // 顯示已分配付款人數量
                let assignedPayers = category.assignedPayers(in: context)
                if !assignedPayers.isEmpty {
                    Text("\(langManager.localized("assigned_payers"))：\(assignedPayers.map { $0.name }.joined(separator: ", "))")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .lineLimit(1)
                }
                
                // 顯示交易統計
                let transactionCount = countTransactions(for: category)
                let totalAmount = calculateTotalAmount(for: category)
                if transactionCount > 0 {
                    Text("\(transactionCount) \(langManager.localized("transactions")), \(langManager.localized("total_amount")) \(formatCurrency(totalAmount))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(spacing: 8) {
                Button {
                    showCategoryList = true
                } label: {
                    Text(langManager.localized("change_button"))
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                
                if let defaultCategory = categories.first(where: { $0.isDefault }),
                   category.id == defaultCategory.id {
                    Text(langManager.localized("default_label"))
                        .font(.caption2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.gray.opacity(0.2))
                        .cornerRadius(4)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    private func emptyCategoryCard() -> some View {
        HStack {
            Image(systemName: "folder")
                .font(.title2)
                .foregroundColor(.secondary)
                .frame(width: 40, height: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(langManager.localized("no_category_selected"))
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                
                Text(langManager.localized("select_category_for_settlement"))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button {
                showCategoryList = true
            } label: {
                Text(langManager.localized("select_category"))
                    .font(.subheadline)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(8)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "dollarsign.circle")
                .font(.system(size: 80))
                .foregroundColor(.gray.opacity(0.3))
            
            VStack(spacing: 8) {
                Text(langManager.localized("start_settlement"))
                    .font(.title2)
                    .bold()
                    .foregroundColor(.primary)
                
                Text(langManager.localized("settlement_description"))
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                
                Text(langManager.localized("settlement_how_it_works"))
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 8)
            }
            
            Button {
                showCategoryList = true
            } label: {
                HStack {
                    Image(systemName: "folder.badge.plus")
                    Text(langManager.localized("select_category"))
                }
                .font(.headline)
                .padding(.horizontal, 32)
                .padding(.vertical, 12)
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
            }
            .padding(.top, 20)
        }
        .padding(.horizontal, 20)
    }
    
    private var categorySelectionSheet: some View {
        NavigationStack {
            List {
                if filteredCategories.isEmpty {
                    ContentUnavailableView(
                        langManager.localized("no_categories"),
                        systemImage: "folder",
                        description: Text(langManager.localized("create_categories_first"))
                    )
                } else {
                    ForEach(filteredCategories) { category in
                        HStack(spacing: 12) {
                            if let colorHex = category.colorHex {
                                Circle()
                                    .fill(Color(hex: colorHex))
                                    .frame(width: 24, height: 24)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(category.name)
                                    .font(.body)
                                    .foregroundColor(.primary)
                                
                                // 顯示交易統計
                                let transactionCount = countTransactions(for: category)
                                if transactionCount > 0 {
                                    Text("\(transactionCount) \(langManager.localized("transactions"))")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                            
                            if selectedCategory?.id == category.id {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                                    .font(.title3)
                            }
                            
                            if category.isDefault {
                                Text(langManager.localized("default_label"))
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.gray.opacity(0.2))
                                    .cornerRadius(4)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedCategory = category
                            showCategoryList = false
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(langManager.localized("select_category"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(langManager.localized("done_button")) {
                        showCategoryList = false
                    }
                }
            }
            .searchable(text: $searchText, prompt: Text(langManager.localized("search_categories")))
        }
        .presentationDetents([.medium, .large])
    }
    
    // MARK: - 輔助方法
    
    private func countTransactions(for category: Category) -> Int {
        do {
            let subcategoriesFetch = FetchDescriptor<Subcategory>()
            let allSubcategories = try context.fetch(subcategoriesFetch)
            let subcategories = allSubcategories.filter { $0.parentID == category.id }
            let subcategoryIDs = subcategories.map { $0.id }
            
            if subcategoryIDs.isEmpty {
                return 0
            }
            
            let transactionsFetch = FetchDescriptor<Transaction>()
            let allTransactions = try context.fetch(transactionsFetch)
            
            return allTransactions.filter { transaction in
                if let subID = transaction.subcategoryID {
                    return subcategoryIDs.contains(subID)
                }
                return false
            }.count
        } catch {
            print("計算交易數量時出錯：\(error)")
            return 0
        }
    }
    
    private func calculateTotalAmount(for category: Category) -> Decimal {
        return category.totalAmount(in: context)
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
