import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID?
    var order: Int = 0
    var colorHex: String?   // store color as hex string (e.g., "#FF6B6B")

    init(id: UUID = UUID(), name: String, parentID: UUID? = nil, order: Int = 0, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.order = order
        self.colorHex = colorHex
    }
}
