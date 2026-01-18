// Payer.swift
import SwiftData
import Foundation

@Model
final class Payer {
    var id: UUID = UUID()
    var name: String
    var order: Int = 0
    var isDefault: Bool = false
    var colorHex: String?
    @Relationship(deleteRule: .cascade) var contributions: [PaymentContribution] = []

    init(id: UUID = UUID(), name: String, order: Int = 0, isDefault: Bool = false, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.isDefault = isDefault
        self.colorHex = colorHex
    }
}
