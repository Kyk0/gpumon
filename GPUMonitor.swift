// GPU Monitor: desktop widget for gpumon.py: a glass panel with every server's GPUs, VRAM and processes.
// Run with `--snapshot out.png` to render the panel to an image, `--icon out.png` to render the app icon.
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

final class Model: ObservableObject {
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

// MARK: - Components

struct Meter: View {
    let frac: Double; var color: Color
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(color).frame(width: max(3, g.size.width * min(1, frac)))
            }
        }
        .frame(height: 3)
        .animation(.easeOut(duration: 0.5), value: frac)
    }
}

struct IconButton: View {
    let icon: String; let action: () -> Void
    @State private var hover = false
    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10, weight: .semibold))
                .foregroundColor(hover ? T.text : T.faint)
                .frame(width: 18, height: 18)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

// MARK: - GPU card: ring + name, util/VRAM sparkline, per-user stacked VRAM bar, chips, legend, expandable process list

struct UserUse { let name: String; let mem: Double; let mine: Bool; let elapsed: Int? }

func userColor(_ u: UserUse) -> Color { u.mine ? T.blue : T.user(u.name) }
func tempColor(_ t: Double?) -> Color { (t ?? 0) >= 82 ? T.red : (t ?? 0) >= 72 ? T.amber : T.dim }

struct MiniRing: View {
    let frac: Double
    var body: some View {
        let c = T.load(frac)
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 4)
            Circle().trim(from: 0, to: max(0.003, min(1, frac)))
                .stroke(AngularGradient(colors: [c.opacity(0.55), c], center: .center, startAngle: .degrees(0), endAngle: .degrees(360 * max(0.01, frac))),
                        style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: c.opacity(0.6), radius: 3)
            Text("\(Text("\(Int((frac * 100).rounded()))").font(.system(size: 12.5, weight: .bold, design: .rounded)))\(Text("%").font(.system(size: 7, weight: .bold, design: .rounded)).foregroundColor(T.dim))")
                .foregroundColor(T.text).contentTransition(.numericText())
        }
        .frame(width: 40, height: 40)
        .animation(.easeOut(duration: 0.6), value: frac)
    }
}

struct Spark: View {
    let points: [[Double?]]; let color: Color; let total: Double
    func y(_ i: Int, _ k: Int) -> Double {
        let p = points[i]; let v = p.count > k ? (p[k] ?? 0) : 0
        return k == 1 ? v / 100 : (total > 0 ? v / total : 0)
    }
    func path(_ size: CGSize, _ k: Int, close: Bool) -> Path {
        var p = Path()
        let n = points.count
        for i in 0..<n {
            let pt = CGPoint(x: size.width * CGFloat(i) / CGFloat(max(1, n - 1)), y: (size.height - 2) * (1 - CGFloat(min(1, y(i, k)))) + 1)
            i == 0 ? p.move(to: pt) : p.addLine(to: pt)
        }
        if close { p.addLine(to: CGPoint(x: size.width, y: size.height)); p.addLine(to: CGPoint(x: 0, y: size.height)); p.closeSubpath() }
        return p
    }
    var span: String {
        let t0: Double = points.first.flatMap { $0.first ?? nil } ?? 0
        let t1: Double = points.last.flatMap { $0.first ?? nil } ?? 0
        return "\(max(1, Int(t1 - t0) / 60))m"
    }
    var body: some View {
        GeometryReader { g in
            if points.count > 1 {
                ZStack(alignment: .topTrailing) {
                    path(g.size, 1, close: true).fill(LinearGradient(colors: [color.opacity(0.28), color.opacity(0)], startPoint: .top, endPoint: .bottom))
                    path(g.size, 2, close: false).stroke(T.blue.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [2.5, 2]))
                    path(g.size, 1, close: false).stroke(color, style: StrokeStyle(lineWidth: 1.3, lineJoin: .round))
                }
            } else {
                Text("collecting history…").font(.system(size: 9)).foregroundColor(T.faint).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 24)
    }
}

struct StackedBar: View {
    let users: [UserUse]; let used: Double; let total: Double
    var body: some View {
        GeometryReader { g in
            let w = g.size.width
            let other = max(0, used - users.reduce(0) { $0 + $1.mem })
            HStack(spacing: 1.5) {
                ForEach(Array(users.enumerated()), id: \.offset) { _, u in
                    Rectangle().fill(LinearGradient(colors: [userColor(u).opacity(0.8), userColor(u)], startPoint: .top, endPoint: .bottom))
                        .frame(width: max(2, w * u.mem / max(1, total)))
                }
                if other > total * 0.005 { Rectangle().fill(Color.white.opacity(0.35)).frame(width: w * other / max(1, total)) }
                Spacer(minLength: 0)
            }
            .frame(width: w, height: 7, alignment: .leading)
            .background(Color.white.opacity(0.07))
            .clipShape(Capsule())
        }
        .frame(height: 7)
        .animation(.easeOut(duration: 0.5), value: used)
    }
}

struct Pill: View {
    let icon: String; let text: String; var color: Color = T.dim
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8, weight: .bold))
            Text(text)
        }
        .font(.system(size: 9.5, weight: .medium).monospacedDigit())
        .foregroundColor(color)
        .padding(.horizontal, 6).padding(.vertical, 2.5)
        .background(Capsule().fill(Color.white.opacity(0.06)))
        .fixedSize()
    }
}

struct GPURow: View {
    let h: Host; let g: GPU
    @ObservedObject var model: Model
    @State private var hover = false
    @State private var confirming = false
    @State private var expanded = false

    var users: [UserUse] {
        var order: [String] = [], mem: [String: Double] = [:], mine: [String: Bool] = [:], el: [String: Int] = [:]
        for p in g.procs {
            if mem[p.user] == nil { order.append(p.user) }
            mem[p.user, default: 0] += p.mem ?? 0
            mine[p.user] = p.mine
            el[p.user] = max(el[p.user] ?? 0, p.elapsed ?? 0)
        }
        return order.map { UserUse(name: $0, mem: mem[$0]!, mine: mine[$0]!, elapsed: el[$0]) }
    }

    var sysLine: String {
        guard let s = h.sys else { return "" }
        var parts: [String] = []
        if let l = s.load?.first, let c = s.cpus { parts.append("CPU \(Int(l / Double(c) * 100))%") }
        if let t = s.ram_total, let a = s.ram_avail { parts.append("RAM \(gb0(t - a))/\(gb0(t))G") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        let load = T.load(g.utilFrac)
        let us = users
        let free = (g.mem_total ?? 0) - (g.mem_used ?? 0)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MiniRing(frac: g.utilFrac)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 5) {
                        Text(h.label).font(.system(size: 13.5, weight: .semibold, design: .rounded)).foregroundColor(T.text)
                        Text(h.gpus.count > 1 ? "GPU \(g.index) · \(short(g.name))" : short(g.name))
                            .font(.system(size: 9.5, weight: .semibold)).foregroundColor(T.dim)
                            .padding(.horizontal, 5).padding(.vertical, 1.5)
                            .background(Capsule().fill(Color.white.opacity(0.07)))
                            .lineLimit(1)
                    }
                    Text(sysLine).font(.system(size: 9.5).monospacedDigit()).foregroundColor(T.faint).lineLimit(1)
                }
                Spacer(minLength: 2)
                if hover && g.index == h.gpus.first?.index {
                    Button {
                        if confirming { model.send("DELETE", "api/hosts/\(h.label)") { _ in } } else { confirming = true }
                    } label: {
                        Text(confirming ? "remove?" : "✕").font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(confirming ? T.red : T.faint)
                    }.buttonStyle(.plain).help("Remove server")
                }
                Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundColor(T.faint)
                    .rotationEffect(.degrees(expanded ? 180 : 0))
            }

            Spark(points: g.history ?? [], color: load, total: g.mem_total ?? 0)

            VStack(alignment: .leading, spacing: 4) {
                StackedBar(users: us, used: g.mem_used ?? 0, total: g.mem_total ?? 0)
                HStack(spacing: 0) {
                    Text("\(Text(gb(g.mem_used)).foregroundColor(T.text).fontWeight(.semibold)) / \(gb0(g.mem_total)) GB VRAM")
                    Spacer()
                    Text("\(gb0(free)) GB free").foregroundColor(free / max(1, g.mem_total ?? 1) > 0.3 ? T.green : T.faint)
                }
                .font(.system(size: 10).monospacedDigit()).foregroundColor(T.faint)
            }

            HStack(spacing: 5) {
                Pill(icon: "thermometer.medium", text: "\(Int(g.temp ?? 0))°C", color: tempColor(g.temp))
                Pill(icon: "bolt.fill", text: "\(Int(g.power ?? 0))/\(Int(g.power_limit ?? 0))W")
                Pill(icon: "square.stack.3d.up.fill", text: "\(g.procs.count) proc")
                Spacer(minLength: 0)
                Text("graph \(Spark(points: g.history ?? [], color: load, total: 0).span)").font(.system(size: 8.5)).foregroundColor(T.faint)
            }

            if us.isEmpty {
                Label("idle — free to use", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 10, weight: .medium)).foregroundColor(T.green)
            } else if expanded {
                VStack(spacing: 3) {
                    ForEach(g.procs) { p in
                        HStack(spacing: 6) {
                            Circle().fill(p.mine ? T.blue : T.user(p.user)).frame(width: 5, height: 5)
                            Text(p.mine ? "you" : p.user).foregroundColor(p.mine ? T.blue : T.text).frame(width: 58, alignment: .leading).lineLimit(1)
                            Text("\(gb(p.mem))G").foregroundColor(T.text).frame(width: 36, alignment: .trailing)
                            Text(dur(p.elapsed)).foregroundColor(T.faint).frame(width: 46, alignment: .trailing)
                            Text(shortCmd(p.cmd)).font(.system(size: 9, design: .monospaced)).foregroundColor(T.faint)
                                .lineLimit(1).truncationMode(.tail)
                            Spacer(minLength: 0)
                        }
                        .font(.system(size: 10).monospacedDigit())
                        .help(p.cmd)
                    }
                }
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.22)))
            } else {
                FlowLegend(users: us)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(LinearGradient(
            colors: [Color.white.opacity(hover ? 0.085 : 0.06), Color.white.opacity(hover ? 0.05 : 0.03)], startPoint: .top, endPoint: .bottom)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(
            LinearGradient(colors: [Color.white.opacity(0.13), Color.white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture { withAnimation(.spring(duration: 0.3)) { expanded.toggle() } }
        .onHover { hover = $0; if !$0 { confirming = false } }
    }

    func short(_ n: String) -> String {
        n.replacingOccurrences(of: "NVIDIA ", with: "").replacingOccurrences(of: "Quadro ", with: "")
    }
}

// Users as "● name 8G 2h", wrapping onto as many lines as needed.
struct FlowLegend: View {
    let users: [UserUse]
    var body: some View {
        FlowLayout(spacing: 10, lineSpacing: 3) {
            ForEach(Array(users.enumerated()), id: \.offset) { _, u in
                HStack(spacing: 4) {
                    Circle().fill(userColor(u)).frame(width: 5, height: 5)
                    Text(u.mine ? "you" : u.name).foregroundColor(u.mine ? T.blue : T.dim)
                        .fontWeight(u.mine ? .semibold : .regular)
                    Text("\(gb0(u.mem))G · \(dur(u.elapsed))").foregroundColor(T.faint)
                }
                .font(.system(size: 10).monospacedDigit())
                .fixedSize()
            }
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat; var lineSpacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > 0 && x + sz.width > w { x = 0; y += lineH + lineSpacing; lineH = 0 }
            x += sz.width + spacing; lineH = max(lineH, sz.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: proposal.width ?? maxX, height: y + lineH)
    }
    func placeSubviews(in b: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = b.minX, y = b.minY, lineH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x > b.minX && x + sz.width > b.maxX { x = b.minX; y += lineH + lineSpacing; lineH = 0 }
            s.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += sz.width + spacing; lineH = max(lineH, sz.height)
        }
    }
}

// MARK: - Cluster summary tiles

struct StatTile: View {
    let value: String; let label: String; var color: Color = T.text
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.system(size: 14, weight: .bold, design: .rounded).monospacedDigit()).foregroundColor(color)
                .contentTransition(.numericText()).lineLimit(1).minimumScaleFactor(0.7)
            Text(label).font(.system(size: 8.5, weight: .semibold)).foregroundColor(T.faint).tracking(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
    }
}

struct Summary: View {
    let s: Status
    var body: some View {
        let gs = s.hosts.flatMap(\.gpus)
        let util = gs.isEmpty ? 0 : gs.reduce(0) { $0 + ($1.util ?? 0) } / Double(gs.count)
        let used = gs.reduce(0) { $0 + ($1.mem_used ?? 0) }, total = gs.reduce(0) { $0 + ($1.mem_total ?? 0) }
        let idle = gs.filter { $0.procs.isEmpty }.count
        let mine = gs.flatMap(\.procs).filter(\.mine).count
        HStack(spacing: 6) {
            StatTile(value: "\(Int(util))%", label: "AVG LOAD", color: T.load(util / 100))
            StatTile(value: "\(gb0(total - used))G", label: "VRAM FREE", color: (total - used) / max(1, total) > 0.3 ? T.green : T.text)
            StatTile(value: "\(idle)/\(gs.count)", label: "IDLE GPUS", color: idle > 0 ? T.green : T.text)
            StatTile(value: "\(mine)", label: "YOUR JOBS", color: mine > 0 ? T.blue : T.text)
        }
    }
}

struct DownRow: View {
    let h: Host
    @ObservedObject var model: Model
    @State private var hover = false
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(h.ok == nil ? T.amber : T.red).frame(width: 6, height: 6)
            Text(h.label).font(.system(size: 12, weight: .semibold)).foregroundColor(T.text)
            Text(h.ok == nil ? "connecting…" : "offline").font(.system(size: 10)).foregroundColor(T.faint)
            Spacer()
            if hover {
                Button { model.send("DELETE", "api/hosts/\(h.label)") { _ in } } label: {
                    Text("remove").font(.system(size: 9.5, weight: .semibold)).foregroundColor(T.red)
                }.buttonStyle(.plain)
            }
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.stroke, lineWidth: 1))
        .onHover { hover = $0 }
        .help(h.error ?? "")
    }
}

// MARK: - Add server

struct AddServer: View {
    @ObservedObject var model: Model
    @Binding var shown: Bool
    @State private var label = ""
    @State private var target = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                TextField("name", text: $label).frame(width: 64)
                TextField("user@host", text: $target).onSubmit(add)
                IconButton(icon: "return", action: add)
            }
            .textFieldStyle(.plain)
            .font(.system(size: 11))
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
            if let error { Text(error).font(.system(size: 10)).foregroundColor(T.red) }
        }
        .padding(.bottom, 4)
    }

    func add() {
        guard !label.isEmpty, !target.isEmpty else { return }
        error = nil
        model.send("POST", "api/hosts", ["label": label.trimmingCharacters(in: .whitespaces),
                                         "target": target.trimmingCharacters(in: .whitespaces)]) { err in
            if let err { error = err } else { shown = false }
        }
    }
}

// MARK: - Panel

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct PanelContent: View {
    @ObservedObject var model: Model
    var snapshot = false
    @State private var adding = false
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("GPU Monitor").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(T.text)
                Circle().fill(model.offline ? T.red : T.green).frame(width: 5, height: 5)
                    .shadow(color: model.offline ? T.red : T.green, radius: 3)
                Text(model.offline ? "offline" : (model.updated.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "…"))
                    .font(.system(size: 9.5).monospacedDigit()).foregroundColor(model.offline ? T.red : T.faint)
                Spacer()
                if hover || adding || snapshot {
                    IconButton(icon: adding ? "xmark" : "plus") { adding.toggle() }.help("Add server")
                    if !snapshot {
                        Menu {
                            Picker("Position", selection: $model.mode) {
                                ForEach(PanelMode.allCases) { Text($0.title).tag($0) }
                            }
                            Divider()
                            Button("Open Web Dashboard") { NSWorkspace.shared.open(dashboard) }
                            Button("Quit GPU Monitor") { NSApp.terminate(nil) }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 10, weight: .semibold)).foregroundColor(T.faint)
                                .frame(width: 18, height: 18)
                        }
                        .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                    }
                }
            }
            .frame(height: 20)
            .padding(.bottom, 8)

            if adding { AddServer(model: model, shown: $adding) }

            if let s = model.status, !s.hosts.isEmpty { Summary(s: s).padding(.bottom, 8) }

            if let s = model.status {
                if s.hosts.isEmpty && !adding {
                    Button { adding = true } label: {
                        Text("+ add a server").font(.system(size: 11)).foregroundColor(T.dim).padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }
                let rows: [(Host, GPU?)] = s.hosts.flatMap { h in
                    h.ok == true && !h.gpus.isEmpty ? h.gpus.map { (h, Optional($0)) } : [(h, nil)]
                }
                VStack(spacing: 7) {
                    ForEach(Array(rows.enumerated()), id: \.offset) { _, r in
                        if let g = r.1 { GPURow(h: r.0, g: g, model: model) } else { DownRow(h: r.0, model: model) }
                    }
                }
                if let b = s.best, let h = s.hosts.first(where: { $0.label == b.host }) {
                    Button {
                        copyToClipboard("ssh \(h.target) -t 'export CUDA_VISIBLE_DEVICES=\(b.gpu); exec $SHELL -l'")
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "arrow.up.right.circle.fill").foregroundColor(T.blue)
                            Text("Best now").foregroundColor(T.dim)
                            Text("\(b.host)\(h.gpus.count > 1 ? " · \(b.gpu)" : "")").fontWeight(.semibold).foregroundColor(T.text)
                            Text("\(gb0(b.free_mb))G free").foregroundColor(T.faint)
                            Spacer()
                            Image(systemName: "doc.on.doc").foregroundColor(T.faint)
                        }
                        .font(.system(size: 10.5))
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(Capsule().fill(T.blue.opacity(0.12)))
                    }
                    .buttonStyle(.plain).padding(.top, 8).help("Copy ssh command with CUDA_VISIBLE_DEVICES set")
                }
            }
        }
        .padding(10)
        .onHover { hover = $0 }
    }
}

struct Blur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = .hudWindow; v.blendingMode = .behindWindow; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {}
}

struct PanelView: View {
    @ObservedObject var model: Model
    var snapshot = false
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        let maxH = (NSScreen.main?.visibleFrame.height ?? 900) - 40
        let content = PanelContent(model: model, snapshot: snapshot)
            .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
        Group {
            if snapshot { content } else { ScrollView(showsIndicators: false) { content } }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: snapshot ? nil : maxH)
        .background(ZStack {
            if !snapshot { Blur() }
            T.bg.opacity(snapshot ? 1 : 0.72)
            LinearGradient(colors: [T.blue.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
        })
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(HeightKey.self) { h in model.onHeight?(min(h, maxH)) }
    }
}

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

// MARK: - Window & app

final class WidgetWindow: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class App: NSObject, NSApplicationDelegate {
    let model = Model()
    var win: WidgetWindow!

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.applicationIconImage = renderPNG(IconView(), scale: 0.25).flatMap(NSImage.init(data:))
        win = WidgetWindow(contentRect: NSRect(x: 0, y: 0, width: panelWidth, height: 500),
                           styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        win.isOpaque = false
        win.backgroundColor = .clear
        win.hasShadow = true
        win.isMovableByWindowBackground = true
        win.hidesOnDeactivate = false
        win.isReleasedWhenClosed = false
        let host = NSHostingView(rootView: PanelView(model: model))
        host.sizingOptions = []
        win.contentView = host
        if !win.setFrameUsingName("GPUWidget"), let scr = NSScreen.main?.visibleFrame {
            win.setFrameOrigin(NSPoint(x: scr.maxX - panelWidth - 20, y: scr.maxY - 520))
        }
        win.setFrameAutosaveName("GPUWidget")
        model.onMode = { [weak self] in self?.apply($0) }
        model.onHeight = { [weak self] h in self?.resize(height: h) }
        apply(model.mode)
        win.orderFrontRegardless()
        model.refresh()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.model.refresh() }
    }

    // Grow/shrink with content while keeping the top edge where the user put it.
    func resize(height: CGFloat) {
        var f = win.frame
        guard height > 0, abs(f.height - height) > 0.5 else { return }
        f.origin.y += f.height - height
        f.size = NSSize(width: panelWidth, height: height)
        win.setFrame(f, display: true, animate: false)
    }

    func apply(_ mode: PanelMode) {
        switch mode {
        case .desktop:
            win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            win.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        case .normal:
            win.level = .normal
            win.collectionBehavior = [.canJoinAllSpaces]
        case .top:
            win.level = .floating
            win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        NSApp.unhide(nil)
        win.orderFrontRegardless()
        return false
    }
}

@MainActor func renderPNG<V: View>(_ view: V, scale: CGFloat = 2) -> Data? {
    let r = ImageRenderer(content: view)
    r.scale = scale
    guard let cg = r.cgImage else { return nil }
    return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
}

let args = CommandLine.arguments
let app = NSApplication.shared
// --snapshot out.png [status.json]: render the panel from the live backend, or from a saved JSON file (used for README demo).
if args.count >= 3 && (args[1] == "--snapshot" || args[1] == "--icon") {
    let data: Data? = MainActor.assumeIsolated {
        if args[1] == "--icon" { return renderPNG(IconView(), scale: 1) }
        let m = Model()
        let src = args.count > 3 ? URL(fileURLWithPath: args[3]) : base.appendingPathComponent("api/status")
        if let d = try? Data(contentsOf: src) {
            m.status = try? JSONDecoder().decode(Status.self, from: d); m.updated = Date()
        }
        return renderPNG(PanelView(model: m, snapshot: true))
    }
    try? data?.write(to: URL(fileURLWithPath: args[2]))
    exit(data == nil ? 1 : 0)
}
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
