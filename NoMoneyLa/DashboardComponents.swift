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

// MARK: - 統計卡片組件

struct TotalSpendingCard: View {
    let stats: MonthlyStats?
    let isLoading: Bool
    
    var body: some View {
        DashboardCard(title: "總消費", icon: "dollarsign.circle") {
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
                    
                    // 與上月比較
                    if stats.previousMonthAmount > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: stats.changePercentage >= 0 ?
                                  "arrow.up.right" : "arrow.down.right")
                                .font(.caption)
                            
                            Text("\(abs(stats.changePercentage), specifier: "%.1f")%")
                                .font(.subheadline)
                                .bold()
                            
                            Text("vs 上月")
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
}

struct CategoryBreakdownCard: View {
    let categories: [CategoryStat]
    let isLoading: Bool
    
    var body: some View {
        DashboardCard(title: "分類分佈", icon: "tag") {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if categories.isEmpty {
                Text("無分類數據")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(spacing: 12) {
                    ForEach(Array(categories.prefix(4))) { stat in
                        HStack(spacing: 12) {
                            // 分類顏色標記
                            Circle()
                                .fill(Color(hex: stat.category.colorHex ?? "#A8A8A8"))
                                .frame(width: 12, height: 12)
                            
                            // 分類名稱
                            Text(stat.category.name)
                                .font(.subheadline)
                                .lineLimit(1)
                                .frame(width: 80, alignment: .leading)
                            
                            // 進度條
                            GeometryReader { geometry in
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(Color.blue.opacity(0.2))
                                    .frame(width: geometry.size.width * CGFloat(stat.percentage / 100))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .frame(height: 6)
                            
                            // 百分比
                            Text("\(Int(stat.percentage))%")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .frame(height: 20)
                    }
                }
            }
        }
    }
}

struct DailyAverageCard: View {
    let stats: MonthlyStats?
    let isLoading: Bool
    
    var body: some View {
        DashboardCard(title: "日均消費", icon: "calendar") {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let stats = stats {
                VStack(alignment: .leading, spacing: 8) {
                    Text(formatCurrency(stats.dailyAverage))
                        .font(.title2)
                        .bold()
                        .foregroundColor(.primary)
                    
                    if let highest = stats.highestTransaction {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            
                            Text("最高：\(formatCurrency(highest.totalAmount))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            Text(highest.date, format: .dateTime.day())
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("平均每日")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            } else {
                Text("無數據")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct SpendingInsightCard: View {
    let insights: SpendingInsights?
    let isLoading: Bool
    
    var body: some View {
        DashboardCard(title: "消費洞察", icon: "lightbulb") {
            if isLoading {
                ProgressView()
                    .scaleEffect(0.8)
            } else if let insights = insights {
                VStack(alignment: .leading, spacing: 10) {
                    // 最活躍消費日
                    if !insights.mostActiveDay.isEmpty {
                        InsightRow(
                            icon: "clock",
                            title: "主要消費",
                            value: insights.mostActiveDay
                        )
                    }
                    
                    // 最常用分類
                    if let category = insights.mostFrequentCategory {
                        InsightRow(
                            icon: "tag",
                            title: "最常用",
                            value: category.name
                        )
                    }
                    
                    // 週末消費比例
                    if insights.weekendVsWeekdayRatio > 0 {
                        InsightRow(
                            icon: "calendar.badge.clock",
                            title: "週末消費",
                            value: "\(Int(insights.weekendVsWeekdayRatio * 100))%"
                        )
                    }
                }
            } else {
                Text("無洞察數據")
                    .foregroundColor(.secondary)
                    .italic()
            }
        }
    }
}

struct InsightRow: View {
    let icon: String
    let title: String
    let value: String
    
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(.blue)
                .frame(width: 20)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.subheadline)
                .bold()
        }
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
        VStack(alignment: .leading, spacing: 16) {
            // 標題欄
            HStack {
                Label(title, systemImage: icon)
                    .font(.headline)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            
            // 內容
            content
        }
        .padding(16)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
    }
}

