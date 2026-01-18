// PaymentContribution.swift
import SwiftData
import Foundation

@Model
final class PaymentContribution {
    var id: UUID = UUID()
    var amount: Decimal
    var payer: Payer
    var transaction: Transaction

    init(id: UUID = UUID(), amount: Decimal, payer: Payer, transaction: Transaction) {
        self.id = id
        self.amount = amount
        self.payer = payer
        self.transaction = transaction
    }
}
