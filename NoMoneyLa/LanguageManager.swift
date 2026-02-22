import SwiftUI
import Combine
import WidgetKit   // 加入呢行

let appGroupID = "group.Ricky.NoMoneyLa"

@MainActor
final class LanguageManager: ObservableObject {
    @Published var selectedLanguage: AppLanguage {
        didSet {
            loadBundle(for: selectedLanguage)
            // 儲存到共享 UserDefaults
            UserDefaults(suiteName: appGroupID)?.set(selectedLanguage.rawValue, forKey: Self.userDefaultsKey)
            // 強制刷新所有 widget
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published private(set) var bundle: Bundle = .main

    private static let userDefaultsKey = "selectedLanguage"

    init() {
        // 從共享 UserDefaults 讀取
        if let raw = UserDefaults(suiteName: appGroupID)?.string(forKey: Self.userDefaultsKey),
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
