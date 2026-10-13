// Data from the gpumon backend and the widget state.
import AppKit
import SwiftUI

let base = URL(string: "http://127.0.0.1:8765")!
let dashboard = URL(string: "http://localhost:8765")!
let panelWidth: CGFloat = 330

// MARK: - Data

struct Proc: Decodable, Identifiable {
    let pid: Int; let mem: Double?; let user: String; let elapsed: Int?; let cmd: String; let mine: Bool
    var id: Int { pid }
}
struct GPU: Decodable, Identifiable {
    let index: Int; let name: String; let util: Double?; let mem_used: Double?; let mem_total: Double?
    let temp: Double?; let power: Double?; let power_limit: Double?; let procs: [Proc]; let history: [[Double?]]?
    var id: Int { index }
    var utilFrac: Double { (util ?? 0) / 100 }
    var memFrac: Double { (mem_total ?? 0) > 0 ? (mem_used ?? 0) / mem_total! : 0 }
}
struct SysInfo: Decodable { let load: [Double]?; let cpus: Int?; let ram_total: Double?; let ram_avail: Double? }
struct Host: Decodable, Identifiable {
    let label: String; let target: String; let ok: Bool?; let error: String?; let gpus: [GPU]; let sys: SysInfo?
    var id: String { label }
}
struct Best: Decodable { let host: String; let gpu: Int; let free_mb: Double; let util: Double? }
struct Status: Decodable { let hosts: [Host]; let best: Best? }

enum PanelMode: String, CaseIterable, Identifiable {
    case desktop, normal, top
    var id: String { rawValue }
    var title: String { ["desktop": "On Desktop (widget)", "normal": "Normal Window", "top": "Always on Top"][rawValue]! }
}

enum PanelHeight: String, CaseIterable, Identifiable {
    case compact, medium, tall, screen
    var id: String { rawValue }
    var title: String { ["compact": "Compact", "medium": "Medium", "tall": "Tall", "screen": "Fit Screen"][rawValue]! }
    var points: CGFloat? { ["compact": 460, "medium": 640, "tall": 840][rawValue] }
}

final class Model: ObservableObject {
    @Published var settings = false
    @Published var room: CGFloat = 800   // space between the window's top edge and the bottom of the screen
    @Published var maxHeight: PanelHeight = PanelHeight(rawValue: UserDefaults.standard.string(forKey: "panelHeight") ?? "") ?? .medium {
        didSet { UserDefaults.standard.set(maxHeight.rawValue, forKey: "panelHeight") }
    }
    @Published var status: Status?
    @Published var offline = false
    @Published var updated: Date?
    @Published var mode: PanelMode = PanelMode(rawValue: UserDefaults.standard.string(forKey: "panelMode") ?? "") ?? .desktop {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "panelMode"); onMode?(mode) }
    }
    var onMode: ((PanelMode) -> Void)?
    var onHeight: ((CGFloat) -> Void)?

    func refresh() {
        URLSession.shared.dataTask(with: base.appendingPathComponent("api/status")) { data, _, _ in
            let s = data.flatMap { try? JSONDecoder().decode(Status.self, from: $0) }
            DispatchQueue.main.async {
                if let s { self.status = s; self.updated = Date() }
                self.offline = s == nil
            }
        }.resume()
    }

    func send(_ method: String, _ path: String, _ body: [String: String]? = nil, done: @escaping (String?) -> Void) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("1", forHTTPHeaderField: "X-GPUMon")
        if let body { req.httpBody = try? JSONSerialization.data(withJSONObject: body) }
        URLSession.shared.dataTask(with: req) { data, resp, err in
            let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let msg = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["error"] as? String
            DispatchQueue.main.async {
                done(code == 200 ? nil : (msg ?? err?.localizedDescription ?? "backend not reachable"))
                self.refresh()
            }
        }.resume()
    }
}
