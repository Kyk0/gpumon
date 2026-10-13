// The widget panel: fixed header + scrolling body.
import AppKit
import SwiftUI

// MARK: - Panel

struct HeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

struct HeaderHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

// Fixed top: title, buttons, add-server form, cluster stats.
struct PanelHeader: View {
    @ObservedObject var model: Model
    var snapshot = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Text("GPU Monitor").font(.system(size: 14, weight: .bold, design: .rounded)).foregroundColor(T.text)
                Circle().fill(model.offline ? T.red : T.green).frame(width: 5, height: 5)
                    .shadow(color: model.offline ? T.red : T.green, radius: 3)
                Text(model.offline ? "offline" : (model.updated.map { DateFormatter.localizedString(from: $0, dateStyle: .none, timeStyle: .medium) } ?? "…"))
                    .font(.system(size: 9.5).monospacedDigit()).foregroundColor(model.offline ? T.red : T.faint)
                Spacer()
                Button { withAnimation(.easeOut(duration: 0.2)) { model.settings.toggle() } } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.settings ? "checkmark" : "gearshape.fill").font(.system(size: 10, weight: .semibold))
                        Text(model.settings ? "Done" : "Settings").font(.system(size: 10.5, weight: .semibold))
                    }
                    .foregroundColor(model.settings ? .white : T.dim)
                    .padding(.horizontal, 9).padding(.vertical, 4)
                    .background(Capsule().fill(model.settings ? T.blue : Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain).help("Servers, position, size")
            }
            .frame(height: 20)
            .padding(.bottom, 8)

            if !model.settings, let s = model.status, !s.hosts.isEmpty { Summary(s: s) }
        }
        .padding(.horizontal, 10).padding(.top, 10).padding(.bottom, 8)
    }
}

// Scrolling part: one card per GPU, then the "best now" pill.
struct PanelBody: View {
    @ObservedObject var model: Model

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if model.settings {
                SettingsView(model: model)
            } else if let s = model.status {
                if s.hosts.isEmpty {
                    Button { model.settings = true } label: {
                        VStack(spacing: 6) {
                            Image(systemName: "server.rack").font(.system(size: 20))
                            Text("No servers yet — tap to add one").font(.system(size: 11, weight: .medium))
                        }.foregroundColor(T.dim).frame(maxWidth: .infinity).padding(24)
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
        .padding(.horizontal, 10).padding(.bottom, 10)
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
    @State private var headerH: CGFloat = 0
    @State private var bodyH: CGFloat = 0

    // Tallest the window may get: the chosen height, but never past the bottom of the screen.
    var cap: CGFloat { max(260, min(model.maxHeight.points ?? .infinity, model.room)) }
    var scrollH: CGFloat { max(0, min(bodyH, cap - headerH)) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 20, style: .continuous)
        VStack(spacing: 0) {
            PanelHeader(model: model, snapshot: snapshot)
                .background(GeometryReader { Color.clear.preference(key: HeaderHeightKey.self, value: $0.size.height) })
            if snapshot {
                PanelBody(model: model)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    PanelBody(model: model)
                        .frame(width: panelWidth)
                        .background(GeometryReader { Color.clear.preference(key: HeightKey.self, value: $0.size.height) })
                }
                .frame(height: scrollH)
                .mask(LinearGradient(stops: bodyH > scrollH + 1
                    ? [.init(color: .clear, location: 0), .init(color: .black, location: 0.03),
                       .init(color: .black, location: 0.93), .init(color: .clear, location: 1)]
                    : [.init(color: .black, location: 0), .init(color: .black, location: 1)],
                    startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(width: panelWidth, alignment: .top)
        .background(ZStack {
            if !snapshot { Blur() }
            T.bg.opacity(snapshot ? 1 : 0.72)
            LinearGradient(colors: [T.blue.opacity(0.07), .clear], startPoint: .topLeading, endPoint: .center)
        })
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.08), lineWidth: 1))
        .environment(\.colorScheme, .dark)
        .onPreferenceChange(HeaderHeightKey.self) { h in
            if abs(h - headerH) >= 1 { headerH = h.rounded(.up); report() }
        }
        .onPreferenceChange(HeightKey.self) { h in
            if abs(h - bodyH) >= 1 { bodyH = h.rounded(.up); report() }
        }
        .onChange(of: cap) { report() }
    }

    func report() { if headerH > 0 { model.onHeight?(headerH + scrollH) } }
}
