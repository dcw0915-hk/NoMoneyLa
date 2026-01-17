//
//  MainTabView.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 16/1/2026.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            NavigationStack {
                ContentView()
            }
            .tabItem {
                Label("Dashboard", systemImage: "house")
            }

            NavigationStack {
                TransactionListView()
            }
            .tabItem {
                Label("Transactions", systemImage: "list.bullet")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
    }
}
