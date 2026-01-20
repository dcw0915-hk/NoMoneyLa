//
//  DashboardView.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 20/1/2026.
//

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
                // 控制欄
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
                
                // 主要內容
                ScrollView {
                    VStack(spacing: 16) {
                        // 統計卡片網格
                        LazyVGrid(
                            columns: [
                                GridItem(.flexible(), spacing: 16),
                                GridItem(.flexible(), spacing: 16)
                            ],
                            spacing: 16
                        ) {
                            TotalSpendingCard(
                                stats: dashboardVM.monthlyStats,
                                isLoading: dashboardVM.isLoading
                            )
                            
                            CategoryBreakdownCard(
                                categories: dashboardVM.categoryStats,
                                isLoading: dashboardVM.isLoading
                            )
                            
                            DailyAverageCard(
                                stats: dashboardVM.monthlyStats,
                                isLoading: dashboardVM.isLoading
                            )
                            
                            SpendingInsightCard(
                                insights: dashboardVM.spendingInsights,
                                isLoading: dashboardVM.isLoading
                            )
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        
                        // 最近交易（可選擴展）
                        if !dashboardVM.isLoading,
                           let stats = dashboardVM.monthlyStats,
                           stats.transactionCount > 0 {
                            RecentTransactionsSection()
                        }
                        
                        // 空狀態提示
                        if !dashboardVM.isLoading,
                           dashboardVM.monthlyStats == nil {
                            emptyStateView
                        }
                    }
                    .padding(.bottom, 20)
                }
                .refreshable {
                    dashboardVM.refreshData()
                }
            }
            .navigationTitle("消費分析")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        dashboardVM.refreshData()
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .foregroundColor(.blue)
                    }
                    .disabled(dashboardVM.isLoading)
                }
            }
            .onAppear {
                // 初始化時載入數據
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
                Text("暫無消費數據")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Text("在選定的時間範圍內沒有找到交易記錄")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            Button("查看所有交易") {
                // 可以導航到交易列表
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

// MARK: - 最近交易組件

struct RecentTransactionsSection: View {
    @EnvironmentObject var dashboardVM: DashboardViewModel
    @Environment(\.modelContext) private var context
    
    @State private var recentTransactions: [Transaction] = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("最近交易", systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
                
                NavigationLink("查看全部") {
                    // 可以導航到篩選後的交易列表
                    TransactionListView()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            .padding(.horizontal, 16)
            
            if recentTransactions.isEmpty {
                Text("無最近交易")
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding()
            } else {
                ForEach(recentTransactions.prefix(3)) { transaction in
                    TransactionRow(transaction: transaction)
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
        guard let payer = dashboardVM.selectedPayer else { return }
        
        // 簡單方法：獲取所有交易，然後在 Swift 中過濾
        do {
            let fetchDescriptor = FetchDescriptor<Transaction>(
                sortBy: [SortDescriptor(\.date, order: .reverse)]
            )
            
            let allTransactions = try context.fetch(fetchDescriptor)
            
            // 過濾包含該付款人的交易
            recentTransactions = allTransactions.filter { transaction in
                transaction.contributions.contains { $0.payer.id == payer.id }
            }
            
            // 只取前5筆
            if recentTransactions.count > 5 {
                recentTransactions = Array(recentTransactions.prefix(5))
            }
            
        } catch {
            print("載入最近交易失敗: \(error)")
            recentTransactions = []
        }
    }
}

struct TransactionRow: View {
    let transaction: Transaction
    
    var body: some View {
        HStack(spacing: 12) {
            // 交易類型圖標
            Image(systemName: transaction.type == .expense ? "arrow.down.circle" : "arrow.up.circle")
                .foregroundColor(transaction.type == .expense ? .red : .green)
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                // 交易備註或分類
                if let note = transaction.note, !note.isEmpty {
                    Text(note)
                        .font(.subheadline)
                        .lineLimit(1)
                } else {
                    Text("交易")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                // 交易日期
                Text(transaction.date, format: .dateTime.month().day())
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 交易金額
            Text(formatCurrency(transaction.totalAmount, code: transaction.currencyCode))
                .font(.headline)
                .foregroundColor(transaction.type == .expense ? .red : .green)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .padding(.horizontal, 16)
    }
}

// MARK: - 預覽

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Transaction.self, Category.self, Subcategory.self, Payer.self, PaymentContribution.self, configurations: config)
    
    // 創建測試數據
    let context = container.mainContext
    
    // 創建測試付款人
    let testPayer = Payer(name: "測試用戶", colorHex: "#3498db")
    context.insert(testPayer)
    
    // 創建測試分類
    let testCategory = Category(name: "飲食", colorHex: "#FF6B6B")
    context.insert(testCategory)
    
    let testSubcategory = Subcategory(name: "餐廳", parentID: testCategory.id, colorHex: "#FF6B6B")
    context.insert(testSubcategory)
    
    // 創建測試交易
    let testTransaction = Transaction(
        totalAmount: 150,
        date: Date(),
        note: "午餐",
        subcategoryID: testSubcategory.id,
        type: .expense,
        currencyCode: "HKD"
    )
    context.insert(testTransaction)
    
    // 創建分攤
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
