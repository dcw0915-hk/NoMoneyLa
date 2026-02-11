import SwiftUI
import SwiftData
import Foundation
import Combine

// MARK: - 月度統計結構（支援多貨幣）
struct MonthlyStats {
    let totalAmounts: [String: Decimal]
    let previousMonthAmounts: [String: Decimal]?
    let changePercentages: [String: Double]?
    let dailyAverage: Decimal
    let highestTransaction: Transaction?
    let transactionCount: Int
    let periodDays: Int
}

// MARK: - 消費洞察
struct SpendingInsights {
    let peakSpendingDay: Date?
    let peakSpendingAmount: Decimal
    let weekendVsWeekdayRatio: Double
    let mostFrequentCategory: Category?
    let mostActiveDay: String
    let weekdayTransactionCount: Int
    let weekendTransactionCount: Int
    let peakMonth: String?
    let peakMonthAmount: Decimal
}

// MARK: - ✅ 分類統計結構（加入貨幣代碼）
struct CategoryStat: Identifiable {
    let id = UUID()
    let category: Category
    let currencyCode: String      // 貨幣代碼
    let amount: Decimal
    let percentage: Double       // 佔該貨幣總額嘅百分比
    let transactionCount: Int
}

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
        
        let (startDate, endDate) = calculateDateRange()
        
        do {
            let transactions = try await fetchTransactions(
                payerID: payer.id,
                startDate: startDate,
                endDate: endDate
            )
            
            monthlyStats = calculateMonthlyStats(
                transactions: transactions,
                payer: payer,
                startDate: startDate,
                endDate: endDate
            )
            
            // ✅ 使用改寫後嘅分類統計方法
            categoryStats = calculateCategoryStats(
                transactions: transactions,
                context: context
            )
            
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
        var fetchDescriptor = FetchDescriptor<Transaction>(
            predicate: #Predicate<Transaction> { transaction in
                transaction.date >= startDate &&
                transaction.date <= endDate
            },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        
        if selectedPeriod == .year {
            fetchDescriptor.fetchLimit = 1000
        }
        
        let allTransactions = try context.fetch(fetchDescriptor)
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
            let components = calendar.dateComponents([.year, .month], from: selectedDate)
            startDate = calendar.date(from: components)!
            var endComponents = DateComponents()
            endComponents.month = 1
            endComponents.day = -1
            endDate = calendar.date(byAdding: endComponents, to: startDate)!
        case .year:
            let components = calendar.dateComponents([.year], from: selectedDate)
            startDate = calendar.date(from: components)!
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
        
        var totalAmounts: [String: Decimal] = [:]
        for transaction in transactions {
            let code = transaction.currencyCode
            let payerContributions = transaction.contributions.filter { $0.payer.id == payer.id }
            let contributionSum = payerContributions.reduce(Decimal(0)) { $0 + $1.amount }
            totalAmounts[code] = (totalAmounts[code] ?? 0) + contributionSum
        }
        
        var previousMonthAmounts: [String: Decimal]? = nil
        var changePercentages: [String: Double]? = nil
        
        switch selectedPeriod {
        case .month:
            let previousAmountHKD = calculatePreviousMonthAmount(payerID: payer.id, currentMonth: startDate)
            previousMonthAmounts = ["HKD": previousAmountHKD]
            if previousAmountHKD > 0, let currentHKD = totalAmounts["HKD"] {
                let change = currentHKD - previousAmountHKD
                let percentage = (change / previousAmountHKD) * 100
                changePercentages = ["HKD": Double(truncating: percentage as NSDecimalNumber)]
            }
        case .year:
            let previousAmountHKD = calculatePreviousYearAmount(payerID: payer.id, currentYear: startDate)
            previousMonthAmounts = ["HKD": previousAmountHKD]
            if previousAmountHKD > 0, let currentHKD = totalAmounts["HKD"] {
                let change = currentHKD - previousAmountHKD
                let percentage = (change / previousAmountHKD) * 100
                changePercentages = ["HKD": Double(truncating: percentage as NSDecimalNumber)]
            }
        }
        
        let daysInRange = calendar.dateComponents([.day], from: startDate, to: endDate).day ?? 1
        let dailyAverage = (totalAmounts["HKD"] ?? 0) / Decimal(daysInRange)
        
        let highestTransaction = transactions.max { t1, t2 in
            let t1Amount = t1.contributions.filter { $0.payer.id == payer.id }.reduce(0) { $0 + $1.amount }
            let t2Amount = t2.contributions.filter { $0.payer.id == payer.id }.reduce(0) { $0 + $1.amount }
            return t1Amount < t2Amount
        }
        
        let periodDays = daysInRange + 1
        
        return MonthlyStats(
            totalAmounts: totalAmounts,
            previousMonthAmounts: previousMonthAmounts,
            changePercentages: changePercentages,
            dailyAverage: dailyAverage,
            highestTransaction: highestTransaction,
            transactionCount: transactions.count,
            periodDays: periodDays
        )
    }
    
    private func calculatePreviousMonthAmount(payerID: UUID, currentMonth: Date) -> Decimal {
        let calendar = Calendar.current
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: currentMonth) else { return 0 }
        let startComponents = calendar.dateComponents([.year, .month], from: previousMonth)
        guard let startDate = calendar.date(from: startComponents) else { return 0 }
        var endComponents = DateComponents()
        endComponents.month = 1
        endComponents.day = -1
        guard let endDate = calendar.date(byAdding: endComponents, to: startDate) else { return 0 }
        
        do {
            var fetchDescriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= startDate && transaction.date <= endDate
                }
            )
            let allTransactions = try context.fetch(fetchDescriptor)
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
        guard let previousYear = calendar.date(byAdding: .year, value: -1, to: currentYear) else { return 0 }
        let startComponents = calendar.dateComponents([.year], from: previousYear)
        guard let startDate = calendar.date(from: startComponents) else { return 0 }
        var endComponents = DateComponents()
        endComponents.year = 1
        endComponents.day = -1
        guard let endDate = calendar.date(byAdding: endComponents, to: startDate) else { return 0 }
        
        do {
            var fetchDescriptor = FetchDescriptor<Transaction>(
                predicate: #Predicate<Transaction> { transaction in
                    transaction.date >= startDate && transaction.date <= endDate
                }
            )
            let allTransactions = try context.fetch(fetchDescriptor)
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
    
    // MARK: - ✅ 核心修改：按分類 + 貨幣分組統計
    private func calculateCategoryStats(
        transactions: [Transaction],
        context: ModelContext
    ) -> [CategoryStat] {
        // 1. 獲取所有分類
        let categoriesFetch = FetchDescriptor<Category>()
        guard let allCategories = try? context.fetch(categoriesFetch) else { return [] }
        
        // 2. 獲取所有子分類
        let subcategoriesFetch = FetchDescriptor<Subcategory>()
        guard let allSubcategories = try? context.fetch(subcategoriesFetch) else { return [] }
        
        // 3. 獲取預設未分類分類（用於交易無 subcategoryID 嘅情況）
        let defaultCategory = allCategories.first(where: { $0.isDefault })
        var defaultUncategorizedSubcategory: Subcategory?
        if let defaultCategory = defaultCategory {
            defaultUncategorizedSubcategory = allSubcategories.first(where: {
                $0.parentID == defaultCategory.id && $0.name == "未分類"
            })
        }
        
        // 4. 統計容器： (分類ID, 貨幣代碼) -> (金額, 交易筆數)
        var categoryTotals: [String: (amount: Decimal, count: Int)] = [:]
        // 貨幣總額容器：貨幣代碼 -> 總金額（用於計算百分比）
        var currencyTotals: [String: Decimal] = [:]
        
        for transaction in transactions where transaction.type == .expense {
            let transactionAmount = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            let currencyCode = transaction.currencyCode
            
            // 決定屬於邊個分類
            var targetCategoryID: UUID?
            
            if let subID = transaction.subcategoryID,
               let subcategory = allSubcategories.first(where: { $0.id == subID }) {
                targetCategoryID = subcategory.parentID
            } else {
                // 如果冇 subcategoryID，歸入預設未分類分類
                targetCategoryID = defaultUncategorizedSubcategory?.parentID
            }
            
            guard let categoryID = targetCategoryID else { continue }
            
            // 組合 key
            let key = "\(categoryID.uuidString)|\(currencyCode)"
            
            if let existing = categoryTotals[key] {
                categoryTotals[key] = (amount: existing.amount + transactionAmount,
                                       count: existing.count + 1)
            } else {
                categoryTotals[key] = (amount: transactionAmount, count: 1)
            }
            
            // 累加貨幣總額
            currencyTotals[currencyCode] = (currencyTotals[currencyCode] ?? 0) + transactionAmount
        }
        
        // 5. 轉換為 CategoryStat 陣列
        var stats: [CategoryStat] = []
        
        for (key, totals) in categoryTotals {
            let components = key.split(separator: "|")
            guard components.count == 2,
                  let categoryID = UUID(uuidString: String(components[0])),
                  let category = allCategories.first(where: { $0.id == categoryID }) else {
                continue
            }
            
            let currencyCode = String(components[1])
            let totalForCurrency = currencyTotals[currencyCode] ?? 1
            
            let percentage = totalForCurrency > 0 ?
                Double(truncating: (totals.amount / totalForCurrency * 100) as NSDecimalNumber) : 0
            
            stats.append(CategoryStat(
                category: category,
                currencyCode: currencyCode,
                amount: totals.amount,
                percentage: percentage,
                transactionCount: totals.count
            ))
        }
        
        // 6. 按金額降序排序
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
        var monthlyTotals: [Int: Decimal] = [:]
        var monthlyCounts: [Int: Int] = [:]
        
        for transaction in transactions where transaction.type == .expense {
            let transactionAmount = transaction.contributions.reduce(Decimal(0)) { $0 + $1.amount }
            if transactionAmount > highestAmount {
                highestAmount = transactionAmount
                peakDay = transaction.date
            }
            
            let weekday = calendar.component(.weekday, from: transaction.date)
            if weekday == 1 || weekday == 7 {
                weekendTransactions += 1
            } else {
                weekdayTransactions += 1
            }
            
            if let subcategoryID = transaction.subcategoryID {
                transactionByCategory[subcategoryID] = (transactionByCategory[subcategoryID] ?? 0) + 1
            }
            
            if selectedPeriod == .year {
                let month = calendar.component(.month, from: transaction.date)
                monthlyTotals[month] = (monthlyTotals[month] ?? 0) + transactionAmount
                monthlyCounts[month] = (monthlyCounts[month] ?? 0) + 1
            }
        }
        
        let totalTransactions = weekdayTransactions + weekendTransactions
        let weekendRatio = totalTransactions > 0 ?
            Double(weekendTransactions) / Double(totalTransactions) : 0
        
        let mostFrequentCategoryID = transactionByCategory.max { $0.value < $1.value }?.key
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
        
        let mostActiveDay = weekendRatio > 0.5 ? "週末" : "平日"
        
        var peakMonth: String?
        var peakMonthAmount: Decimal = 0
        if selectedPeriod == .year, !monthlyTotals.isEmpty {
            if let (month, amount) = monthlyTotals.max(by: { $0.value < $1.value }) {
                peakMonthAmount = amount
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
        case .month: dateComponent.month = -1
        case .year:  dateComponent.year = -1
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
        case .month: dateComponent.month = 1
        case .year:  dateComponent.year = 1
        }
        if let newDate = calendar.date(byAdding: dateComponent, to: selectedDate) {
            selectedDate = newDate
            refreshData()
        }
    }
}
