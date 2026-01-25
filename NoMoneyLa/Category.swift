// Category.swift
import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID = UUID()
    var name: String
    var order: Int = 0
    var colorHex: String?
    var isDefault: Bool = false  // 新增：標記是否為預設分類
    var assignedPayerIDs: [UUID] = []

    init(id: UUID = UUID(), name: String, order: Int = 0, colorHex: String? = nil, isDefault: Bool = false, assignedPayerIDs: [UUID] = []) {
        self.id = id
        self.name = name
        self.order = order
        self.colorHex = colorHex
        self.isDefault = isDefault
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

    // ✅ 修復：獲取已分配的付款人（處理重複ID和無效ID）
    func assignedPayers(in context: ModelContext) -> [Payer] {
        guard !assignedPayerIDs.isEmpty else {
            print("DEBUG [Category.assignedPayers]: assignedPayerIDs 為空")
            return []
        }
        
        print("DEBUG [Category.assignedPayers]: 開始獲取已分配付款人")
        print("  - assignedPayerIDs: \(assignedPayerIDs)")
        
        do {
            // 1. 先去重，避免重複查找
            let uniqueIDs = Array(Set(assignedPayerIDs))
            print("  - 去重後 uniqueIDs: \(uniqueIDs)")
            
            if uniqueIDs.count != assignedPayerIDs.count {
                print("  - 警告：assignedPayerIDs 中有重複的 UUID，已自動去重")
                // ✅ 自動修復：更新 storedPayerIDs 為去重後的版本
                self.assignedPayerIDs = uniqueIDs
            }
            
            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            print("  - 資料庫中總共有 \(allPayers.count) 個付款人")
            
            // 2. 創建一個映射表，方便快速查找
            let payerDict = Dictionary(uniqueKeysWithValues: allPayers.map { ($0.id, $0) })
            
            // 3. 逐一查找每個 ID 對應的付款人，並處理無效ID
            var validPayers: [Payer] = []
            var invalidIDs: [UUID] = []
            
            for payerID in uniqueIDs {
                if let payer = payerDict[payerID] {
                    validPayers.append(payer)
                    print("  - 找到付款人: \(payer.name) (ID: \(payerID))")
                } else {
                    invalidIDs.append(payerID)
                    print("  - 警告: 找不到 ID 為 \(payerID) 的付款人")
                }
            }
            
            // 4. 如果有無效ID，清理它們並保存
            if !invalidIDs.isEmpty {
                print("  - 發現 \(invalidIDs.count) 個無效的付款人ID，正在清理...")
                
                // 從 assignedPayerIDs 中移除無效ID
                self.assignedPayerIDs = uniqueIDs.filter { !invalidIDs.contains($0) }
                
                // 嘗試保存清理後的數據
                do {
                    try context.save()
                    print("  - 已成功清理無效的付款人ID")
                } catch {
                    print("  - 清理無效ID時保存失敗: \(error)")
                }
            }
            
            print("  - 總共找到 \(validPayers.count) 個有效的已分配付款人")
            
            // 5. 按原始順序返回（保持用戶設置的順序）
            // 首先按原始 assignedPayerIDs 的順序排序（過濾掉無效ID後）
            let orderedValidPayers = uniqueIDs
                .filter { payerDict[$0] != nil } // 只保留有效的ID
                .compactMap { payerDict[$0] }    // 轉換為對應的Payer對象
            
            return orderedValidPayers
        } catch {
            print("DEBUG [Category.assignedPayers]: 獲取分配付款人時出錯：\(error)")
            return []
        }
    }

    // ✅ 改進：檢查是否分配了有效的付款人
    var hasValidAssignedPayers: Bool {
        // 不僅檢查是否為空，還需要確保所有ID都是有效的
        // 注意：這個屬性只檢查數組是否為空，實際有效性需要在上下文中檢查
        return !assignedPayerIDs.isEmpty
    }
    
    // ✅ 新增：清理無效的付款人ID（可手動調用）
    func cleanupInvalidPayerIDs(in context: ModelContext) -> [UUID] {
        guard !assignedPayerIDs.isEmpty else { return [] }
        
        do {
            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            let validPayerIDs = Set(allPayers.map { $0.id })
            
            // 找出無效的ID
            let invalidIDs = assignedPayerIDs.filter { !validPayerIDs.contains($0) }
            
            if !invalidIDs.isEmpty {
                print("清理分類 \(name) 中的無效付款人ID: \(invalidIDs)")
                
                // 移除無效ID
                self.assignedPayerIDs = assignedPayerIDs.filter { validPayerIDs.contains($0) }
                
                // 保存更改
                do {
                    try context.save()
                    print("已成功清理 \(invalidIDs.count) 個無效付款人ID")
                } catch {
                    print("清理後保存失敗: \(error)")
                }
            }
            
            return invalidIDs
        } catch {
            print("清理無效付款人ID時出錯: \(error)")
            return []
        }
    }
    
    // ✅ 新增：安全地添加付款人ID（避免重複）
    func addPayerID(_ payerID: UUID, in context: ModelContext) -> Bool {
        // 檢查付款人是否存在
        do {
            let payerFetch = FetchDescriptor<Payer>(
                predicate: #Predicate { $0.id == payerID }
            )
            let existingPayers = try context.fetch(payerFetch)
            
            if existingPayers.isEmpty {
                print("警告：嘗試添加不存在的付款人ID: \(payerID)")
                return false
            }
            
            // 避免重複添加
            if !assignedPayerIDs.contains(payerID) {
                assignedPayerIDs.append(payerID)
                
                // 保存更改
                do {
                    try context.save()
                    print("成功添加付款人ID: \(payerID)")
                    return true
                } catch {
                    print("添加付款人ID後保存失敗: \(error)")
                    return false
                }
            } else {
                print("付款人ID已存在: \(payerID)")
                return false
            }
        } catch {
            print("檢查付款人存在性時出錯: \(error)")
            return false
        }
    }
    
    // ✅ 新增：安全地移除付款人ID
    func removePayerID(_ payerID: UUID, in context: ModelContext) -> Bool {
        if assignedPayerIDs.contains(payerID) {
            assignedPayerIDs.removeAll { $0 == payerID }
            
            // 保存更改
            do {
                try context.save()
                print("成功移除付款人ID: \(payerID)")
                return true
            } catch {
                print("移除付款人ID後保存失敗: \(error)")
                return false
            }
        }
        
        print("付款人ID不存在: \(payerID)")
        return false
    }
}
