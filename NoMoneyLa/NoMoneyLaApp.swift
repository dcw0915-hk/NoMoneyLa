//
//  NoMoneyLaApp.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 16/1/2026.
//

import SwiftUI
import SwiftData

@main
struct NoMoneyLaApp: App {
    @StateObject private var langManager = LanguageManager()
    let container: ModelContainer

    // 從 AppStorage 讀取使用者選擇的顏色模式
    @AppStorage("appColorScheme") private var appColorScheme: String = "system"

    init() {
        // 建立 ModelContainer，包含三個 model（Transaction, Category, Subcategory）
        container = try! ModelContainer(for: Transaction.self, Category.self, Subcategory.self)

        // 取得 mainContext 進行一次性初始化與遷移（若需要）
        let ctx = container.mainContext

        // 先嘗試執行一次性遷移（此函式內含說明與安全檢查）
        performOneTimeMigrationIfNeeded(ctx)

        // 初始化 category / subcategory order（確保 order 連續）
        initializeOrders(in: ctx)
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .modelContainer(container)
                .environmentObject(langManager)
                .preferredColorScheme(resolveColorScheme(appColorScheme)) // 套用顏色模式
        }
    }

    private func resolveColorScheme(_ value: String) -> ColorScheme? {
        switch value {
        case "light": return .light
        case "dark": return .dark
        default: return nil // 跟隨系統
        }
    }

    // MARK: - 初始化排序
    /// 確保父分類與子分類的 order 欄位是連續的（0..n-1）
    private func initializeOrders(in context: ModelContext) {
        do {
            // 父分類排序
            let allCategories = try context.fetch(FetchDescriptor<Category>())
            let sortedParents = allCategories.sorted(by: { $0.order < $1.order })
            for (idx, cat) in sortedParents.enumerated() {
                cat.order = idx
            }

            // 子分類排序：依 parentID 分組後各自排序
            let allSubcategories = try context.fetch(FetchDescriptor<Subcategory>())
            let grouped = Dictionary(grouping: allSubcategories, by: { $0.parentID })
            for (_, group) in grouped {
                let sorted = group.sorted(by: { $0.order < $1.order })
                for (idx, sub) in sorted.enumerated() {
                    sub.order = idx
                }
            }

            try context.save()
        } catch {
            print("初始化排序時發生錯誤：", error)
        }
    }

    // MARK: - 一次性遷移入口（請在備份資料後執行）
    /// 如果你的舊 schema 使用單一 Category model 並以 parentID 表示子分類，
    /// 你需要把那些原本 parentID != nil 的 Category 轉成 Subcategory。
    ///
    /// 這個函式提供一個安全的入口與旗標，實際遷移邏輯請依你的資料狀態實作並在測試環境驗證。
    private func performOneTimeMigrationIfNeeded(_ context: ModelContext) {
        // 使用 UserDefaults 或其他旗標避免重複遷移
        let migratedKey = "didMigrateCategoryToSubcategory_v1"
        let alreadyMigrated = UserDefaults.standard.bool(forKey: migratedKey)
        guard !alreadyMigrated else { return }

        // --- 注意事項（請在執行前閱讀） ---
        // 1) 在執行任何遷移前，務必備份使用者資料（例如備份 persistent store）。
        // 2) 根據你目前的資料庫狀態，遷移策略會不同：
        //    - 若舊資料庫中 Category 有 parentID 欄位（表示子分類），
        //      你可以把這些有 parentID 的 Category 轉成 Subcategory（保留原 id 或建立新 id）。
        //    - 若你已經手動修改 model 並移除 parentID，某些欄位可能無法直接存取；在這種情況下，請先在測試環境做完整遷移流程。
        // 3) 下面範例為「概念性」遷移範本，請根據實際情況修改與測試。

        do {
            // 嘗試讀取所有 Category（舊資料或新資料都會回傳）
            let allCats = try context.fetch(FetchDescriptor<Category>())

            // 如果沒有任何 Subcategory，且存在可能為「子分類」的 Category（依你自己的判斷條件）
            let existingSubs = try context.fetch(FetchDescriptor<Subcategory>())
            if existingSubs.isEmpty {
                // 範例策略（概念）：
                // 假設舊版 Category 有一個自訂欄位 parentID（但在新 model 中已移除），
                // 你可能需要在遷移前的版本中先匯出資料或在舊版 App 中執行遷移腳本。
                //
                // 這裡我們不會嘗試直接讀取不存在的欄位；相反地，我把遷移步驟留給你實作：
                //
                // - 如果你能在舊版 App 中先把 parentID != nil 的項目匯出成 JSON（包含 id, name, parentID, order, colorHex），
                //   則在新版 App 啟動時讀取該 JSON 並建立 Subcategory 實例。
                //
                // - 或者，如果你的 persistent store 還保有 parentID 欄位（但 model 已改），
                //   你需要使用更低階的遷移工具或在舊版 App 中先執行遷移。
                //
                // 因為 SwiftData 的 schema 變更與遷移情況較複雜，這裡僅提供安全入口與旗標機制。
                //
                // 若你需要，我可以幫你產生一個「匯出舊 Category 為 JSON」的程式碼片段，或產生「從 JSON 建立 Subcategory」的範例。
                //
                // 目前我們只把 migratedKey 設為 true，避免重複嘗試（你可以在實作遷移後再把這行移除或改為在遷移成功後才設 true）。
            }

            // 若你決定在此處執行遷移，請在成功後呼叫：
            // UserDefaults.standard.set(true, forKey: migratedKey)

        } catch {
            print("遷移檢查時發生錯誤：", error)
            // 不要設置 migratedKey，讓你可以在修正後重試
        }
    }
}
