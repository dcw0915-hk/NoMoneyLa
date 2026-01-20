//
//  DashboardViewModel.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 20/1/2026.
//

import SwiftUI
import SwiftData
import Foundation
import Combine

@MainActor
class DashboardViewModel: ObservableObject {
    @Published var selectedPayer: Payer?
    @Published var selectedPeriod: TimePeriod = .month
    @Published var selectedDate: Date = Date()
    
    @Published var monthlyStats: MonthlyStats?
    @Published var categoryStats: [CategoryStat] = []
    @Published var spendingInsights: SpendingInsights?
    
    @Published var isLoading = false
    @Published var allPayers: [Payer] = []
    
    private let context: ModelContext
    private let calendar = Calendar.current
    
    init(context: ModelContext) {
        self.context = context
        loadAllPayers()
        if let firstPayer = allPayers.first {
            selectedPayer = firstPayer
        }
    }
    
    // MARK: - 數據載入
    
    func loadAllPayers() {
        do {
            let fetchDescriptor = FetchDescriptor<Payer>(
                sortBy: [SortDescriptor(\.order)]
            )
            allPayers = try context.fetch(fetchDescriptor)
        } catch {
            print("載入付款人失敗: \(error)")
            allPayers = []
        }
    }
    
    func loadDashboardData() async {
        guard let payer = selectedPayer else { return }
        
        isLoading = true
        
        // 計算時間範圍
        let (startDate, endDate) = calculateDateRange()
        
        do {
            // 獲取所有交易
            let transactions = try await fetchTransactions(
                payerID: payer.id,
                startDate: startDate,
                endDate: endDate
            )
            
            // 計算統計數據
            monthlyStats = calculateMonthlyStats(
                transactions: transactions,
                payer: payer,
                startDate: startDate,
                endDate: endDate
            )
            
            // 計算分類統計
            categoryStats = calculateCategoryStats(
                transactions: transactions,
                context: context
            )
            
            // 計算消費洞察
            spendingInsights = calculateSpendingInsights(
                transactions: transactions
            )
            
        } catch {
            print("載入 Dashboard 數據失敗: \(error)")
            monthlyStats = nil
            categoryStats = []
            spendingInsights = nil
        }
        
        isLoading = false
    }
    
    // MARK: - 數據查詢
    
    private func fetchTransactions(
        payerID: UUID,
        startDate: Date,
        endDate: Date
    ) async throws -> [Transaction] {
        // 使用兩步查詢方法避免複雜的 Predicate
        // 1. 先獲取該時間段內的所有交易
        var fetchDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.date >= startDate &&
                transaction.date <= endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        let allTransactions = try context.fetch(fetchDescriptor)
        
        // 2. 在內存中過濾包含該付款人的交易
        return allTransactions.filter { transaction in
            transaction.contributions.contains { $0.payer.id == payerID }
        }
    }
    
    // MARK: - 數據計算
    
    func calculateDateRange() -> (startDate: Date, endDate: Date) {
        let calendar = Calendar.current
        var startDate: Date
        var endDate: Date
        
        switch selectedPeriod {
        case .month:
            // 當前月的第一天
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            startDate = calendar.date(from: components)!
            
            // 當前月的最後一天
            var endComponents = DateComponents()
            endComponents.month = 1
            endComponents.day = -1
            endDate = calendar.date(byAdding: endComponents, to: startDate)!
            
        case .year:
            // 當前年的第一天
            let components = calendar.dateComponents([.year], from: selectedDate)
            startDate = calendar.date(from: components)!
            
            // 當前年的最後一天
            var endComponents = DateComponents()
            endComponents.year = 1
            endComponents.day = -1
            endDate = calendar.date(byAdding: endComponents, to: startDate)!
        }
        
        return (startDate, endDate)
    }
    
    private func calculateMonthlyStats(
        transactions: [Transaction],
        payer: Payer,
        startDate: Date,
        endDate: Date
    ) -> MonthlyStats? {
        guard !transactions.isEmpty else { return nil }
        
        // 計算總金額
        let totalAmount = transactions.reduce(Decimal(0)) { total, transaction in
            let payerContributions = transaction.contributions.filter { $0.payer.id == payer.id }
            let contributionSum = payerContributions.reduce(Decimal(0)) { $0 + $1.amount }
            return total + contributionSum
        }
        
        // 計算上月數據（僅在月視圖時）
        var previousMonthAmount: Decimal = 0
        var changePercentage: Double = 0
        
        if selectedPeriod == .month {
            previousMonthAmount = calculatePreviousMonthAmount(payerID: payer.id, currentMonth: startDate)
            if previousMonthAmount > 0 {
                let change = totalAmount - previousMonthAmount
                let percentage = (change / previousMonthAmount) * 100
                changePercentage = Double(truncating: percentage as NSDecimalNumber)
            }
        }
        
        // 計算日均消費
        let daysInRange = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 30
        let dailyAverage = daysInRange > 0 ? totalAmount / Decimal(daysInRange) : 0
        
        // 找出最高交易
        let highestTransaction = transactions.max { t1, t2 in
            let t1Amount = t1.contributions.filter { $0.payer.id == payer.id }.reduce(0) { $0 + $1.amount }
            let t2Amount = t2.contributions.filter { $0.payer.id == payer.id }.reduce(0) { $0 + $1.amount }
            return t1Amount < t2Amount
        }
        
        return MonthlyStats(
            totalAmount: totalAmount,
            previousMonthAmount: previousMonthAmount,
            changePercentage: changePercentage,
            dailyAverage: dailyAverage,
            highestTransaction: highestTransaction,
            transactionCount: transactions.count
        )
    }
    
    private func calculatePreviousMonthAmount(payerID: UUID, currentMonth: Date) -> Decimal {
        let calendar = Calendar.current
        
        // 計算上個月的時間範圍
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) else {
            return 0
        }
        
        let startComponents = calendar.dateComponents([.year, .month], from: previousMonth)
        guard let startDate = calendar.date(from: startComponents) else { return 0 }
        
        var endComponents = DateComponents()
        endComponents.month = 1
        endComponents.day = -1
        guard let endDate = calendar.date(byAdding: endComponents, to: startDate) else { return 0 }
        
        do {
            // 獲取上月所有交易
            var fetchDescriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= startDate &&
                    transaction.date <= endDate
                }
            )
            
            let allTransactions = try context.fetch(fetchDescriptor)
            
            // 過濾包含該付款人的交易並計算總額
            return allTransactions.reduce(Decimal(0)) { total, transaction in
                let payerContributions = transaction.contributions.filter { $0.payer.id == payerID }
                let contributionSum = payerContributions.reduce(Decimal(0)) { $0 + $1.amount }
                return total + contributionSum
            }
        } catch {
            print("計算上月金額失敗: \(error)")
            return 0
        }
    }
    
    private func calculateCategoryStats(
        transactions: [Transaction],
        context: ModelContext
    ) -> [CategoryStat] {
        // 獲取所有分類
        let categoriesFetch = FetchDescriptor<Category>()
        guard let allCategories = try? context.fetch(categoriesFetch) else {
            return []
        }
        
        // 獲取所有子分類
        let subcategoriesFetch = FetchDescriptor<Subcategory>()
        guard let allSubcategories = try? context.fetch(subcategoriesFetch) else {
            return []
        }
        
        // 按分類統計
        var categoryTotals: [UUID: (amount: Decimal, count: Int)] = [:]
        var totalAmount: Decimal = 0
        
        for transaction in transactions {
            guard let subcategoryID = transaction.subcategoryID,
                  let subcategory = allSubcategories.first(where: { $0.id == subcategoryID }) else {
                continue
            }
            
            // 只計算支出類交易
            guard transaction.type == .expense else { continue }
            
            let transactionAmount = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            
            // 累加到分類總額
            if let existing = categoryTotals[subcategory.parentID] {
                categoryTotals[subcategory.parentID] = (
                    amount: existing.amount + transactionAmount,
                    count: existing.count + 1
                )
            } else {
                categoryTotals[subcategory.parentID] = (
                    amount: transactionAmount,
                    count: 1
                )
            }
            
            totalAmount += transactionAmount
        }
        
        // 轉換為 CategoryStat 陣列
        var stats: [CategoryStat] = []
        
        for (categoryID, totals) in categoryTotals {
            if let category = allCategories.first(where: { $0.id == categoryID }) {
                let percentage = totalAmount > 0 ?
                    Double(truncating: (totals.amount / totalAmount * 100) as NSDecimalNumber) : 0
                
                stats.append(CategoryStat(
                    category: category,
                    amount: totals.amount,
                    percentage: percentage,
                    transactionCount: totals.count
                ))
            }
        }
        
        // 按金額降序排序
        return stats.sorted { $0.amount > $1.amount }
    }
    
    private func calculateSpendingInsights(transactions: [Transaction]) -> SpendingInsights? {
        guard !transactions.isEmpty else { return nil }
        
        let calendar = Calendar.current
        var weekdayTransactions = 0
        var weekendTransactions = 0
        var transactionByCategory: [UUID: Int] = [:]
        var highestAmount: Decimal = 0
        var peakDay: Date?
        
        // 分析交易模式
        for transaction in transactions {
            guard transaction.type == .expense else { continue }
            
            let transactionAmount = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            
            // 找出最高交易
            if transactionAmount > highestAmount {
                highestAmount = transactionAmount
                peakDay = transaction.date
            }
            
            // 統計週末 vs 平日
            let weekday = calendar.component(.weekday, from: transaction.date)
            if weekday == 1 || weekday == 7 { // 週日=1, 週六=7
                weekendTransactions += 1
            } else {
                weekdayTransactions += 1
            }
            
            // 統計分類使用頻率
            if let subcategoryID = transaction.subcategoryID {
                transactionByCategory[subcategoryID] = (transactionByCategory[subcategoryID] ?? 0) + 1
            }
        }
        
        // 計算週末比例
        let totalTransactions = weekdayTransactions + weekendTransactions
        let weekendRatio = totalTransactions > 0 ?
            Double(weekendTransactions) / Double(totalTransactions) : 0
        
        // 找出最常用分類
        let mostFrequentCategoryID = transactionByCategory.max { $0.value < $1.value }?.key
        
        // 獲取分類名稱
        var mostFrequentCategory: Category?
        if let categoryID = mostFrequentCategoryID {
            let subcategoriesFetch = FetchDescriptor<Subcategory>()
            if let allSubcategories = try? context.fetch(subcategoriesFetch),
               let subcategory = allSubcategories.first(where: { $0.id == categoryID }) {
                let categoriesFetch = FetchDescriptor<Category>()
                if let allCategories = try? context.fetch(categoriesFetch) {
                    mostFrequentCategory = allCategories.first { $0.id == subcategory.parentID }
                }
            }
        }
        
        // 判斷最活躍消費日
        let mostActiveDay = weekendRatio > 0.5 ? "週末" : "平日"
        
        return SpendingInsights(
            peakSpendingDay: peakDay,
            peakSpendingAmount: highestAmount,
            weekendVsWeekdayRatio: weekendRatio,
            mostFrequentCategory: mostFrequentCategory,
            mostActiveDay: mostActiveDay
        )
    }
    
    // MARK: - 公開方法
    
    func refreshData() {
        Task {
            await loadDashboardData()
        }
    }
    
    func selectPreviousPeriod() {
        let calendar = Calendar.current
        var dateComponent = DateComponents()
        
        switch selectedPeriod {
        case .month:
            dateComponent.month = -1
        case .year:
            dateComponent.year = -1
        }
        
        if let newDate = calendar.date(byAdding: dateComponent, to: selectedDate) {
            selectedDate = newDate
            refreshData()
        }
    }
    
    func selectNextPeriod() {
        let calendar = Calendar.current
        var dateComponent = DateComponents()
        
        switch selectedPeriod {
        case .month:
            dateComponent.month = 1
        case .year:
            dateComponent.year = 1
        }
        
        if let newDate = calendar.date(byAdding: dateComponent, to: selectedDate) {
            selectedDate = newDate
            refreshData()
        }
    }
}
