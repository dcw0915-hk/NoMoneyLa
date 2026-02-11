import SwiftUI
import SwiftData

struct DashboardView: View {
    @EnvironmentObject var langManager: LanguageManager
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.modelContext) private var context
    
    @State private var showingLoading = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DashboardControlBar(
                    selectedPayer: $dashboardVM.selectedPayer,
                    selectedPeriod: $dashboardVM.selectedPeriod,
                    selectedDate: $dashboardVM.selectedDate,
                    allPayers: dashboardVM.allPayers
                )
                .onChange(of: dashboardVM.selectedPayer) { _ in
                    dashboardVM.refreshData()
                }
                .onChange(of: dashboardVM.selectedPeriod) { _ in
                    dashboardVM.refreshData()
                }
                .onChange(of: dashboardVM.selectedDate) { _ in
                    dashboardVM.refreshData()
                }
                
                ScrollView {
                    VStack(spacing: 16) {
                        // ✅ 使用新的 TotalSpendingCard，傳入多貨幣字典
                        TotalSpendingCard(
                            totalAmounts: dashboardVM.monthlyStats?.totalAmounts ?? [:],
                            transactionCount: dashboardVM.monthlyStats?.transactionCount ?? 0,
                            previousMonthAmounts: dashboardVM.monthlyStats?.previousMonthAmounts,
                            changePercentages: dashboardVM.monthlyStats?.changePercentages,
                            isLoading: dashboardVM.isLoading,
                            period: dashboardVM.selectedPeriod
                        )
                        
                        DailyAverageCard(
                            stats: dashboardVM.monthlyStats,
                            isLoading: dashboardVM.isLoading,
                            period: dashboardVM.selectedPeriod
                        )
                        
                        CategoryBreakdownCard(
                            categories: dashboardVM.categoryStats,
                            isLoading: dashboardVM.isLoading
                        )
                        
                        SpendingInsightCard(
                            insights: dashboardVM.spendingInsights,
                            isLoading: dashboardVM.isLoading,
                            period: dashboardVM.selectedPeriod
                        )
                        
                        if !dashboardVM.isLoading,
                           let stats = dashboardVM.monthlyStats,
                           stats.transactionCount > 0 {
                            RecentTransactionsSection()
                        }
                        
                        if !dashboardVM.isLoading,
                           dashboardVM.monthlyStats == nil {
                            emptyStateView
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 16)
                }
                .refreshable {
                    dashboardVM.refreshData()
                }
            }
            .navigationTitle(langManager.localized("dashboard_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dashboardVM.refreshData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                            .font(.body)
                    }
                    .disabled(dashboardVM.isLoading)
                }
            }
            .onAppear {
                if dashboardVM.selectedPayer != nil && !dashboardVM.isLoading {
                    dashboardVM.refreshData()
                }
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 60))
                .foregroundColor(.gray.opacity(0.3))
            
            VStack(spacing: 8) {
                Text(langManager.localized("no_spending_data"))
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text(langManager.localized("no_transactions_in_selected_period"))
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button(langManager.localized("view_all_transactions")) {
                // 導航到交易列表
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.blue)
            .foregroundColor(.white)
            .cornerRadius(8)
        }
        .padding(.vertical, 60)
    }
}

// MARK: - 最近交易組件（不變）
struct RecentTransactionsSection: View {
    @EnvironmentObject var langManager: LanguageManager
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.modelContext) private var context
    
    @State private var recentTransactions: [Transaction] = []
    @State private var totalFilteredTransactions = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(langManager.localized("recent_transactions"), systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                if totalFilteredTransactions > 0 {
                    NavigationLink(langManager.localized("view_all")) {
                        TransactionListView(
                            filterPayer: dashboardVM.selectedPayer,
                            filterPeriod: dashboardVM.selectedPeriod,
                            filterDate: dashboardVM.selectedDate
                        )
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            
            if recentTransactions.isEmpty {
                Text(langManager.localized("no_transactions_in_period"))
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(recentTransactions.prefix(3)) { transaction in
                    TransactionRow(transaction: transaction)
                }
                
                if let payerName = dashboardVM.selectedPayer?.name {
                    Text("\(langManager.localized("filter_label"))：\(payerName)｜\(formatPeriod())")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 4)
                }
            }
        }
        .onAppear {
            loadRecentTransactions()
        }
        .onChange(of: dashboardVM.selectedPayer) { _ in
            loadRecentTransactions()
        }
        .onChange(of: dashboardVM.selectedDate) { _ in
            loadRecentTransactions()
        }
        .onChange(of: dashboardVM.selectedPeriod) { _ in
            loadRecentTransactions()
        }
    }
    
    private func loadRecentTransactions() {
        guard let payer = dashboardVM.selectedPayer else {
            recentTransactions = []
            totalFilteredTransactions = 0
            return
        }
        
        let (startDate, endDate) = dashboardVM.calculateDateRange()
        
        do {
            let fetchDescriptor = FetchDescriptor<Transaction>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            let allTransactions = try context.fetch(fetchDescriptor)
            
            let filtered = allTransactions.filter { transaction in
                let isInPeriod = transaction.date >= startDate && transaction.date <= endDate
                let hasPayer = transaction.contributions.contains { $0.payer.id == payer.id }
                return isInPeriod && hasPayer
            }
            
            totalFilteredTransactions = filtered.count
            recentTransactions = Array(filtered.prefix(5))
        } catch {
            print("載入最近交易失敗: \(error)")
            recentTransactions = []
            totalFilteredTransactions = 0
        }
    }
    
    private func formatPeriod() -> String {
        let formatter = DateFormatter()
        switch dashboardVM.selectedPeriod {
        case .month:
            formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "yyyy年M月" : "MMM yyyy"
        case .year:
            formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "yyyy年" : "yyyy"
        }
        return formatter.string(from: dashboardVM.selectedDate)
    }
}

struct TransactionRow: View {
    @EnvironmentObject var langManager: LanguageManager
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.type == .expense ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundColor(transaction.type == .expense ? .red : .green)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text(langManager.localized("transaction_default_name"))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Text(transaction.date, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // ✅ 使用交易本身的貨幣代碼
            Text(formatCurrency(amount: transaction.totalAmount, code: transaction.currencyCode))
                .font(.headline)
                .foregroundColor(transaction.type == .expense ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }
    
    private func formatCurrency(amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 預覽
#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Transaction.self, Category.self, Subcategory.self, Payer.self, PaymentContribution.self, configurations: config)
    
    let context = container.mainContext
    let testPayer = Payer(name: "測試用戶", colorHex: "#3498db")
    context.insert(testPayer)
    let testCategory = Category(name: "飲食", colorHex: "#FF6B6B")
    context.insert(testCategory)
    let testSubcategory = Subcategory(name: "餐廳", parentID: testCategory.id, colorHex: "#FF6B6B")
    context.insert(testSubcategory)
    let testTransaction = Transaction(
        totalAmount: 150,
        date: Date(),
        note: "午餐",
        subcategoryID: testSubcategory.id,
        type: .expense,
        currencyCode: "HKD"
    )
    context.insert(testTransaction)
    let contribution = PaymentContribution(
        amount: 150,
        payer: testPayer,
        transaction: testTransaction
    )
    context.insert(contribution)
    testTransaction.contributions.append(contribution)
    try? context.save()
    
    return DashboardView()
        .environmentObject(LanguageManager())
        .environmentObject(DashboardViewModel(context: context))
        .modelContainer(container)
}
