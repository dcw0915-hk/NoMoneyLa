import SwiftData
import Foundation

@Model
final class Transaction {
    var id: UUID = UUID()
    var amount: Decimal
    var date: Date
    var note: String?
    var subcategoryID: UUID?   // 改為子分類
    var type: TransactionType
    var currencyCode: String

    init(id: UUID = UUID(),
         amount: Decimal,
         date: Date,
         note: String? = nil,
         subcategoryID: UUID? = nil,
         type: TransactionType,
         currencyCode: String = "HKD") {
        self.id = id
        self.amount = amount
        self.date = date
        self.note = note
        self.subcategoryID = subcategoryID
        self.type = type
        self.currencyCode = currencyCode
    }
}
