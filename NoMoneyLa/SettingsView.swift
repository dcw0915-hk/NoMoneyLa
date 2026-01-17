//
//  SettingsView.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 16/1/2026.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var langManager: LanguageManager
    @State private var selectedLanguageRaw: String = AppLanguage.english.rawValue
    
    @AppStorage("appColorScheme") private var appColorScheme: String = "system" // system / light / dark
    
    var body: some View {
        NavigationStack {
            List {
                // 外觀設定（第一列）
                Section(langManager.localized("settings_appearance_section")) {
                    Picker(langManager.localized("settings_appearance_label"), selection: $appColorScheme) {
                        Text(langManager.localized("settings_appearance_system")).tag("system")
                        Text(langManager.localized("settings_appearance_light")).tag("light")
                        Text(langManager.localized("settings_appearance_dark")).tag("dark")
                    }
                    .pickerStyle(.segmented)
                }
                
                // 語言設定（第二列，移除套用按鈕）
                Section(langManager.localized("settings_language_section")) {
                    Picker(langManager.localized("settings_language_label"), selection: $selectedLanguageRaw) {
                        ForEach(AppLanguage.allCases, id: \.rawValue) { lang in
                            Text(displayName(for: lang)).tag(lang.rawValue)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedLanguageRaw) { newValue in
                        applyLanguage(raw: newValue)
                    }
                }
                
                // 管理分類（第三列）
                Section {
                    NavigationLink(destination: CategoryListView()) {
                        Label(langManager.localized("settings_manage_categories"), systemImage: "folder")
                    }
                }
            }
            .navigationTitle(langManager.localized("settings_title"))
            .onAppear {
                selectedLanguageRaw = langManager.selectedLanguage.rawValue
            }
        }
    }
    
    private func applyLanguage(raw: String) {
        guard let lang = AppLanguage(rawValue: raw) else { return }
        langManager.selectedLanguage = lang
    }
    
    private func displayName(for lang: AppLanguage) -> String {
        switch lang {
        case .english: return "English"
        case .chineseHK: return "繁體中文（香港）"
        case .japanese: return "日本語"
        }
    }
}
