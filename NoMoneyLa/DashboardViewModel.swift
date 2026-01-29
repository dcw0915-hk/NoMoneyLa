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
                transactions: transactions,
                startDate: startDate,
                endDate: endDate
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
        
        // 年視圖時限制獲取數量
        if selectedPeriod == .year {
            fetchDescriptor.fetchLimit = 1000
        }
        
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
        
        // 計算上期數據
        var previousPeriodAmount: Decimal = 0
        var changePercentage: Double = 0
        
        switch selectedPeriod {
        case .month:
            previousPeriodAmount = calculatePreviousMonthAmount(payerID: payer.id, currentMonth: startDate)
        case .year:
            previousPeriodAmount = calculatePreviousYearAmount(payerID: payer.id, currentYear: startDate)
        }
        
        if previousPeriodAmount > 0 {
            let change = totalAmount - previousPeriodAmount
            let percentage = (change / previousPeriodAmount) * 100
            changePercentage = Double(truncating: percentage as NSDecimalNumber)
        }
        
        // 計算日均消費
        let daysInRange = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        let dailyAverage = daysInRange > 0 ? totalAmount / Decimal(daysInRange) : 0
        
        // 找出最高交易
        let highestTransaction = transactions.max { t1, t2 in
            let t1Amount = t1.contributions.filter { $0.payer.id == payer.id }.reduce(0) { $0 + $1.amount }
            let t2Amount = t2.contributions.filter { $0.payer.id == payer.id }.reduce(0) { $0 + $1.amount }
            return t1Amount < t2Amount
        }
        
        let periodDays = daysInRange + 1
        
        return MonthlyStats(
            totalAmount: totalAmount,
            previousMonthAmount: previousPeriodAmount,
            changePercentage: changePercentage,
            dailyAverage: dailyAverage,
            highestTransaction: highestTransaction,
            transactionCount: transactions.count,
            periodDays: periodDays
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
    
    private func calculatePreviousYearAmount(payerID: UUID, currentYear: Date) -> Decimal {
        let calendar = Calendar.current
        
        // 計算上年的時間範圍
        guard let previousYear = calendar.date(byAdding: .year, value: -1, to: currentYear) else {
            return 0
        }
        
        let startComponents = calendar.dateComponents([.year], from: previousYear)
        guard let startDate = calendar.date(from: startComponents) else { return 0 }
        
        var endComponents = DateComponents()
        endComponents.year = 1
        endComponents.day = -1
        guard let endDate = calendar.date(byAdding: endComponents, to: startDate) else { return 0 }
        
        do {
            // 獲取上年所有交易
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
            print("計算上年金額失敗: \(error)")
            return 0
        }
    }
    
    // ✅ 更新：簡化統計邏輯，不再處理 nil 分類
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
        
        // ✅ 先獲取預設未分類分類
        let defaultCategory = allCategories.first(where: { $0.isDefault })
        var defaultUncategorizedSubcategory: Subcategory?
        if let defaultCategory = defaultCategory {
            defaultUncategorizedSubcategory = allSubcategories.first(where: {
                $0.parentID == defaultCategory.id && $0.name == "未分類"
            })
        }
        
        // 按分類統計
        var categoryTotals: [UUID: (amount: Decimal, count: Int)] = [:]
        var totalAmount: Decimal = 0
        
        for transaction in transactions {
            guard let subcategoryID = transaction.subcategoryID else {
                // ✅ 理論上唔應該出現，但如果出現就計入預設未分類
                if let defaultUncategorizedSubcategory = defaultUncategorizedSubcategory {
                    let transactionAmount = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
                    
                    if let existing = categoryTotals[defaultUncategorizedSubcategory.parentID] {
                        categoryTotals[defaultUncategorizedSubcategory.parentID] = (
                            amount: existing.amount + transactionAmount,
                            count: existing.count + 1
                        )
                    } else {
                        categoryTotals[defaultUncategorizedSubcategory.parentID] = (
                            amount: transactionAmount,
                            count: 1
                        )
                    }
                    
                    totalAmount += transactionAmount
                }
                continue
            }
            
            guard let subcategory = allSubcategories.first(where: { $0.id == subcategoryID }) else {
                // 如果找不到對應子分類，也計入預設未分類
                if let defaultUncategorizedSubcategory = defaultUncategorizedSubcategory {
                    let transactionAmount = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
                    
                    if let existing = categoryTotals[defaultUncategorizedSubcategory.parentID] {
                        categoryTotals[defaultUncategorizedSubcategory.parentID] = (
                            amount: existing.amount + transactionAmount,
                            count: existing.count + 1
                        )
                    } else {
                        categoryTotals[defaultUncategorizedSubcategory.parentID] = (
                            amount: transactionAmount,
                            count: 1
                        )
                    }
                    
                    totalAmount += transactionAmount
                }
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
    
    private func calculateSpendingInsights(
        transactions: [Transaction],
        startDate: Date,
        endDate: Date
    ) -> SpendingInsights? {
        guard !transactions.isEmpty else { return nil }
        
        let calendar = Calendar.current
        var weekdayTransactions = 0
        var weekendTransactions = 0
        var transactionByCategory: [UUID: Int] = [:]
        var highestAmount: Decimal = 0
        var peakDay: Date?
        var monthlyTotals: [Int: Decimal] = [:]  // 新增：每月統計（僅年視圖）
        var monthlyCounts: [Int: Int] = [:]     // 新增：每月交易數
        
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
            
            // 年視圖：統計每月數據
            if selectedPeriod == .year {
                let month = calendar.component(.month, from: transaction.date)
                monthlyTotals[month] = (monthlyTotals[month] ?? 0) + transactionAmount
                monthlyCounts[month] = (monthlyCounts[month] ?? 0) + 1
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
        
        // 年視圖：找出消費最高月份
        var peakMonth: String?
        var peakMonthAmount: Decimal = 0
        if selectedPeriod == .year, !monthlyTotals.isEmpty {
            if let (month, amount) = monthlyTotals.max(by: { $0.value < $1.value }) {
                peakMonthAmount = amount
                // 將月份數字轉為中文
                let monthNames = ["", "1月", "2月", "3月", "4月", "5月", "6月", "7月", "8月", "9月", "10月", "11月", "12月"]
                peakMonth = monthNames[month]
            }
        }
        
        return SpendingInsights(
            peakSpendingDay: peakDay,
            peakSpendingAmount: highestAmount,
            weekendVsWeekdayRatio: weekendRatio,
            mostFrequentCategory: mostFrequentCategory,
            mostActiveDay: mostActiveDay,
            weekdayTransactionCount: weekdayTransactions,
            weekendTransactionCount: weekendTransactions,
            peakMonth: peakMonth,
            peakMonthAmount: peakMonthAmount
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
