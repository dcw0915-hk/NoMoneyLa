import SwiftUI
import SwiftData

@main
struct NoMoneyLaApp: App {
    @StateObject private var langManager = LanguageManager()
    let container: ModelContainer
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    init() {
        // 加入 Payer 和 PaymentContribution 模型
        container = try! ModelContainer(
            for: Transaction.self,
            Category.self,
            Subcategory.self,
            Payer.self,
            PaymentContribution.self
        )
        
        let ctx = container.mainContext
        performOneTimeMigrationIfNeeded(ctx)
        initializeOrders(in: ctx)
        createDefaultPayerIfNeeded(in: ctx)
        createUncategorizedSubcategoriesIfNeeded(in: ctx)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(container)
                .environmentObject(langManager)
                .preferredColorScheme(resolveColorScheme(appColorScheme))
        }
    }

    private func resolveColorScheme(_ value: String) -> ColorScheme? {
        switch value {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    private func initializeOrders(in context: ModelContext) {
        do {
            let allCategories = try context.fetch(FetchDescriptor<Category>())
            let sortedParents = allCategories.sorted(by: { $0.order < $1.order })
            for (idx, cat) in sortedParents.enumerated() {
                cat.order = idx
            }

            let allSubcategories = try context.fetch(FetchDescriptor<Subcategory>())
            let grouped = Dictionary(grouping: allSubcategories, by: { $0.parentID })
            for (_, group) in grouped {
                let sorted = group.sorted(by: {
                    if $0.name == "未分類" && $1.name != "未分類" {
                        return true
                    } else if $0.name != "未分類" && $1.name == "未分類" {
                        return false
                    } else {
                        return $0.order < $1.order
                    }
                })
                for (idx, sub) in sorted.enumerated() {
                    sub.order = idx
                }
            }
            
            let allPayers = try context.fetch(FetchDescriptor<Payer>())
            let sortedPayers = allPayers.sorted(by: { $0.order < $1.order })
            for (idx, payer) in sortedPayers.enumerated() {
                payer.order = idx
            }

            try context.save()
        } catch {
            print("初始化排序時發生錯誤：", error)
        }
    }

    private func createDefaultPayerIfNeeded(in context: ModelContext) {
        do {
            let payerFetch = FetchDescriptor<Payer>()
            let existingPayers = try context.fetch(payerFetch)
            
            if existingPayers.isEmpty {
                let defaultPayer = Payer(name: "自己", order: 0, isDefault: true, colorHex: "#3498db")
                context.insert(defaultPayer)
                try context.save()
            }
        } catch {
            print("建立預設付款人時發生錯誤：", error)
        }
    }

    private func performOneTimeMigrationIfNeeded(_ context: ModelContext) {
        let migratedKey = "didMigrateToMultiPayer_v1"
        let alreadyMigrated = UserDefaults.standard.bool(forKey: migratedKey)
        guard !alreadyMigrated else { return }
        
        do {
            let oldTransactions = try context.fetch(FetchDescriptor<Transaction>())
            let oldPayers = try context.fetch(FetchDescriptor<Payer>())
            
            for transaction in oldTransactions {
                if transaction.contributions.isEmpty {
                    if let defaultPayer = oldPayers.first(where: { $0.isDefault }) {
                        let contribution = PaymentContribution(
                            amount: transaction.totalAmount,
                            payer: defaultPayer,
                            transaction: transaction
                        )
                        context.insert(contribution)
                        transaction.contributions.append(contribution)
                    } else if !oldPayers.isEmpty {
                        let contribution = PaymentContribution(
                            amount: transaction.totalAmount,
                            payer: oldPayers[0],
                            transaction: transaction
                        )
                        context.insert(contribution)
                        transaction.contributions.append(contribution)
                    }
                }
            }
            
            try context.save()
            UserDefaults.standard.set(true, forKey: migratedKey)
        } catch {
            print("遷移到多付款人時發生錯誤：", error)
        }
    }

    private func createUncategorizedSubcategoriesIfNeeded(in context: ModelContext) {
        do {
            let categories = try context.fetch(FetchDescriptor<Category>())
            let allSubcategories = try context.fetch(FetchDescriptor<Subcategory>())
            
            for category in categories {
                let hasUncategorized = allSubcategories.contains {
                    $0.parentID == category.id && $0.name == "未分類"
                }
                
                if !hasUncategorized {
                    let uncategorized = Subcategory(
                        name: "未分類",
                        parentID: category.id,
                        order: -1,
                        colorHex: "#A8A8A8"
                    )
                    context.insert(uncategorized)
                }
            }
            
            try context.save()
        } catch {
            print("建立未分類子分類時發生錯誤：", error)
        }
    }
}
