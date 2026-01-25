//
//  DashboardComponents.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 20/1/2026.
//

import SwiftUI
import SwiftData

// MARK: - 數據結構

enum TimePeriod: String, CaseIterable {
    case month = "month"
    case year = "year"
}

struct MonthlyStats {
    let totalAmount: Decimal
    let previousMonthAmount: Decimal
    let changePercentage: Double
    let dailyAverage: Decimal
    let highestTransaction: Transaction?
    let transactionCount: Int
    let periodDays: Int // 新增：期間天數
}

struct CategoryStat: Identifiable {
    let id = UUID()
    let category: Category
    let amount: Decimal
    let percentage: Double
    let transactionCount: Int
}

struct SpendingInsights {
    let peakSpendingDay: Date?
    let peakSpendingAmount: Decimal
    let weekendVsWeekdayRatio: Double
    let mostFrequentCategory: Category?
    let mostActiveDay: String // "週一"、"週末"等
    let weekdayTransactionCount: Int // 新增：平日交易筆數
    let weekendTransactionCount: Int // 新增：週末交易筆數
    let peakMonth: String?      // 新增：消費最高月份
    let peakMonthAmount: Decimal // 新增：該月消費金額
}

// MARK: - 控制欄組件

struct DashboardControlBar: View {
    @Binding var selectedPayer: Payer?
    @Binding var selectedPeriod: TimePeriod
    @Binding var selectedDate: Date
    let allPayers: [Payer]
    
    var body: some View {
        VStack(spacing: 16) {
            // 付款人選擇器
            PayerSelectionView(
                selectedPayer: $selectedPayer,
                allPayers: allPayers
            )
            
            // 時間選擇器
            PeriodSelectionView(
                selectedPeriod: $selectedPeriod,
                selectedDate: $selectedDate
            )
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemBackground))
    }
}

struct PayerSelectionView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Binding var selectedPayer: Payer?
    let allPayers: [Payer]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(langManager.localized("dashboard_analyze_target"))
                .font(.caption)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(allPayers) { payer in
                        PayerChipView(
                            payer: payer,
                            isSelected: selectedPayer?.id == payer.id
                        )
                        .onTapGesture {
                            selectedPayer = payer
                        }
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

struct PayerChipView: View {
    let payer: Payer
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                .frame(width: 16, height: 16)
            
            Text(payer.name)
                .font(.subheadline)
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(isSelected ? Color.blue.opacity(0.2) : Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
}

struct PeriodSelectionView: View {
    @EnvironmentObject var langManager: LanguageManager
    @Binding var selectedPeriod: TimePeriod
    @Binding var selectedDate: Date
    
    var body: some View {
        VStack(spacing: 12) {
            // 月/年切換
            Picker(langManager.localized("dashboard_period"), selection: $selectedPeriod) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Text(langManager.localized(period == .month ? "period_month" : "period_year")).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            
            // 日期導航
            HStack(spacing: 20) {
                Button {
                    moveDate(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
                
                Text(formatDate())
                    .font(.headline)
                    .frame(minWidth: 120)
                
                Button {
                    moveDate(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.headline)
                        .foregroundColor(.blue)
                }
            }
        }
    }
    
    private func moveDate(by value: Int) {
        let calendar = Calendar.current
        var dateComponent = DateComponents()
        
        switch selectedPeriod {
        case .month:
            dateComponent.month = value
        case .year:
            dateComponent.year = value
        }
        
        if let newDate = calendar.date(byAdding: dateComponent, to: selectedDate) {
            selectedDate = newDate
        }
    }
    
    private func formatDate() -> String {
        let formatter = DateFormatter()
        
        switch selectedPeriod {
        case .month:
            formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "yyyy年M月" : "MMM yyyy"
        case .year:
            formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "yyyy年" : "yyyy"
        }
        
        return formatter.string(from: selectedDate)
    }
}

// MARK: - 篩選欄組件

struct FilterBarView: View {
    @EnvironmentObject var langManager: LanguageManager
    let filterType: TransactionType?
    let filterCategory: Category?
    let filterSubcategory: Subcategory?
    let filterPayer: Payer?  // 新增
    let filterDateRange: String?  // 新增
    let searchText: String
    let clearFilters: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(langManager.localized("filter_current"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Button(langManager.localized("clear_button")) {
                    clearFilters()
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
            
            // 篩選標籤行
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let type = filterType {
                        filterTag(
                            text: type == .expense ? langManager.localized("expense_label") : langManager.localized("income_label"),
                            color: .gray
                        )
                    }
                    
                    if let cat = filterCategory {
                        filterTag(text: cat.name, color: .blue)
                    }
                    
                    if let sub = filterSubcategory {
                        filterTag(text: sub.name, color: .blue.opacity(0.8))
                    }
                    
                    if let payer = filterPayer {
                        filterTag(text: payer.name, color: .green)
                    }
                    
                    if let dateRange = filterDateRange {
                        filterTag(text: dateRange, color: .orange)
                    }
                    
                    if !searchText.isEmpty {
                        filterTag(
                            text: "\(langManager.localized("search_label"))：\(searchText)",
                            color: .purple
                        )
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
    
    private func filterTag(text: String, color: Color) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(color.opacity(0.3), lineWidth: 1)
            )
            .foregroundColor(color)
    }
}

// MARK: - 工具欄菜單組件

struct ToolbarMenuView: View {
    @EnvironmentObject var langManager: LanguageManager
    let categories: [Category]
    let subcategories: [Subcategory]
    let payers: [Payer]  // 新增
    let filterCategory: Category?
    let filterType: TransactionType?
    let filterSubcategory: Subcategory?
    let filterPayer: Payer?  // 新增
    let onSelectType: (TransactionType?) -> Void
    let onSelectCategory: (Category?) -> Void
    let onSelectSubcategory: (Subcategory?) -> Void
    let onSelectPayer: (Payer?) -> Void  // 新增
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
                Label(filterType?.rawValue ?? langManager.localized("type_label"),
                      systemImage: "line.3.horizontal.decrease.circle")
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
                Label(filterCategory?.name ?? langManager.localized("form_parent_category"),
                      systemImage: "folder")
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
                Label(filterSubcategory?.name ?? langManager.localized("form_subcategory"),
                      systemImage: "tag")
            }
            
            // 新增付款人篩選菜單
            Menu {
                Button(langManager.localized("all_payers")) {
                    onSelectPayer(nil)
                    saveFilterState()
                }
                ForEach(payers) { payer in
                    Button {
                        onSelectPayer(payer)
                        saveFilterState()
                    } label: {
                        HStack {
                            Circle()
                                .fill(Color(hex: payer.colorHex ?? "#A8A8A8"))
                                .frame(width: 8, height: 8)
                            Text(payer.name)
                        }
                    }
                }
            } label: {
                Label(filterPayer?.name ?? langManager.localized("payer_label"), systemImage: "person.2")
            }
        }
    }
}

// MARK: - 統計卡片組件

struct TotalSpendingCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let stats: MonthlyStats?
    let isLoading: Bool
    let period: TimePeriod
    
    init(stats: MonthlyStats?, isLoading: Bool, period: TimePeriod) {
        self.stats = stats
        self.isLoading = isLoading
        self.period = period
    }
    
    var body: some View {
        DashboardCard(title: period == .month ?
                     langManager.localized("monthly_total_spending") :
                     langManager.localized("yearly_total_spending"),
                     icon: "dollarsign.circle") {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let stats = stats {
                VStack(alignment: .leading, spacing: 12) {
                    // 總金額
                    Text(formatCurrency(stats.totalAmount))
                        .font(.title)
                        .bold()
                        .foregroundColor(.primary)
                    
                    // 與上期比較
                    if stats.previousMonthAmount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: stats.changePercentage >= 0 ?
                                  "arrow.up.right" : "arrow.down.right")
                                .font(.caption)
                            
                            Text("\(abs(stats.changePercentage), specifier: "%.1f")%")
                                .font(.subheadline)
                                .bold()
                            
                            Text(period == .month ?
                                 langManager.localized("vs_last_month") :
                                 langManager.localized("vs_last_year"))
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .foregroundColor(stats.changePercentage >= 0 ? .red : .green)
                    }
                    
                    // 交易筆數
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        Text("\(stats.transactionCount) \(langManager.localized("transactions_label"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 說明文字
                    Text(langManager.localized("dashboard_include_all_transactions"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            } else {
                Text(langManager.localized("no_data"))
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 分類分佈卡片（直向優化版）

struct CategoryBreakdownCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let categories: [CategoryStat]
    let isLoading: Bool
    
    var body: some View {
        DashboardCard(title: langManager.localized("category_distribution"), icon: "tag") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if categories.isEmpty {
                Text(langManager.localized("no_category_data"))
                    .foregroundColor(.secondary)
                    .italic()
                    .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    // 使用更寬嘅顯示方式
                    ForEach(Array(categories.prefix(5))) { stat in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                // 分類名稱和顏色
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: stat.category.colorHex ?? "#A8A8A8"))
                                        .frame(width: 10, height: 10)
                                    
                                    Text(stat.category.name)
                                        .font(.body)
                                        .lineLimit(1)
                                }
                                
                                Spacer()
                                
                                // 金額和百分比
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text(formatCurrency(stat.amount))
                                        .font(.body)
                                        .bold()
                                    
                                    Text("\(Int(stat.percentage))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            // 進度條（使用全寬度）
                            GeometryReader { geometry in
                                let barWidth = geometry.size.width * CGFloat(stat.percentage / 100)
                                
                                ZStack(alignment: .leading) {
                                    // 背景條
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(height: 6)
                                    
                                    // 前景條
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(
                                            stat.category.name == langManager.localized("uncategorized") ?
                                            Color.gray.opacity(0.6) :
                                            Color.blue.opacity(0.8)
                                        )
                                        .frame(width: barWidth, height: 6)
                                }
                            }
                            .frame(height: 6)
                        }
                        .padding(.vertical, 4)
                    }
                    
                    // 如果分類超過5個，顯示"查看更多"
                    if categories.count > 5 {
                        HStack {
                            Spacer()
                            Text("\(langManager.localized("view_more_categories")) (\(categories.count - 5) \(langManager.localized("categories_label")))")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .padding(.top, 4)
                            Spacer()
                        }
                    }
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 0  // 整數顯示，節省空間
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 日均消費卡片

struct DailyAverageCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let stats: MonthlyStats?
    let isLoading: Bool
    let period: TimePeriod
    
    init(stats: MonthlyStats?, isLoading: Bool, period: TimePeriod) {
        self.stats = stats
        self.isLoading = isLoading
        self.period = period
    }
    
    var body: some View {
        let title = langManager.localized("daily_average_spending")
        let periodText = period == .month ? langManager.localized("this_month") : langManager.localized("this_year")
        
        DashboardCard(title: title, icon: "calendar") {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let stats = stats {
                VStack(alignment: .leading, spacing: 10) {
                    // 日均消費金額
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatCurrency(stats.dailyAverage))
                            .font(.title)
                            .bold()
                            .foregroundColor(.primary)
                        
                        Text("/\(langManager.localized("day_unit"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 詳細說明
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "equal.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.7))
                            
                            Text(langManager.localized("calculation_method"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("\(langManager.localized("total_spending")) ÷ \(stats.periodDays)\(langManager.localized("days_unit"))")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.blue)
                        }
                        
                        Text("(\(periodText) \(langManager.localized("total_days")) \(stats.periodDays) \(langManager.localized("days_unit")))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
                    
                    // 顯示年視圖的每月平均
                    if period == .year {
                        Divider()
                            .padding(.vertical, 4)
                        
                        let monthlyAverage = stats.totalAmount > 0 ? stats.totalAmount / 12 : 0
                        HStack(spacing: 8) {
                            Image(systemName: "calendar.badge.clock")
                                .font(.caption)
                                .foregroundColor(.purple)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text(langManager.localized("monthly_average"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                Text(formatCurrency(monthlyAverage))
                                    .font(.subheadline)
                                    .bold()
                                    .foregroundColor(.purple)
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                    
                    // 最高交易（如果存在）
                    if let highest = stats.highestTransaction {
                        Divider()
                            .padding(.vertical, 4)
                        
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                // ✅ 修改這裡：使用更清晰的標題
                                Text(getHighestTransactionTitle())
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 4) {
                                    Text(formatCurrency(highest.totalAmount))
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.orange)
                                    
                                    // ✅ 修改這裡：使用更清晰的日期格式
                                    Text("(\(formatTransactionDate(highest.date)))")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text(langManager.localized("no_data"))
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text(langManager.localized("no_transactions_in_period"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
    
    // ✅ 新增：獲取最高交易標題
    private func getHighestTransactionTitle() -> String {
        switch period {
        case .month:
            return langManager.localized("highest_spending_day")
        case .year:
            return langManager.localized("highest_spending_date")
        }
    }
    
    // ✅ 新增：格式化交易日期
    private func formatTransactionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        
        switch period {
        case .month:
            // 月視圖：顯示日期，如 "25號" 或 "25th"
            formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "d號" : "d'日'"
            
            // 英文環境下添加序數後綴
            if langManager.selectedLanguage == .english {
                let day = Calendar.current.component(.day, from: date)
                let suffix = daySuffix(for: day)
                return "\(day)\(suffix)"
            }
            return formatter.string(from: date)
            
        case .year:
            // 年視圖：顯示月份和日期
            formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "M月d日" : "MMM d"
            return formatter.string(from: date)
        }
    }
    
    // ✅ 新增：英文日期序數後綴
    private func daySuffix(for day: Int) -> String {
        switch day {
        case 1, 21, 31:
            return "st"
        case 2, 22:
            return "nd"
        case 3, 23:
            return "rd"
        default:
            return "th"
        }
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: langManager.selectedLanguage.rawValue)
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}
// MARK: - 消費洞察卡片

struct SpendingInsightCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let insights: SpendingInsights?
    let isLoading: Bool
    let period: TimePeriod
    
    init(insights: SpendingInsights?, isLoading: Bool, period: TimePeriod) {
        self.insights = insights
        self.isLoading = isLoading
        self.period = period
    }
    
    var body: some View {
        DashboardCard(title: langManager.localized("spending_insights"), icon: "lightbulb") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let insights = insights {
                VStack(alignment: .leading, spacing: 16) {
                    // 根據週期顯示不同洞察
                    if period == .year {
                        // 年視圖：顯示月度洞察
                        yearlyInsightsView(insights: insights)
                    } else {
                        // 月視圖：顯示原有洞察
                        monthlyInsightsView(insights: insights)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "chart.bar.doc.horizontal")
                        .font(.system(size: 40))
                        .foregroundColor(.gray.opacity(0.3))
                    
                    Text(langManager.localized("no_insights_data"))
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text(langManager.localized("record_more_transactions_for_insights"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }
    
    private func monthlyInsightsView(insights: SpendingInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // 使用網格佈局顯示多個洞察
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // 洞察1：消費時段
                insightItem(
                    icon: "clock",
                    title: langManager.localized("primary_time_period"),
                    value: insights.mostActiveDay,
                    color: .blue
                )
                
                // 洞察2：週末比例
                let weekendRatio = Int(insights.weekendVsWeekdayRatio * 100)
                insightItem(
                    icon: "calendar",
                    title: langManager.localized("weekend_spending"),
                    value: "\(weekendRatio)%",
                    color: .orange
                )
                
                // 洞察3：交易筆數
                let totalTransactions = insights.weekdayTransactionCount + insights.weekendTransactionCount
                insightItem(
                    icon: "list.bullet",
                    title: langManager.localized("total_transactions_label"),
                    value: "\(totalTransactions)\(langManager.localized("transactions_unit"))",
                    color: .green
                )
                
                // 洞察4：最高消費
                if insights.peakSpendingAmount > 0 {
                    insightItem(
                        icon: "arrow.up.circle",
                        title: langManager.localized("highest_spending"),
                        value: formatCurrency(insights.peakSpendingAmount),
                        color: .red
                    )
                }
            }
            
            // 如果有最常用分類，顯示在下方
            if let category = insights.mostFrequentCategory {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.purple)
                        .font(.caption)
                    
                    Text("\(langManager.localized("most_used_category"))：")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(category.name)
                        .font(.caption)
                        .bold()
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
    }
    
    private func yearlyInsightsView(insights: SpendingInsights) -> some View {
        let totalTransactions = insights.weekdayTransactionCount + insights.weekendTransactionCount
        return VStack(alignment: .leading, spacing: 12) {
            // 年視圖專用洞察
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                // 洞察1：消費最高月份
                if let peakMonth = insights.peakMonth {
                    insightItem(
                        icon: "chart.bar.fill",
                        title: langManager.localized("highest_spending_month"),
                        value: peakMonth,
                        color: .blue
                    )
                    
                    insightItem(
                        icon: "dollarsign.circle.fill",
                        title: langManager.localized("month_amount"),
                        value: formatCurrency(insights.peakMonthAmount),
                        color: .blue
                    )
                }
                
                // 洞察2：週末比例
                let weekendRatio = Int(insights.weekendVsWeekdayRatio * 100)
                insightItem(
                    icon: "calendar",
                    title: langManager.localized("weekend_spending"),
                    value: "\(weekendRatio)%",
                    color: .orange
                )
                
                // 洞察3：交易筆數
                let totalTransactions = insights.weekdayTransactionCount + insights.weekendTransactionCount
                insightItem(
                    icon: "list.bullet",
                    title: langManager.localized("total_transactions_label"),
                    value: "\(totalTransactions)\(langManager.localized("transactions_unit"))",
                    color: .green
                )
                
                // 洞察4：最高消費
                if insights.peakSpendingAmount > 0 {
                    insightItem(
                        icon: "crown.fill",
                        title: langManager.localized("yearly_highest_spending"),
                        value: formatCurrency(insights.peakSpendingAmount),
                        color: .red
                    )
                }
            }
            
            // 如果有最常用分類，顯示在下方
            if let category = insights.mostFrequentCategory {
                HStack {
                    Image(systemName: "tag.fill")
                        .foregroundColor(.purple)
                        .font(.caption)
                    
                    Text("\(langManager.localized("yearly_most_used_category"))：")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(category.name)
                        .font(.caption)
                        .bold()
                    
                    Spacer()
                }
                .padding(.top, 4)
            }
            
            // 顯示週末/平日統計
            Divider()
                .padding(.vertical, 4)
            
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(langManager.localized("spending_time_distribution"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(langManager.localized("weekday"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(insights.weekdayTransactionCount)\(langManager.localized("transactions_unit"))")
                                .font(.body)
                                .bold()
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(langManager.localized("weekend"))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(insights.weekendTransactionCount)\(langManager.localized("transactions_unit"))")
                                .font(.body)
                                .bold()
                        }
                    }
                }
                
                Spacer()
                
                // 比例環形圖
                if totalTransactions > 0 {
                    let weekendPercentage = Double(insights.weekendTransactionCount) / Double(totalTransactions)
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 8)
                            .frame(width: 50, height: 50)
                        
                        Circle()
                            .trim(from: 0, to: CGFloat(weekendPercentage))
                            .stroke(Color.orange, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                            .frame(width: 50, height: 50)
                            .rotationEffect(.degrees(-90))
                        
                        Text("\(Int(weekendPercentage * 100))%")
                            .font(.caption)
                            .bold()
                    }
                }
            }
        }
    }
    
    private func insightItem(icon: String, title: String, value: String, color: Color) -> some View {
        VStack(spacing: 6) {
            // 圖標
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(height: 24)
            
            // 標題
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
            
            // 數值
            Text(value)
                .font(.body)
                .bold()
                .foregroundColor(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 通用卡片容器

struct DashboardCard<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {  // 稍微增加間距
            // 標題欄
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.bottom, 4)  // 增加標題與內容之間的距離
            
            // 內容
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)  // 佔滿寬度
        .padding(16)  // 使用一致padding
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}
