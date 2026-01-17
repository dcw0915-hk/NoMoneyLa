import SwiftData
import Foundation

@Model
final class Transaction {
    var id: UUID
    var amount: Decimal
    var date: Date
    var note: String?
    var categoryID: UUID?
    var type: TransactionType
    var currencyCode: String   // 👈 新增欄位

    init(id: UUID = UUID(),
         amount: Decimal,
         date: Date,
         note: String? = nil,
         categoryID: UUID? = nil,
         type: TransactionType,
         currencyCode: String = "HKD") {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.categoryID = categoryID
        self.type = type
        self.currencyCode = currencyCode
    }
}
