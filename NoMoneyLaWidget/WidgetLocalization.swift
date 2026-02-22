import Foundation

func widgetLocalizedString(_ key: String) -> String {
    let defaults = UserDefaults(suiteName: appGroupID)
    let languageRaw = defaults?.string(forKey: "selectedLanguage") ?? Locale.current.language.languageCode?.identifier ?? "en"
    
    let languageCode: String
    switch languageRaw {
    case "zh-HK", "zh-Hant-HK", "zh-Hant":
        languageCode = "zh-HK"
    case "ja":
        languageCode = "ja"
    default:
        languageCode = "en"
    }
    
    if let path = Bundle.main.path(forResource: languageCode, ofType: "lproj"),
       let bundle = Bundle(path: path) {
        return bundle.localizedString(forKey: key, value: nil, table: nil)
    }
    return Bundle.main.localizedString(forKey: key, value: nil, table: nil)
}
