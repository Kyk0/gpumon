// GPU Monitor: desktop widget for gpumon.py: a glass panel with every server's GPUs, VRAM and processes.
// Run with `--snapshot out.png` to render the panel to an image, `--icon out.png` to render the app icon.
import AppKit
import SwiftUI

let base = URL(string: "http://127.0.0.1:8765")!
let dashboard = URL(string: "http://localhost:8765")!
let panelWidth: CGFloat = 280

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
    static func user(_ name: String) -> Color {
        let h = name.unicodeScalars.reduce(5381) { ($0 &* 33) &+ Int($1.value) }
        return Color(hue: Double(abs(h) % 360) / 360, saturation: 0.55, brightness: 0.95)
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

// MARK: - GPU row: "● name   97%  69/80G", thin VRAM bar, who's on it

struct GPURow: View {
    let h: Host; let g: GPU
    @ObservedObject var model: Model
    @State private var hover = false
    @State private var confirming = false

    var dot: Color { h.ok == true ? T.load(g.utilFrac) : h.ok == false ? T.red : T.amber }
    var users: [(String, Double, Bool)] {
        var order: [String] = [], mem: [String: Double] = [:], mine: [String: Bool] = [:]
        for p in g.procs {
            if mem[p.user] == nil { order.append(p.user) }
            mem[p.user, default: 0] += p.mem ?? 0
            mine[p.user] = p.mine
        }
        return order.map { ($0, mem[$0]!, mine[$0]!) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Circle().fill(dot).frame(width: 6, height: 6)
                Text(h.label).font(.system(size: 12, weight: .semibold)).foregroundColor(T.text)
                if h.gpus.count > 1 { Text("\(g.index)").font(.system(size: 10, weight: .medium)).foregroundColor(T.faint) }
                Spacer(minLength: 4)
                if hover && g.index == h.gpus.first?.index {
                    Button {
                        if confirming { model.send("DELETE", "api/hosts/\(h.label)") { _ in } } else { confirming = true }
                    } label: {
                        Text(confirming ? "remove" : "✕").font(.system(size: 9.5, weight: .semibold))
                            .foregroundColor(confirming ? T.red : T.faint)
                    }.buttonStyle(.plain)
                }
                Text("\(Int(g.util ?? 0))%").font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundColor(T.load(g.utilFrac)).frame(width: 38, alignment: .trailing)
                Text("\(gb0(g.mem_used))/\(gb0(g.mem_total))G").font(.system(size: 10.5).monospacedDigit())
                    .foregroundColor(T.dim).frame(width: 50, alignment: .trailing)
            }
            Meter(frac: g.memFrac, color: T.load(g.memFrac).opacity(0.85))
            if users.isEmpty {
                Text("idle").font(.system(size: 10)).foregroundColor(T.green.opacity(0.8))
            } else {
                users.enumerated().reduce(Text("")) { acc, e in
                    let (i, u) = e
                    let part = Text("\(u.2 ? "you" : u.0) \(gb0(u.1))G").foregroundColor(u.2 ? T.blue : T.faint)
                    return i == 0 ? part : Text("\(acc)\(Text("  ·  ").foregroundColor(T.faint))\(part)")
                }
                .font(.system(size: 10)).lineLimit(1).truncationMode(.tail)
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hover = $0; if !$0 { confirming = false } }
        .help(tooltip)
    }

    var tooltip: String {
        var lines = ["\(h.label) · \(g.name) · \(Int(g.temp ?? 0))°C · \(Int(g.power ?? 0))W", h.target]
        if let e = h.error, h.ok != true { lines.append(e) }
        for p in g.procs { lines.append("\(p.user)  \(gb(p.mem))G  \(dur(p.elapsed))  \(shortCmd(p.cmd).prefix(70))") }
        return lines.joined(separator: "\n")
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
        .padding(.vertical, 7)
        .contentShape(Rectangle())
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
                Text("GPUs").font(.system(size: 11, weight: .bold)).foregroundColor(T.dim).tracking(0.5)
                if model.offline { Text("· backend offline").font(.system(size: 10)).foregroundColor(T.red) }
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
            .frame(height: 18)
            .padding(.bottom, 4)

            if adding { AddServer(model: model, shown: $adding) }

            if let s = model.status {
                if s.hosts.isEmpty && !adding {
                    Button { adding = true } label: {
                        Text("+ add a server").font(.system(size: 11)).foregroundColor(T.dim).padding(.vertical, 8)
                    }.buttonStyle(.plain)
                }
                let rows: [(Host, GPU?)] = s.hosts.flatMap { h in
                    h.ok == true && !h.gpus.isEmpty ? h.gpus.map { (h, Optional($0)) } : [(h, nil)]
                }
                ForEach(Array(rows.enumerated()), id: \.offset) { i, r in
                    if i > 0 { Rectangle().fill(T.stroke).frame(height: 1) }
                    if let g = r.1 { GPURow(h: r.0, g: g, model: model) } else { DownRow(h: r.0, model: model) }
                }
                if let b = s.best {
                    Text("best now → \(b.host)\(rows.filter { $0.0.label == b.host }.count > 1 ? " gpu\(b.gpu)" : "") · \(gb0(b.free_mb))G free")
                        .font(.system(size: 9.5)).foregroundColor(T.faint).padding(.top, 6)
                }
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
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
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
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
