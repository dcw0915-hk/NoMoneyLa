//
//  LanguageManager.swift
//  NoMoneyLa
//
//  Created by Ricky Ding on 16/1/2026.
//

// LanguageManager.swift
import SwiftUI
import Combine

@MainActor
final class LanguageManager: ObservableObject {
    @Published var selectedLanguage: AppLanguage {
        didSet {
            loadBundle(for: selectedLanguage)
            UserDefaults.standard.set(selectedLanguage.rawValue, forKey: Self.userDefaultsKey)
        }
    }

    @Published private(set) var bundle: Bundle = .main   // 改成 @Published

    private static let userDefaultsKey = "selectedLanguage"

    init() {
        if let raw = UserDefaults.standard.string(forKey: Self.userDefaultsKey),
           let saved = AppLanguage(rawValue: raw) {
            selectedLanguage = saved
        } else {
            selectedLanguage = .english
        }
        loadBundle(for: selectedLanguage)
    }

    func localized(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func loadBundle(for lang: AppLanguage) {
        if let path = Bundle.main.path(forResource: lang.rawValue, ofType: "lproj"),
           let b = Bundle(path: path) {
            bundle = b
        } else {
            bundle = .main
        }
    }
}
