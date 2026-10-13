// Menu bar companion for gpumon.py: GPU util + VRAM per host in the status bar,
// a floating desktop panel with GPUs, VRAM and processes, and a detail menu.
import AppKit
import SwiftUI

let api = URL(string: "http://127.0.0.1:8765/api/status")!
let dashboard = URL(string: "http://localhost:8765")!
let serversPage = URL(string: "http://localhost:8765/#servers")!

// Where the panel lives: on the desktop under all windows (like a widget), a normal window, or always on top.
enum PanelMode: String, CaseIterable {
    case desktop, normal, top
    var title: String { ["desktop": "On Desktop (widget)", "normal": "Normal Window", "top": "Always on Top"][rawValue]! }
}

struct Proc: Decodable, Identifiable {
    let pid: Int; let mem: Double?; let user: String; let elapsed: Int?; let cmd: String; let mine: Bool
    var id: Int { pid }
}
struct GPU: Decodable, Identifiable {
    let index: Int; let name: String; let util: Double?; let mem_used: Double?; let mem_total: Double?
    let temp: Double?; let power: Double?; let procs: [Proc]
    var id: Int { index }
    var memFrac: Double { (mem_total ?? 0) > 0 ? (mem_used ?? 0) / mem_total! : 0 }
}
struct Host: Decodable, Identifiable {
    let label: String; let target: String; let ok: Bool?; let error: String?; let gpus: [GPU]
    var id: String { label }
}
struct Best: Decodable { let host: String; let gpu: Int; let free_mb: Double; let util: Double? }
struct Status: Decodable { let hosts: [Host]; let best: Best? }

func gb(_ mb: Double?) -> String { String(format: "%.1f", (mb ?? 0) / 1024) }
func gb0(_ mb: Double?) -> String { String(format: "%.0f", (mb ?? 0) / 1024) }
func dur(_ s: Int?) -> String {
    guard let s else { return "" }
    let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
    return d > 0 ? "\(d)d\(h)h" : h > 0 ? "\(h)h\(m)m" : "\(m)m"
}
func shortCmd(_ c: String, _ n: Int = 60) -> String {
    var parts = c.split(separator: " ").map(String.init)
    if let first = parts.first { parts[0] = first.split(separator: "/").last.map(String.init) ?? first }
    let s = parts.joined(separator: " ")
    return s.count > n ? String(s.prefix(n)) + "…" : s
}
func loadColor(_ pct: Double) -> NSColor { pct >= 90 ? .systemRed : pct >= 60 ? .systemOrange : .systemGreen }

final class Model: ObservableObject {
    @Published var status: Status?
    @Published var failed = false
}

// MARK: - Floating panel

struct Bar: View {
    let frac: Double
    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.12))
                Capsule().fill(Color(loadColor(frac * 100))).frame(width: max(0, g.size.width * min(1, frac)))
            }
        }.frame(height: 7)
    }
}

struct HostView: View {
    let h: Host
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Circle().fill(h.ok == true ? Color.green : Color.red).frame(width: 7, height: 7)
                Text(h.label).font(.system(size: 13, weight: .bold))
                if let g = h.gpus.first { Text(g.name.replacingOccurrences(of: "NVIDIA ", with: "")).font(.system(size: 11)).foregroundColor(.secondary) }
                Spacer()
                if h.ok != true { Text(h.error ?? "down").font(.system(size: 10)).foregroundColor(.red).lineLimit(1) }
            }
            ForEach(h.gpus) { g in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("GPU").frame(width: 34, alignment: .leading).foregroundColor(.secondary)
                        Bar(frac: (g.util ?? 0) / 100)
                        Text("\(Int(g.util ?? 0))%").frame(width: 92, alignment: .trailing)
                    }
                    HStack(spacing: 8) {
                        Text("VRAM").frame(width: 34, alignment: .leading).foregroundColor(.secondary)
                        Bar(frac: g.memFrac)
                        Text("\(gb(g.mem_used))/\(gb0(g.mem_total)) GB").frame(width: 92, alignment: .trailing)
                    }
                    if g.procs.isEmpty {
                        Text("no processes — free").foregroundColor(.green).padding(.top, 2)
                    }
                    ForEach(g.procs) { p in
                        HStack(spacing: 6) {
                            Text(p.user).fontWeight(p.mine ? .bold : .regular)
                                .foregroundColor(p.mine ? .blue : .primary).frame(width: 68, alignment: .leading).lineLimit(1)
                            Text("\(gb(p.mem)) GB").frame(width: 54, alignment: .trailing)
                            Text(dur(p.elapsed)).foregroundColor(.secondary).frame(width: 46, alignment: .trailing)
                            Text(shortCmd(p.cmd, 120)).foregroundColor(.secondary).lineLimit(1).truncationMode(.tail)
                        }
                        .font(.system(size: 10.5, design: .monospaced))
                        .help(p.cmd)
                    }
                }
                .font(.system(size: 11).monospacedDigit())
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.05)))
    }
}

struct PanelView: View {
    @ObservedObject var model: Model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("GPUs").font(.system(size: 13, weight: .bold))
                    Spacer()
                    Button("⚙ Servers") { NSWorkspace.shared.open(serversPage) }.buttonStyle(.borderless).font(.system(size: 11))
                    Button("Dashboard") { NSWorkspace.shared.open(dashboard) }.buttonStyle(.borderless).font(.system(size: 11))
                }
                if let s = model.status, s.hosts.isEmpty {
                    Text("No servers yet — click ⚙ Servers to add one.").foregroundColor(.secondary).font(.system(size: 11))
                }
                if let s = model.status {
                    if let b = s.best {
                        HStack(spacing: 4) {
                            Text("Best now:").foregroundColor(.secondary)
                            Text("\(b.host) GPU\(b.gpu)").bold()
                            Text("· \(gb(b.free_mb)) GB free").foregroundColor(.secondary)
                        }.font(.system(size: 11))
                    }
                    ForEach(s.hosts) { HostView(h: $0) }
                } else {
                    Text("Backend not reachable on :8765").foregroundColor(.red)
                }
                if model.failed && model.status != nil { Text("⚠ backend offline — stale data").font(.system(size: 10)).foregroundColor(.orange) }
            }
            .padding(10)
            .padding(.top, 10)
        }
        .frame(minWidth: 380, minHeight: 200)
    }
}

// MARK: - App

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    let model = Model()
    var panel: NSPanel!
    let defaults = UserDefaults.standard

    func applicationDidFinishLaunching(_ n: Notification) {
        defaults.register(defaults: ["panelOpen": true, "panelMode": PanelMode.desktop.rawValue])
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        makePanel()
        if defaults.bool(forKey: "panelOpen") { panel.orderFront(nil) }
        updateTitle()
        refresh()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
    }

    func makePanel() {
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 440, height: 640),
                        styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView],
                        backing: .buffered, defer: false)
        panel.title = "GPUs"
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        applyMode()
        let fx = NSVisualEffectView()
        fx.material = .hudWindow
        fx.blendingMode = .behindWindow
        fx.state = .active
        let host = NSHostingView(rootView: PanelView(model: model))
        host.translatesAutoresizingMaskIntoConstraints = false
        fx.addSubview(host)
        NSLayoutConstraint.activate([host.leadingAnchor.constraint(equalTo: fx.leadingAnchor), host.trailingAnchor.constraint(equalTo: fx.trailingAnchor),
                                     host.topAnchor.constraint(equalTo: fx.topAnchor), host.bottomAnchor.constraint(equalTo: fx.bottomAnchor)])
        panel.contentView = fx
        if !panel.setFrameUsingName("GPUPanel"), let scr = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: scr.maxX - 460, y: scr.maxY - 660))
        }
        panel.setFrameAutosaveName("GPUPanel")
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { [weak self] _ in
            self?.defaults.set(false, forKey: "panelOpen")
        }
    }

    var mode: PanelMode { PanelMode(rawValue: defaults.string(forKey: "panelMode") ?? "") ?? .desktop }

    func applyMode() {
        switch mode {
        case .desktop:
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        case .normal:
            panel.level = .normal
            panel.collectionBehavior = [.canJoinAllSpaces]
        case .top:
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        }
    }

    func refresh() {
        URLSession.shared.dataTask(with: api) { data, _, _ in
            let s = data.flatMap { try? JSONDecoder().decode(Status.self, from: $0) }
            DispatchQueue.main.async {
                if let s { self.model.status = s }
                self.model.failed = s == nil
                self.updateTitle()
            }
        }.resume()
    }

    // Two-line status item: one column per host, "A 99%" over "14/94G".
    func updateTitle() {
        guard let button = item.button else { return }
        button.title = ""
        guard let s = model.status, !model.failed else {
            button.image = nil
            button.attributedTitle = NSAttributedString(string: "GPU offline", attributes: [.foregroundColor: NSColor.systemRed,
                                                                                             .font: NSFont.systemFont(ofSize: 12, weight: .medium)])
            return
        }
        button.attributedTitle = NSAttributedString(string: "")
        let font = NSFont.monospacedDigitSystemFont(ofSize: 9.5, weight: .semibold)
        let firsts = s.hosts.map { $0.label.prefix(1).uppercased() }
        let cols: [(NSAttributedString, NSAttributedString)] = s.hosts.map { h in
            let one = h.label.prefix(1).uppercased()
            let letter = firsts.filter { $0 == one }.count > 1 ? h.label.prefix(2).capitalized : one
            guard h.ok == true, let g = h.gpus.max(by: { ($0.util ?? 0) < ($1.util ?? 0) }) else {
                return (NSAttributedString(string: "\(letter) ✕", attributes: [.font: font, .foregroundColor: NSColor.systemRed]),
                        NSAttributedString(string: "down", attributes: [.font: font, .foregroundColor: NSColor.systemRed]))
            }
            let u = g.util ?? 0
            let top = NSMutableAttributedString(string: "\(letter) ", attributes: [.font: font, .foregroundColor: NSColor.labelColor])
            top.append(NSAttributedString(string: "\(Int(u))%", attributes: [.font: font, .foregroundColor: loadColor(u)]))
            let used = h.gpus.reduce(0) { $0 + ($1.mem_used ?? 0) }, total = h.gpus.reduce(0) { $0 + ($1.mem_total ?? 0) }
            let bot = NSAttributedString(string: "\(gb0(used))/\(gb0(total))G",
                                         attributes: [.font: font, .foregroundColor: loadColor(total > 0 ? used / total * 100 : 0)])
            return (top, bot)
        }
        let gap: CGFloat = 8
        let widths = cols.map { ceil(max($0.0.size().width, $0.1.size().width)) }
        let size = NSSize(width: widths.reduce(0, +) + gap * CGFloat(max(0, cols.count - 1)), height: 22)
        let img = NSImage(size: size, flipped: false) { _ in
            var x: CGFloat = 0
            for (i, c) in cols.enumerated() {
                c.0.draw(at: NSPoint(x: x, y: 11))
                c.1.draw(at: NSPoint(x: x, y: 0))
                x += widths[i] + gap
            }
            return true
        }
        img.isTemplate = false
        button.image = img
        button.imagePosition = .imageOnly
    }

    // Rebuild the menu each time it opens so it's always fresh.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let toggle = NSMenuItem(title: panel.isVisible ? "Hide Panel" : "Show Panel", action: #selector(togglePanel), keyEquivalent: "p")
        toggle.target = self
        menu.addItem(toggle)
        let where_ = NSMenuItem(title: "Panel Position", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for m in PanelMode.allCases {
            let mi = NSMenuItem(title: m.title, action: #selector(setMode(_:)), keyEquivalent: "")
            mi.target = self
            mi.representedObject = m.rawValue
            mi.state = m == mode ? .on : .off
            sub.addItem(mi)
        }
        where_.submenu = sub
        menu.addItem(where_)
        let manage = NSMenuItem(title: "Add / Remove Servers…", action: #selector(openServers), keyEquivalent: ",")
        manage.target = self
        menu.addItem(manage)
        menu.addItem(.separator())

        guard let s = model.status else {
            menu.addItem(disabled("Backend not reachable on :8765"))
            addFooter(menu); return
        }
        if let b = s.best {
            let it = NSMenuItem(title: "", action: #selector(copyBest), keyEquivalent: "")
            it.target = self
            it.attributedTitle = rich([("Best now: ", .secondaryLabelColor, false),
                                       ("\(b.host) GPU \(b.gpu)", .labelColor, true),
                                       ("  \(gb(b.free_mb)) GB free · click to copy ssh", .secondaryLabelColor, false)])
            menu.addItem(it)
            menu.addItem(.separator())
        }
        for h in s.hosts {
            let head = NSMenuItem()
            head.attributedTitle = rich([(h.label, .labelColor, true),
                                         (h.ok == true ? "  \(h.target)" : "  ⚠ \(h.error ?? "down")",
                                          h.ok == true ? .secondaryLabelColor : .systemRed, false)])
            head.isEnabled = false
            menu.addItem(head)
            for g in h.gpus {
                let pct = g.util ?? 0
                let line = NSMenuItem()
                line.attributedTitle = rich([("   ● ", loadColor(pct), false),
                    ("GPU\(g.index) \(Int(pct))%  ", .labelColor, false),
                    ("\(gb(g.mem_used))/\(gb(g.mem_total)) GB  \(Int(g.temp ?? 0))°C  \(Int(g.power ?? 0))W  ", .labelColor, false),
                    (g.name, .secondaryLabelColor, false)])
                line.isEnabled = false
                menu.addItem(line)
                for p in g.procs {
                    let pi = NSMenuItem()
                    pi.attributedTitle = rich([
                        ("      \(p.user.padding(toLength: 10, withPad: " ", startingAt: 0)) ", p.mine ? .systemBlue : .secondaryLabelColor, p.mine),
                        ("\(gb(p.mem).leftPad(5)) GB  \(dur(p.elapsed).leftPad(6))  ", .secondaryLabelColor, false),
                        (shortCmd(p.cmd), .tertiaryLabelColor, false)], mono: true)
                    pi.toolTip = p.cmd
                    pi.isEnabled = false
                    menu.addItem(pi)
                }
                if g.procs.isEmpty { menu.addItem(disabled("      free")) }
            }
            menu.addItem(.separator())
        }
        addFooter(menu)
    }

    func addFooter(_ menu: NSMenu) {
        let open = NSMenuItem(title: "Open Dashboard", action: #selector(openDash), keyEquivalent: "d")
        open.target = self
        menu.addItem(open)
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    func disabled(_ t: String) -> NSMenuItem { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }

    func rich(_ parts: [(String, NSColor, Bool)], mono: Bool = false) -> NSAttributedString {
        let out = NSMutableAttributedString()
        for (text, color, bold) in parts {
            let font = mono ? NSFont.monospacedSystemFont(ofSize: 11, weight: bold ? .bold : .regular)
                            : NSFont.systemFont(ofSize: 13, weight: bold ? .semibold : .regular)
            out.append(NSAttributedString(string: text, attributes: [.font: font, .foregroundColor: color]))
        }
        return out
    }

    @objc func togglePanel() {
        if panel.isVisible { panel.close() } else { panel.orderFrontRegardless(); defaults.set(true, forKey: "panelOpen") }
    }

    @objc func setMode(_ sender: NSMenuItem) {
        defaults.set(sender.representedObject as? String, forKey: "panelMode")
        applyMode()
        if !panel.isVisible { togglePanel() }
    }

    @objc func openServers() { NSWorkspace.shared.open(serversPage) }

    @objc func openDash() { NSWorkspace.shared.open(dashboard) }

    @objc func copyBest() {
        guard let b = model.status?.best, let h = model.status?.hosts.first(where: { $0.label == b.host }) else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("ssh \(h.target) -t 'export CUDA_VISIBLE_DEVICES=\(b.gpu); exec $SHELL -l'", forType: .string)
    }
}

extension String {
    func leftPad(_ n: Int) -> String { count >= n ? self : String(repeating: " ", count: n - count) + self }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
