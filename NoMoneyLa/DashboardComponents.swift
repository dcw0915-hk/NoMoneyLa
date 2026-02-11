import SwiftUI
import SwiftData

// MARK: - 共用類型定義（UI 層使用）
enum TimePeriod: String, CaseIterable {
    case month = "month"
    case year = "year"
}

// MARK: - ✅ CategoryStat 已在 ViewModel 定義，此處唔重複
//        UI 層直接使用 ViewModel 嘅 CategoryStat

// MARK: - 控制欄組件（不變）
struct DashboardControlBar: View {
    @Binding var selectedPayer: Payer?
    @Binding var selectedPeriod: TimePeriod
    @Binding var selectedDate: Date
    let allPayers: [Payer]
    
    var body: some View {
        VStack(spacing: 16) {
            PayerSelectionView(
                selectedPayer: $selectedPayer,
                allPayers: allPayers
            )
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
            Picker(langManager.localized("dashboard_period"), selection: $selectedPeriod) {
                ForEach(TimePeriod.allCases, id: \.self) { period in
                    Text(langManager.localized(period == .month ? "period_month" : "period_year")).tag(period)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 200)
            
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
        case .month: dateComponent.month = value
        case .year:  dateComponent.year = value
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

// MARK: - 篩選欄組件（不變）
struct FilterBarView: View {
    @EnvironmentObject var langManager: LanguageManager
    let filterType: TransactionType?
    let filterCategory: Category?
    let filterSubcategory: Subcategory?
    let filterPayer: Payer?
    let filterDateRange: String?
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

// MARK: - 工具欄菜單組件（不變）
struct ToolbarMenuView: View {
    @EnvironmentObject var langManager: LanguageManager
    let categories: [Category]
    let subcategories: [Subcategory]
    let payers: [Payer]
    let filterCategory: Category?
    let filterType: TransactionType?
    let filterSubcategory: Subcategory?
    let filterPayer: Payer?
    let onSelectType: (TransactionType?) -> Void
    let onSelectCategory: (Category?) -> Void
    let onSelectSubcategory: (Subcategory?) -> Void
    let onSelectPayer: (Payer?) -> Void
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

// MARK: - 總消費卡片（支援多貨幣，不變）
struct TotalSpendingCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let totalAmounts: [String: Decimal]
    let transactionCount: Int
    let previousMonthAmounts: [String: Decimal]?
    let changePercentages: [String: Double]?
    let isLoading: Bool
    let period: TimePeriod
    
    init(totalAmounts: [String: Decimal], transactionCount: Int,
         previousMonthAmounts: [String: Decimal]? = nil,
         changePercentages: [String: Double]? = nil,
         isLoading: Bool, period: TimePeriod) {
        self.totalAmounts = totalAmounts
        self.transactionCount = transactionCount
        self.previousMonthAmounts = previousMonthAmounts
        self.changePercentages = changePercentages
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
            } else if totalAmounts.isEmpty {
                Text(langManager.localized("no_data"))
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if totalAmounts.count == 1, let (code, amount) = totalAmounts.first {
                        Text(formatCurrency(amount: amount, code: code))
                            .font(.title)
                            .bold()
                            .foregroundColor(.primary)
                        
                        if code == "HKD", let prev = previousMonthAmounts?["HKD"], prev > 0,
                           let change = changePercentages?["HKD"] {
                            HStack(spacing: 6) {
                                Image(systemName: change >= 0 ? "arrow.up.right" : "arrow.down.right")
                                    .font(.caption)
                                Text("\(abs(change), specifier: "%.1f")%")
                                    .font(.subheadline)
                                    .bold()
                                Text(period == .month ?
                                     langManager.localized("vs_last_month") :
                                     langManager.localized("vs_last_year"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .foregroundColor(change >= 0 ? .red : .green)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                    .font(.caption)
                                Text(langManager.localized("multiple_currencies"))
                                    .font(.headline)
                                    .foregroundColor(.orange)
                            }
                            
                            ForEach(totalAmounts.sorted(by: { $0.value > $1.value }), id: \.key) { code, amount in
                                HStack {
                                    Text(code)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                    Spacer()
                                    Text(formatCurrency(amount: amount, code: code))
                                        .font(.body)
                                        .bold()
                                }
                            }
                        }
                    }
                    
                    HStack {
                        Image(systemName: "list.bullet")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("\(transactionCount) \(langManager.localized("transactions_label"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Text(langManager.localized("dashboard_include_all_transactions"))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }
    
    private func formatCurrency(amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - ✅ 分類分佈卡片（支援多貨幣）
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
                    ForEach(Array(categories.prefix(5))) { stat in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(Color(hex: stat.category.colorHex ?? "#A8A8A8"))
                                        .frame(width: 10, height: 10)
                                    Text(stat.category.name)
                                        .font(.body)
                                        .lineLimit(1)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    // ✅ 使用分類本身嘅貨幣代碼
                                    Text(formatCurrency(amount: stat.amount, code: stat.currencyCode))
                                        .font(.body)
                                        .bold()
                                    // 顯示貨幣代碼作為輔助信息
                                    Text("\(stat.currencyCode) · \(Int(stat.percentage))%")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            // 進度條仍然以百分比顯示，唔受貨幣影響
                            GeometryReader { geometry in
                                let barWidth = geometry.size.width * CGFloat(stat.percentage / 100)
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 3)
                                        .fill(Color.gray.opacity(0.15))
                                        .frame(height: 6)
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
    
    private func formatCurrency(amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 日均消費卡片（不變）
struct DailyAverageCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let stats: MonthlyStats?
    let isLoading: Bool
    let period: TimePeriod
    
    var body: some View {
        DashboardCard(title: langManager.localized("daily_average_spending"), icon: "calendar") {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let stats = stats {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formatCurrency(stats.dailyAverage))
                            .font(.title)
                            .bold()
                            .foregroundColor(.primary)
                        Text("/\(langManager.localized("day_unit"))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
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
                        Text("(\(period == .month ? langManager.localized("this_month") : langManager.localized("this_year")) \(langManager.localized("total_days")) \(stats.periodDays) \(langManager.localized("days_unit")))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.blue.opacity(0.1))
                    )
                    
                    if period == .year {
                        Divider()
                            .padding(.vertical, 4)
                        let monthlyAverage = (stats.totalAmounts["HKD"] ?? 0) / 12
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
                    
                    if let highest = stats.highestTransaction {
                        Divider()
                            .padding(.vertical, 4)
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.caption)
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(period == .month ?
                                     langManager.localized("highest_spending_day") :
                                     langManager.localized("highest_spending_date"))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Text(formatCurrency(amount: highest.totalAmount, code: highest.currencyCode))
                                        .font(.subheadline)
                                        .bold()
                                        .foregroundColor(.orange)
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
                }
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
    
    private func formatCurrency(amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
    
    private func formatTransactionDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = langManager.selectedLanguage == .chineseHK ? "M/d" : "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - 消費洞察卡片（不變）
struct SpendingInsightCard: View {
    @EnvironmentObject var langManager: LanguageManager
    let insights: SpendingInsights?
    let isLoading: Bool
    let period: TimePeriod
    
    var body: some View {
        DashboardCard(title: langManager.localized("spending_insights"), icon: "lightbulb") {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding()
            } else if let insights = insights {
                VStack(alignment: .leading, spacing: 16) {
                    if period == .year {
                        yearlyInsightsView(insights: insights)
                    } else {
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
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            }
        }
    }
    
    private func monthlyInsightsView(insights: SpendingInsights) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                insightItem(
                    icon: "clock",
                    title: langManager.localized("primary_time_period"),
                    value: insights.mostActiveDay,
                    color: .blue
                )
                insightItem(
                    icon: "calendar",
                    title: langManager.localized("weekend_spending"),
                    value: "\(Int(insights.weekendVsWeekdayRatio * 100))%",
                    color: .orange
                )
                insightItem(
                    icon: "list.bullet",
                    title: langManager.localized("total_transactions_label"),
                    value: "\(insights.weekdayTransactionCount + insights.weekendTransactionCount)\(langManager.localized("transactions_unit"))",
                    color: .green
                )
                if insights.peakSpendingAmount > 0 {
                    insightItem(
                        icon: "arrow.up.circle",
                        title: langManager.localized("highest_spending"),
                        value: formatCurrency(insights.peakSpendingAmount, code: "HKD"),
                        color: .red
                    )
                }
            }
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
        VStack(alignment: .leading, spacing: 12) {
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
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
                        value: formatCurrency(insights.peakMonthAmount, code: "HKD"),
                        color: .blue
                    )
                }
                insightItem(
                    icon: "calendar",
                    title: langManager.localized("weekend_spending"),
                    value: "\(Int(insights.weekendVsWeekdayRatio * 100))%",
                    color: .orange
                )
                insightItem(
                    icon: "list.bullet",
                    title: langManager.localized("total_transactions_label"),
                    value: "\(insights.weekdayTransactionCount + insights.weekendTransactionCount)\(langManager.localized("transactions_unit"))",
                    color: .green
                )
                if insights.peakSpendingAmount > 0 {
                    insightItem(
                        icon: "crown.fill",
                        title: langManager.localized("yearly_highest_spending"),
                        value: formatCurrency(insights.peakSpendingAmount, code: "HKD"),
                        color: .red
                    )
                }
            }
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
                let totalTransactions = insights.weekdayTransactionCount + insights.weekendTransactionCount
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
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
                .frame(height: 24)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(1)
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
    
    private func formatCurrency(_ amount: Decimal, code: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        formatter.maximumFractionDigits = 0
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }
}

// MARK: - 通用卡片容器（不變）
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
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(.primary)
                Spacer()
            }
            .padding(.bottom, 4)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}
