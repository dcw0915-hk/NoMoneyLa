import SwiftUI
import SwiftData

@main
struct NoMoneyLaApp: App {
    @StateObject private var langManager = LanguageManager()
    @StateObject private var dashboardVM: DashboardViewModel
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
        
        // 初始化 DashboardViewModel
        _dashboardVM = StateObject(wrappedValue: DashboardViewModel(context: ctx))
        
        performOneTimeMigrationIfNeeded(ctx)
        createDefaultCategoryIfNeeded(in: ctx)
        initializeOrders(in: ctx)
        createDefaultPayerIfNeeded(in: ctx)
        createUncategorizedSubcategoriesIfNeeded(in: ctx)
        
        // ✅ 新增：遷移 subcategoryID 為 nil 的交易到預設未分類
        migrateNilSubcategoriesToUncategorized(in: ctx)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(container)
                .environmentObject(langManager)
                .environmentObject(dashboardVM)
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

    private func createDefaultCategoryIfNeeded(in context: ModelContext) {
        do {
            let categoryFetch = FetchDescriptor<Category>()
            let existingCategories = try context.fetch(categoryFetch)
            
            // 檢查係咪已經有預設「未分類」分類
            let hasDefault = existingCategories.contains { $0.name == "未分類" && $0.isDefault }
            
            if !hasDefault {
                // 建立預設「未分類」主分類
                let defaultCategory = Category(
                    name: "未分類",
                    order: -1,  // 排最前
                    colorHex: "#A8A8A8",
                    isDefault: true  // 標記為預設
                )
                context.insert(defaultCategory)
                
                // 建立對應嘅「未分類」子分類
                let defaultSubcategory = Subcategory(
                    name: "未分類",
                    parentID: defaultCategory.id,
                    order: -1,
                    colorHex: "#A8A8A8"
                )
                context.insert(defaultSubcategory)
                
                try context.save()
                print("已建立預設未分類分類")
            }
        } catch {
            print("建立預設分類時出錯：\(error)")
        }
    }

    private func initializeOrders(in context: ModelContext) {
        do {
            let allCategories = try context.fetch(FetchDescriptor<Category>())
            
            // 確保預設分類 order = -1（排最前）
            if let defaultCat = allCategories.first(where: { $0.isDefault }) {
                defaultCat.order = -1
            }
            
            // 其他分類重新排序
            let sortedParents = allCategories
                .filter { !$0.isDefault }
                .sorted(by: { $0.order < $1.order })
            
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
                // 跳過預設分類，因為已經建立咗
                if category.isDefault { continue }
                
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
    
    // ✅ 新增：遷移 subcategoryID 為 nil 的交易到預設未分類
    private func migrateNilSubcategoriesToUncategorized(in context: ModelContext) {
        let migratedKey = "didMigrateNilSubcategoriesToUncategorized"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }
        
        do {
            // 1. 獲取預設分類
            let defaultCategoryFetch = FetchDescriptor<Category>(
                predicate: #Predicate { $0.isDefault == true }
            )
            guard let defaultCategory = try context.fetch(defaultCategoryFetch).first else {
                print("找不到預設分類")
                return
            }
            
            // 2. 獲取預設分類嘅「未分類」子分類
            let subcategoryFetch = FetchDescriptor<Subcategory>()
            let allSubcategories = try context.fetch(subcategoryFetch)
            guard let defaultUncategorizedSub = allSubcategories.first(where: {
                $0.parentID == defaultCategory.id && $0.name == "未分類"
            }) else {
                print("找不到預設未分類子分類")
                return
            }
            
            // 3. 獲取所有 subcategoryID 為 nil 嘅交易
            let transactionFetch = FetchDescriptor<Transaction>()
            let allTransactions = try context.fetch(transactionFetch)
            let nilSubcategoryTransactions = allTransactions.filter { $0.subcategoryID == nil }
            
            // 4. 更新為預設「未分類」子分類
            for transaction in nilSubcategoryTransactions {
                transaction.subcategoryID = defaultUncategorizedSub.id
            }
            
            // 5. 保存並標記已遷移
            if !nilSubcategoryTransactions.isEmpty {
                try context.save()
                print("已遷移 \(nilSubcategoryTransactions.count) 筆交易到預設未分類")
            }
            
            UserDefaults.standard.set(true, forKey: migratedKey)
            
        } catch {
            print("遷移 subcategoryID 為 nil 的交易時出錯：\(error)")
        }
    }
}
