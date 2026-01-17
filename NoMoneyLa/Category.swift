import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID = UUID()
    var name: String
    var order: Int = 0
    var colorHex: String?    // 可選：父分類也可有顏色

    init(id: UUID = UUID(), name: String, order: Int = 0, colorHex: String? = nil) {
        self.id = id
        self.name = name
        self.order = order
        self.colorHex = colorHex
    }
}
