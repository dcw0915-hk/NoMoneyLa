// Category.swift
import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID = UUID()
    var name: String
    var order: Int = 0
    var colorHex: String?    // 可選：父分類也可有顏色

    // 分類專用付款人（儲存 Payer 的 id）
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
            // 獲取此分類下的所有子分類
            let subcategoriesFetch = FetchDescriptor<Subcategory>()
            let allSubcategories = try context.fetch(subcategoriesFetch)
            let subcategories = allSubcategories.filter { $0.parentID == self.id }
            let subcategoryIDs = subcategories.map { $0.id }

            if subcategoryIDs.isEmpty {
                return []
            }

            // 獲取此分類下的所有交易
            let transactionsFetch = FetchDescriptor<Transaction>()
            let allTransactions = try context.fetch(transactionsFetch)

            // 篩選屬於此分類的交易
            let transactions = allTransactions.filter { transaction in
                if let subID = transaction.subcategoryID {
                    return subcategoryIDs.contains(subID)
                }
                return false
            }

            // 從交易中收集所有付款人
            var payerIDs = Set<UUID>()
            for transaction in transactions {
                for contribution in transaction.contributions {
                    payerIDs.insert(contribution.payer.id)
                }
            }

            // 獲取對應的付款人對象
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
        guard !assignedPayerIDs.isEmpty else { return [] }

        do {
            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            return allPayers.filter { assignedPayerIDs.contains($0.id) }
        } catch {
            print("獲取分配付款人時出錯：\(error)")
            return []
        }
    }

    // 檢查是否分配了付款人
    var hasAssignedPayers: Bool {
        !assignedPayerIDs.isEmpty
    }
}
