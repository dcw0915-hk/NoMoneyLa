import SwiftUI

// MARK: - Color extension (hex -> Color)

extension Color {
    /// 初始化 Color 從 hex 字串（支援 "RGB", "RRGGBB", "AARRGGBB"）
    init(hex: String) {
        let hexStr = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hexStr).scanHexInt64(&int)

        let r, g, b, a: UInt64
        switch hexStr.count {
        case 3:
            // "RGB" -> expand to "RRGGBB"
            (r, g, b, a) = ((int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17, 255)
        case 6:
            (r, g, b, a) = (int >> 16, int >> 8 & 0xFF, int & 0xFF, 255)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            // 解析失敗時回傳灰色（避免黑色或 nil）
            (r, g, b, a) = (160, 160, 160, 255)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255.0,
            green: Double(g) / 255.0,
            blue: Double(b) / 255.0,
            opacity: Double(a) / 255.0
        )
    }

    /// Convert Color to hex string "#RRGGBB". Returns nil if conversion fails.
    func toHex() -> String? {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        guard ui.getRed(&r, green: &g, blue: &b, alpha: &a) else { return nil }
        #else
        let ns = NSColor(self)
        guard let rgb = ns.usingColorSpace(.deviceRGB) else { return nil }
        let r = rgb.redComponent, g = rgb.greenComponent, b = rgb.blueComponent
        #endif
        let ri = Int(round(Double(r) * 255))
        let gi = Int(round(Double(g) * 255))
        let bi = Int(round(Double(b) * 255))
        return String(format: "#%02X%02X%02X", ri, gi, bi)
    }
}

