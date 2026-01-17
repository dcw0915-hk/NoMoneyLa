import SwiftData
import Foundation

@Model
final class Subcategory {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID      // 指向 Category.id
    var order: Int = 0
    var colorHex: String?

    init(id: UUID = UUID(), name: String, parentID: UUID, order: Int = 0, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.order = order
        self.colorHex = colorHex
    }
}
