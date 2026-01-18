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

    // 驗證分攤金額
    var isAmountValid: Bool {
        if contributions.isEmpty {
            return true
        }
        let sum = contributions.reduce(0) { $0 + $1.amount }
        return sum == totalAmount
    }

    // 主要付款人
    var primaryPayer: Payer? {
        contributions.max(by: { $0.amount < $1.amount })?.payer
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
