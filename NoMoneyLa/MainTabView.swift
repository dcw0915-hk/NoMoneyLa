//
//  MainTabView.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 16/1/2026.
//

import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Category.order) private var categories: [Category]
    
    var body: some View {
        TabView {
            NavigationStack {
                TransactionListView()
            }
            .tabItem {
                Label("Transactions", systemImage: "list.bullet")
            }

            NavigationStack {
                ContentView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "house")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
            
            // 測試頁面（開發完成後可移除）
            NavigationStack {
                if let firstCategory = categories.first {
                    CategorySettlementView(category: firstCategory)
                } else {
                    VStack {
                        Spacer()
                        Text("請先建立分類")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("在「分類管理」中新增分類後，即可使用結算功能")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        Spacer()
                    }
                }
            }
            .tabItem {
                Label("結算測試", systemImage: "dollarsign.circle")
            }
        }
    }
}
