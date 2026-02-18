import SwiftData
import Foundation

@Model
final class Subcategory {
    var id: UUID = UUID()
    var name: String
    var parentID: UUID      // 指向 Category.id
    var order: Int = 0
    var colorHex: String?
    var isUncategorized: Bool = false  // 新增：標記是否為「未分類」子分類

    init(id: UUID = UUID(), name: String, parentID: UUID, order: Int = 0, colorHex: String? = nil, isUncategorized: Bool = false) {
        self.id = id
        self.name = name
        self.parentID = parentID
        self.order = order
        self.colorHex = colorHex
        self.isUncategorized = isUncategorized
    }
}
