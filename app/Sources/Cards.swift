// GPU cards, summary tiles and their small building blocks.
import AppKit
import SwiftUI

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
        .onHover { hover = $0 }
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
    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(h.ok == nil ? T.amber : T.red).frame(width: 6, height: 6)
            Text(h.label).font(.system(size: 12, weight: .semibold)).foregroundColor(T.text)
            Text(h.ok == nil ? "connecting…" : "offline").font(.system(size: 10)).foregroundColor(T.faint)
            Spacer()
        }
        .padding(11)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(T.stroke, lineWidth: 1))
        .help(h.error ?? "")
    }
}
