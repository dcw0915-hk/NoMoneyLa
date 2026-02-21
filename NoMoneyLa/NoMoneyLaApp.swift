import SwiftUI
import SwiftData
import WidgetKit

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

        // 遷移 subcategoryID 為 nil 的交易到預設未分類
        migrateNilSubcategoriesToUncategorized(in: ctx)

        // 遷移舊的未分類標記（基於名稱）
        migrateUncategorizedFlag(in: ctx)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(container)
                .environmentObject(langManager)
                .environmentObject(dashboardVM)
                .preferredColorScheme(resolveColorScheme(appColorScheme))
                .onOpenURL { url in
                    if url.scheme == "nomoneyla" {
                        // 處理導航（可選）
                    }
                }
        }
    }

    private func resolveColorScheme(_ value: String) -> ColorScheme? {
        switch value {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }

    // MARK: - 建立預設「未分類」主分類（使用內部名稱 "uncategorized"）
    private func createDefaultCategoryIfNeeded(in context: ModelContext) {
        do {
            let categoryFetch = FetchDescriptor<Category>()
            let existingCategories = try context.fetch(categoryFetch)

            // 檢查係咪已經有預設分類（任何 isDefault == true 嘅分類）
            let hasDefault = existingCategories.contains { $0.isDefault }

            if !hasDefault {
                // 建立預設主分類，使用內部名稱 "Uncategorized" (之後會根據語言更新顯示)
                let defaultCategory = Category(
                    name: "Uncategorized",  // 內部名稱
                    order: -1,
                    colorHex: "#A8A8A8",
                    isDefault: true
                )
                context.insert(defaultCategory)

                // 建立對應嘅預設未分類子分類，內部名稱同樣用 "uncategorized"
                let defaultSubcategory = Subcategory(
                    name: "uncategorized",
                    parentID: defaultCategory.id,
                    order: -1,
                    colorHex: "#A8A8A8",
                    isUncategorized: true
                )
                context.insert(defaultSubcategory)

                try context.save()
                print("已建立預設未分類分類 (內部名稱)")
            }
        } catch {
            print("建立預設分類時出錯：\(error)")
        }
    }

    // MARK: - 建立預設付款人
    private func createDefaultPayerIfNeeded(in context: ModelContext) {
        do {
            let payerFetch = FetchDescriptor<Payer>()
            let existingPayers = try context.fetch(payerFetch)

            if existingPayers.isEmpty {
                // 建立預設付款人，使用內部名稱 "Myself"
                let defaultPayer = Payer(
                    name: "Myself",
                    order: 0,
                    isDefault: true,
                    colorHex: "#3498db"
                )
                context.insert(defaultPayer)
                try context.save()
                print("已建立預設付款人 (內部名稱)")
            }
        } catch {
            print("建立預設付款人時發生錯誤：", error)
        }
    }

    // MARK: - 為每個非預設分類建立一個「未分類」子分類（內部名稱 "uncategorized"）
    private func createUncategorizedSubcategoriesIfNeeded(in context: ModelContext) {
        do {
            let categories = try context.fetch(FetchDescriptor<Category>())
            let allSubcategories = try context.fetch(FetchDescriptor<Subcategory>())

            for category in categories {
                // 跳過預設分類，因為已經建立咗
                if category.isDefault { continue }

                let hasUncategorized = allSubcategories.contains {
                    $0.parentID == category.id && $0.isUncategorized
                }

                if !hasUncategorized {
                    let uncategorized = Subcategory(
                        name: "uncategorized",   // 內部名稱
                        parentID: category.id,
                        order: -1,
                        colorHex: "#A8A8A8",
                        isUncategorized: true
                    )
                    context.insert(uncategorized)
                }
            }

            try context.save()
        } catch {
            print("建立未分類子分類時發生錯誤：", error)
        }
    }

    // MARK: - 初始化排序
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
                    if $0.isUncategorized && !$1.isUncategorized {
                        return true
                    } else if !$0.isUncategorized && $1.isUncategorized {
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

    // MARK: - 一次性遷移（舊交易轉為多付款人結構）
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

    // MARK: - 遷移 subcategoryID 為 nil 的交易到預設未分類
    private func migrateNilSubcategoriesToUncategorized(in context: ModelContext) {
        let migratedKey = "didMigrateNilSubcategoriesToUncategorized"
        guard !UserDefaults.standard.bool(forKey: migratedKey) else { return }

        do {
            // 1. 獲取預設分類（isDefault == true）
            let defaultCategoryFetch = FetchDescriptor<Category>(
                predicate: #Predicate { $0.isDefault == true }
            )
            guard let defaultCategory = try context.fetch(defaultCategoryFetch).first else {
                print("找不到預設分類")
                return
            }

            // 2. 獲取預設分類嘅第一個 isUncategorized == true 子分類
            let targetParentID = defaultCategory.id
            let subcategoryFetch = FetchDescriptor<Subcategory>(
                predicate: #Predicate { $0.parentID == targetParentID && $0.isUncategorized == true }
            )
            let defaultSubs = try context.fetch(subcategoryFetch)
            guard let defaultUncategorizedSub = defaultSubs.first else {
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

    // MARK: - 遷移舊的未分類標記（基於名稱）
    private func migrateUncategorizedFlag(in context: ModelContext) {
        let key = "didMigrateUncategorizedFlag"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        do {
            let subcategories = try context.fetch(FetchDescriptor<Subcategory>())
            // 所有可能嘅未分類名稱（支援英文、繁體中文、日文）
            let possibleNames = ["Uncategorized", "未分類", "未分類"]
            for sub in subcategories where possibleNames.contains(sub.name) {
                sub.isUncategorized = true
                // 統一內部名稱
                sub.name = "uncategorized"
            }
            try context.save()
            UserDefaults.standard.set(true, forKey: key)
            print("已遷移未分類標記")
        } catch {
            print("遷移未分類標記失敗：\(error)")
        }
    }
}
