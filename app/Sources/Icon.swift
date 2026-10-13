// App icon, drawn in SwiftUI and rendered to PNG at install time.
import AppKit
import SwiftUI

// MARK: - App icon

struct IconView: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 230, style: .continuous)
                .fill(LinearGradient(colors: [Color(red: 0.13, green: 0.15, blue: 0.20), Color(red: 0.04, green: 0.05, blue: 0.07)],
                                     startPoint: .top, endPoint: .bottom))
                .padding(100)
            ForEach(Array([(T.green, 0.72, 300.0), (T.amber, 0.55, 210.0), (T.red, 0.88, 120.0)].enumerated()), id: \.offset) { _, r in
                ZStack {
                    Circle().stroke(r.0.opacity(0.16), lineWidth: 62)
                    Circle().trim(from: 0, to: r.1).stroke(r.0, style: StrokeStyle(lineWidth: 62, lineCap: .round))
                        .rotationEffect(.degrees(-90)).shadow(color: r.0.opacity(0.6), radius: 18)
                }.frame(width: r.2 * 2, height: r.2 * 2)
            }
        }
        .frame(width: 1024, height: 1024)
    }
}
