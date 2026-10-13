// Formatting helpers and the color theme.
import AppKit
import SwiftUI

// MARK: - Formatting & theme

func gb(_ mb: Double?) -> String { String(format: "%.1f", (mb ?? 0) / 1024) }
func gb0(_ mb: Double?) -> String { String(format: "%.0f", (mb ?? 0) / 1024) }
func dur(_ s: Int?) -> String {
    guard let s else { return "" }
    let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
    return d > 0 ? "\(d)d \(h)h" : h > 0 ? "\(h)h \(m)m" : "\(m)m"
}
func shortCmd(_ c: String) -> String {
    var parts = c.split(separator: " ").map(String.init)
    if let first = parts.first { parts[0] = first.split(separator: "/").last.map(String.init) ?? first }
    return parts.joined(separator: " ")
}
func copyToClipboard(_ s: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(s, forType: .string)
}

enum T {
    static let bg = Color(red: 0.055, green: 0.063, blue: 0.082)
    static let card = Color.white.opacity(0.045)
    static let stroke = Color.white.opacity(0.08)
    static let text = Color.white.opacity(0.93)
    static let dim = Color.white.opacity(0.56)
    static let faint = Color.white.opacity(0.34)
    static let green = Color(red: 0.27, green: 0.86, blue: 0.56)
    static let amber = Color(red: 1.0, green: 0.73, blue: 0.27)
    static let red = Color(red: 1.0, green: 0.40, blue: 0.42)
    static let blue = Color(red: 0.42, green: 0.64, blue: 1.0)
    static func load(_ f: Double) -> Color { f >= 0.9 ? red : f >= 0.6 ? amber : green }
    // Distinct colors for other users; blue is reserved for "you".
    static let palette: [Color] = [
        Color(red: 0.93, green: 0.45, blue: 0.85), Color(red: 1.0, green: 0.80, blue: 0.35), Color(red: 0.35, green: 0.85, blue: 0.80),
        Color(red: 1.0, green: 0.55, blue: 0.40), Color(red: 0.70, green: 0.55, blue: 1.0), Color(red: 0.75, green: 0.92, blue: 0.40),
        Color(red: 1.0, green: 0.45, blue: 0.55), Color(red: 0.55, green: 0.90, blue: 0.55),
    ]
    static func user(_ name: String) -> Color {
        let h = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return palette[abs(h) % palette.count]
    }
}
