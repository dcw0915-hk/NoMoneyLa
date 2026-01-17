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
        // 傳入 variadic 型別（不要用陣列）
        container = try! ModelContainer(for: Transaction.self, Category.self)

        // 初始化 category order（確保 order 連續）
        let ctx = container.mainContext
        do {
            let allCats = try ctx.fetch(FetchDescriptor<Category>())
            let grouped = Dictionary(grouping: allCats, by: { $0.parentID })
            for (_, group) in grouped {
                let sorted = group.sorted { $0.order < $1.order }
                for (idx, cat) in sorted.enumerated() { cat.order = idx }
            }
            try ctx.save()
        } catch {
            print("初始化 Category order 時發生錯誤：", error)
        }
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
}
