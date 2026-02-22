// Category.swift
import SwiftData
import Foundation

@Model
final class Category {
    var id: UUID = UUID()
    var name: String
    var order: Int = 0
    var colorHex: String?
    var isDefault: Bool = false
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
            return []
        }
    }

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
            return 0
        }
    }

    func assignedPayers(in context: ModelContext) -> [Payer] {
        guard !assignedPayerIDs.isEmpty else {
            return []
        }
        
        do {
            let uniqueIDs = Array(Set(assignedPayerIDs))
            
            if uniqueIDs.count != assignedPayerIDs.count {
                self.assignedPayerIDs = uniqueIDs
            }
            
            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            let payerDict = Dictionary(uniqueKeysWithValues: allPayers.map { ($0.id, $0) })
            
            var validPayers: [Payer] = []
            var invalidIDs: [UUID] = []
            
            for payerID in uniqueIDs {
                if let payer = payerDict[payerID] {
                    validPayers.append(payer)
                } else {
                    invalidIDs.append(payerID)
                }
            }
            
            if !invalidIDs.isEmpty {
                self.assignedPayerIDs = uniqueIDs.filter { !invalidIDs.contains($0) }
                
                do {
                    try context.save()
                } catch {
                }
            }
            
            let orderedValidPayers = uniqueIDs
                .filter { payerDict[$0] != nil }
                .compactMap { payerDict[$0] }
            
            return orderedValidPayers
        } catch {
            return []
        }
    }

    var hasValidAssignedPayers: Bool {
        return !assignedPayerIDs.isEmpty
    }
    
    func cleanupInvalidPayerIDs(in context: ModelContext) -> [UUID] {
        guard !assignedPayerIDs.isEmpty else { return [] }
        
        do {
            let payersFetch = FetchDescriptor<Payer>()
            let allPayers = try context.fetch(payersFetch)
            let validPayerIDs = Set(allPayers.map { $0.id })
            
            let invalidIDs = assignedPayerIDs.filter { !validPayerIDs.contains($0) }
            
            if !invalidIDs.isEmpty {
                self.assignedPayerIDs = assignedPayerIDs.filter { validPayerIDs.contains($0) }
                
                do {
                    try context.save()
                } catch {
                }
            }
            
            return invalidIDs
        } catch {
            return []
        }
    }
    
    func addPayerID(_ payerID: UUID, in context: ModelContext) -> Bool {
        do {
            let payerFetch = FetchDescriptor<Payer>(
                predicate: #Predicate { $0.id == payerID }
            )
            let existingPayers = try context.fetch(payerFetch)
            
            if existingPayers.isEmpty {
                return false
            }
            
            if !assignedPayerIDs.contains(payerID) {
                assignedPayerIDs.append(payerID)
                
                do {
                    try context.save()
                    return true
                } catch {
                    return false
                }
            } else {
                return false
            }
        } catch {
            return false
        }
    }
    
    func removePayerID(_ payerID: UUID, in context: ModelContext) -> Bool {
        if assignedPayerIDs.contains(payerID) {
            assignedPayerIDs.removeAll { $0 == payerID }
            
            do {
                try context.save()
                return true
            } catch {
                return false
            }
        }
        
        return false
    }
}
