// Transaction.swift
import SwiftData
import Foundation

@Model
final class Transaction {
    var id: UUID = UUID()
    var totalAmount: Decimal
    var date: Date
    var note: String?
    var subcategoryID: UUID?
    var type: TransactionType
    var currencyCode: String
    @Relationship(deleteRule: .cascade) var contributions: [PaymentContribution] = []

    // 相容性屬性
    var amount: Decimal {
        get { totalAmount }
        set { totalAmount = newValue }
    }

    // ✅ 修復：改進的分攤金額驗證
    var isAmountValid: Bool {
        // 收入交易不需要分攤驗證
        guard type == .expense else { return true }
        
        // 如果完全沒有分攤，視為無效
        if contributions.isEmpty {
            return false
        }
        
        // 帶容差比較分攤總額
        let sum = contributions.reduce(Decimal(0)) { $0 + $1.amount }
        let difference = abs(sum - totalAmount)
        let tolerance = Decimal(0.01)
        
        return difference <= tolerance
    }
    
    // ✅ 新增：獲取分攤狀態描述
    var contributionStatusDescription: String {
        // 收入交易不需要分攤驗證
        guard type == .expense else { return "" }
        
        if contributions.isEmpty {
            return "⚠️ 無分攤"
        }
        
        let sum = contributions.reduce(Decimal(0)) { $0 + $1.amount }
        let difference = sum - totalAmount
        
        if abs(difference) <= Decimal(0.01) {
            return "✅ 分攤正確"
        } else if difference > 0 {
            return "⚠️ 分攤過多 \(formatCurrency(abs(difference)))"
        } else {
            return "⚠️ 分攤不足 \(formatCurrency(abs(difference)))"
        }
    }
    
    // ✅ 新增：獲取分攤差異金額
    var contributionDifference: Decimal {
        guard type == .expense && !contributions.isEmpty else { return 0 }
        let sum = contributions.reduce(Decimal(0)) { $0 + $1.amount }
        return sum - totalAmount
    }
    
    // ✅ 新增：獲取分攤狀態代碼（用於 UI 層決定顏色）
    enum ContributionStatusCode: String {
        case noContributions = "no_contributions"
        case balanced = "balanced"
        case insufficient = "insufficient"
        case excess = "excess"
    }
    
    var contributionStatusCode: ContributionStatusCode {
        guard type == .expense else { return .balanced }
        
        if contributions.isEmpty {
            return .noContributions
        }
        
        let sum = contributions.reduce(Decimal(0)) { $0 + $1.amount }
        let difference = sum - totalAmount
        
        if abs(difference) <= Decimal(0.01) {
            return .balanced
        } else if difference > 0 {
            return .excess
        } else {
            return .insufficient
        }
    }
    
    // ✅ 新增：驗證嚴重程度（用於 UI 層）
    enum ValidationSeverity: String {
        case valid = "valid"           // 完全正確
        case warning = "warning"       // 有小問題，但可接受
        case error = "error"           // 有嚴重問題，需要關注
    }
    
    var validationSeverity: ValidationSeverity {
        if type == .expense && contributions.isEmpty {
            return .error    // 空分攤是嚴重問題
        }
        
        let sum = contributions.reduce(Decimal(0)) { $0 + $1.amount }
        let difference = abs(sum - totalAmount)
        
        if difference <= Decimal(0.01) {
            return .valid    // 在容差內
        } else if difference <= Decimal(1.00) {
            return .warning  // 小額誤差
        } else {
            return .error    // 大額誤差
        }
    }

    // 主要付款人
    var primaryPayer: Payer? {
        contributions.max(by: { $0.amount < $1.amount })?.payer
    }
    
    // ✅ 新增：計算每人平均分攤
    func calculateEqualSplit() -> Decimal? {
        guard type == .expense && !contributions.isEmpty else { return nil }
        return totalAmount / Decimal(contributions.count)
    }
    
    // ✅ 新增：格式化貨幣的輔助方法
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    init(id: UUID = UUID(),
         totalAmount: Decimal,
         date: Date,
         note: String? = nil,
         subcategoryID: UUID? = nil,
         type: TransactionType,
         currencyCode: String = "HKD",
         contributions: [PaymentContribution] = []) {
        self.id = id
        self.totalAmount = totalAmount
        self.date = date
        self.note = note
        self.subcategoryID = subcategoryID
        self.type = type
        self.currencyCode = currencyCode
        self.contributions = contributions
    }
    
    // 相容舊版初始化
    convenience init(id: UUID = UUID(),
                     amount: Decimal,
                     date: Date,
                     note: String? = nil,
                     subcategoryID: UUID? = nil,
                     type: TransactionType,
                     currencyCode: String = "HKD") {
        self.init(id: id,
                  totalAmount: amount,
                  date: date,
                  note: note,
                  subcategoryID: subcategoryID,
                  type: type,
                  currencyCode: currencyCode,
                  contributions: [])
    }
}
