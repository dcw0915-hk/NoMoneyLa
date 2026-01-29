import Foundation

// MARK: - 貨幣格式化
func formatCurrency(_ amount: Decimal) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = "HKD"
    formatter.maximumFractionDigits = 2
    return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
}

func formatCurrency(_ amount: Decimal, code: String) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .currency
    formatter.currencyCode = code
    formatter.maximumFractionDigits = 2
    return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
}

// MARK: - 日期格式化
func formatDate(_ date: Date, format: String = "yyyy-MM-dd") -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = format
    return formatter.string(from: date)
}

// MARK: - 其他工具函數
func calculatePercentage(_ part: Decimal, _ total: Decimal) -> Double {
    guard total > 0 else { return 0 }
    return Double(truncating: (part / total * 100) as NSDecimalNumber)
}
