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
    case month = "月"
    case year = "年"
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
    @Binding var selectedPayer: Payer?
    let allPayers: [Payer]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("分析對象")
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
    @Binding var selectedPeriod: TimePeriod
    @Binding var selectedDate: Date
    
    var body: some View {
        VStack(spacing: 12) {
            // 月/年切換
            Picker("週期", selection: $selectedPeriod) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Text(period.rawValue).tag(period)
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
            formatter.dateFormat = "yyyy年M月"
        case .year:
            formatter.dateFormat = "yyyy年"
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
                Button("所有付款人") {
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
                Label(filterPayer?.name ?? "付款人", systemImage: "person.2")
            }
        }
    }
}

// MARK: - 統計卡片組件

struct TotalSpendingCard: View {
    let stats: MonthlyStats?
    let isLoading: Bool
    let period: TimePeriod  // 新增：知道當前週期
    
    init(stats: MonthlyStats?, isLoading: Bool, period: TimePeriod) {
        self.stats = stats
        self.isLoading = isLoading
        self.period = period
    }
    
    var body: some View {
        DashboardCard(title: period == .month ? "本月消費" : "今年消費", icon: "dollarsign.circle") {
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
                            
                            Text(period == .month ? "vs 上月" : "vs 上年")
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
                        
                        Text("\(stats.transactionCount) 筆交易")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("無數據")
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
    let categories: [CategoryStat]
    let isLoading: Bool
    
    var body: some View {
        DashboardCard(title: "分類分佈", icon: "tag") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if categories.isEmpty {
                Text("無分類數據")
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
                                            stat.category.name == "無" ?
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
                            Text("查看更多分類 (\(categories.count - 5) 個)")
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
    let stats: MonthlyStats?
    let isLoading: Bool
    let period: TimePeriod
    
    init(stats: MonthlyStats?, isLoading: Bool, period: TimePeriod) {
        self.stats = stats
        self.isLoading = isLoading
        self.period = period
    }
    
    var body: some View {
        let title = period == .month ? "日均消費" : "日均消費"
        let periodText = period == .month ? "本月" : "今年"
        
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
                        
                        Text("/日")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // 詳細說明
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 4) {
                            Image(systemName: "equal.circle.fill")
                                .font(.caption2)
                                .foregroundColor(.blue.opacity(0.7))
                            
                            Text("計算方式：")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            
                            Text("總消費 ÷ \(stats.periodDays)日")
                                .font(.caption2)
                                .bold()
                                .foregroundColor(.blue)
                        }
                        
                        Text("(\(periodText)共 \(stats.periodDays) 日)")
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
                                Text("月均消費")
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
                                Text(period == .month ? "最高單筆消費" : "年度最高消費")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                HStack(spacing: 4) {
                                    Text(formatCurrency(highest.totalAmount))
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.orange)
                                    
                                    if period == .month {
                                        Text("(\(highest.date, format: .dateTime.day())日)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    } else {
                                        Text("(\(highest.date, format: .dateTime.month().day()))")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            
                            Spacer()
                        }
                        .padding(.top, 2)
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("無數據")
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text("在選定的時間範圍內沒有找到消費記錄")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
    }
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "HKD"
        formatter.maximumFractionDigits = 0
        formatter.minimumFractionDigits = 0
        formatter.locale = Locale(identifier: "zh_HK")
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 消費洞察卡片

struct SpendingInsightCard: View {
    let insights: SpendingInsights?
    let isLoading: Bool
    let period: TimePeriod
    
    init(insights: SpendingInsights?, isLoading: Bool, period: TimePeriod) {
        self.insights = insights
        self.isLoading = isLoading
        self.period = period
    }
    
    var body: some View {
        DashboardCard(title: "消費洞察", icon: "lightbulb") {
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
                    
                    Text("暫無洞察數據")
                        .font(.body)
                        .foregroundColor(.secondary)
                        .italic()
                    
                    Text("記錄更多交易以獲得洞察")
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
                    title: "主要時段",
                    value: insights.mostActiveDay,
                    color: .blue
                )
                
                // 洞察2：週末比例
                let weekendRatio = Int(insights.weekendVsWeekdayRatio * 100)
                insightItem(
                    icon: "calendar",
                    title: "週末消費",
                    value: "\(weekendRatio)%",
                    color: .orange
                )
                
                // 洞察3：交易筆數
                let totalTransactions = insights.weekdayTransactionCount + insights.weekendTransactionCount
                insightItem(
                    icon: "list.bullet",
                    title: "總交易",
                    value: "\(totalTransactions)筆",
                    color: .green
                )
                
                // 洞察4：最高消費
                if insights.peakSpendingAmount > 0 {
                    insightItem(
                        icon: "arrow.up.circle",
                        title: "最高消費",
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
                    
                    Text("最常用分類：")
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
                        title: "消費最高月",
                        value: peakMonth,
                        color: .blue
                    )
                    
                    insightItem(
                        icon: "dollarsign.circle.fill",
                        title: "該月金額",
                        value: formatCurrency(insights.peakMonthAmount),
                        color: .blue
                    )
                }
                
                // 洞察2：週末比例
                let weekendRatio = Int(insights.weekendVsWeekdayRatio * 100)
                insightItem(
                    icon: "calendar",
                    title: "週末消費",
                    value: "\(weekendRatio)%",
                    color: .orange
                )
                
                // 洞察3：交易筆數
                let totalTransactions = insights.weekdayTransactionCount + insights.weekendTransactionCount
                insightItem(
                    icon: "list.bullet",
                    title: "總交易",
                    value: "\(totalTransactions)筆",
                    color: .green
                )
                
                // 洞察4：最高消費
                if insights.peakSpendingAmount > 0 {
                    insightItem(
                        icon: "crown.fill",
                        title: "年度最高",
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
                    
                    Text("年度最常用分類：")
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
                    Text("消費時間分布")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("平日")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(insights.weekdayTransactionCount)筆")
                                .font(.body)
                                .bold()
                        }
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text("週末")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text("\(insights.weekendTransactionCount)筆")
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
