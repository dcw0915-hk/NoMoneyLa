// Category.swift
import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID = UUID()
    var name: String
    var order: Int = 0
    var colorHex: String?

    var assignedPayerIDs: [UUID] = []

    init(id: UUID = UUID(), name: String, order: Int = 0, colorHex: String? = nil, assignedPayerIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.order = order
        self.colorHex = colorHex
        self.assignedPayerIDs = assignedPayerIDs
    }
}

// MARK: - 擴展：計算屬性
extension Category {
    // 計算此分類的參與者（從交易中動態計算）
    func participants(in context: ModelContext) -> [Payer] {
        do {
            let subcategoriesFetch = FetchDescriptor<Subcategory>()
            let allSubcategories = try context.fetch(subcategoriesFetch)
            let subcategories = allSubcategories.filter { $0.parentID == self.id }
            let subcategoryIDs = subcategories.map { $0.id }

            if subcategoryIDs.isEmpty {
                return []
            }

            let transactionsFetch = FetchDescriptor<Transaction>()
            let allTransactions = try context.fetch(transactionsFetch)

            let transactions = allTransactions.filter { transaction in
                if let subID = transaction.subcategoryID {
                    return subcategoryIDs.contains(subID)
                }
                return false
            }

            var payerIDs = Set<UUID>()
            for transaction in transactions {
                for contribution in transaction.contributions {
                    payerIDs.insert(contribution.payer.id)
                }
            }

            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            return allPayers.filter { payerIDs.contains($0.id) }
        } catch {
            print("計算分類參與者時出錯：\(error)")
            return []
        }
    }

    // 計算分類總金額
    func totalAmount(in context: ModelContext) -> Decimal {
        do {
            let subcategoriesFetch = FetchDescriptor<Subcategory>()
            let allSubcategories = try context.fetch(subcategoriesFetch)
            let subcategories = allSubcategories.filter { $0.parentID == self.id }
            let subcategoryIDs = subcategories.map { $0.id }

            if subcategoryIDs.isEmpty {
                return 0
            }

            let transactionsFetch = FetchDescriptor<Transaction>()
            let allTransactions = try context.fetch(transactionsFetch)

            let transactions = allTransactions.filter { transaction in
                if let subID = transaction.subcategoryID {
                    return subcategoryIDs.contains(subID)
                }
                return false
            }

            return transactions.reduce(0) { $0 + $1.totalAmount }
        } catch {
            print("計算分類總金額時出錯：\(error)")
            return 0
        }
    }

    // 獲取已分配的付款人
    func assignedPayers(in context: ModelContext) -> [Payer] {
        guard !assignedPayerIDs.isEmpty else {
            print("DEBUG [Category.assignedPayers]: assignedPayerIDs 為空")
            return []
        }
        
        print("DEBUG [Category.assignedPayers]: 開始獲取已分配付款人")
        print("  - assignedPayerIDs: \(assignedPayerIDs)")
        
        do {
            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            print("  - 資料庫中總共有 \(allPayers.count) 個付款人")
            
            // 逐一查找每個 ID 對應的付款人
            var result: [Payer] = []
            for payerID in assignedPayerIDs {
                if let payer = allPayers.first(where: { $0.id == payerID }) {
                    result.append(payer)
                    print("  - 找到付款人: \(payer.name) (ID: \(payerID))")
                } else {
                    print("  - 警告: 找不到 ID 為 \(payerID) 的付款人")
                }
            }
            
            print("  - 總共找到 \(result.count) 個已分配付款人")
            return result
        } catch {
            print("DEBUG [Category.assignedPayers]: 獲取分配付款人時出錯：\(error)")
            return []
        }
    }

    // 檢查是否分配了付款人
    var hasAssignedPayers: Bool {
        !assignedPayerIDs.isEmpty
    }
}
