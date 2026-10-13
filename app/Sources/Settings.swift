// In-widget settings: servers, position, height.
import AppKit
import SwiftUI

// MARK: - Settings (inside the widget)

struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).font(.system(size: 9, weight: .bold)).foregroundColor(T.faint).tracking(0.6)
            content
        }
        .padding(11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(T.stroke, lineWidth: 1))
    }
}

struct ServerSettingsRow: View {
    let h: Host
    @ObservedObject var model: Model
    @State private var confirming = false
    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(h.ok == true ? T.green : h.ok == false ? T.red : T.amber).frame(width: 6, height: 6)
            VStack(alignment: .leading, spacing: 1) {
                Text(h.label).font(.system(size: 12, weight: .semibold)).foregroundColor(T.text)
                Text(h.ok == false ? (h.error ?? "offline") : h.target).font(.system(size: 9.5))
                    .foregroundColor(h.ok == false ? T.red : T.faint).lineLimit(1)
            }
            Spacer(minLength: 4)
            if confirming {
                Button("Cancel") { confirming = false }.buttonStyle(.plain).font(.system(size: 10)).foregroundColor(T.dim)
            }
            Button {
                if confirming { model.send("DELETE", "api/hosts/\(h.label)") { _ in } } else { confirming = true }
            } label: {
                Group {
                    if confirming { Text("Remove").font(.system(size: 10, weight: .semibold)) }
                    else { Image(systemName: "trash").font(.system(size: 10, weight: .semibold)) }
                }
                .foregroundColor(confirming ? .white : T.dim)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Capsule().fill(confirming ? T.red : Color.white.opacity(0.07)))
            }
            .buttonStyle(.plain).help("Remove \(h.label)")
        }
        .padding(.vertical, 3)
    }
}

struct SettingsView: View {
    @ObservedObject var model: Model
    @State private var label = ""
    @State private var target = ""
    @State private var error: String?
    @State private var busy = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            SettingsSection(title: "Servers") {
                let hosts = model.status?.hosts ?? []
                if hosts.isEmpty { Text("No servers yet.").font(.system(size: 11)).foregroundColor(T.dim) }
                ForEach(hosts) { h in
                    ServerSettingsRow(h: h, model: model)
                    if h.id != hosts.last?.id { Rectangle().fill(T.stroke).frame(height: 1) }
                }
            }

            SettingsSection(title: "Add server") {
                field("Name", "e.g. gpu-box", $label)
                field("SSH", "user@host or ~/.ssh/config alias", $target)
                Text("The server must accept `ssh` with your key, without asking for a password.")
                    .font(.system(size: 9.5)).foregroundColor(T.faint).fixedSize(horizontal: false, vertical: true)
                if let error { Text(error).font(.system(size: 10)).foregroundColor(T.red) }
                HStack {
                    Spacer()
                    Button(action: add) {
                        Text(busy ? "Adding…" : "Add server").font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
                            .padding(.horizontal, 14).padding(.vertical, 6)
                            .background(Capsule().fill(T.blue.opacity(label.isEmpty || target.isEmpty ? 0.4 : 1)))
                    }
                    .buttonStyle(.plain).disabled(busy || label.isEmpty || target.isEmpty)
                }
            }

            SettingsSection(title: "Widget") {
                HStack {
                    Text("Position").font(.system(size: 11)).foregroundColor(T.dim).frame(width: 56, alignment: .leading)
                    Picker("", selection: $model.mode) {
                        Text("Desktop").tag(PanelMode.desktop); Text("Window").tag(PanelMode.normal); Text("On top").tag(PanelMode.top)
                    }.pickerStyle(.segmented).labelsHidden()
                }
                HStack {
                    Text("Height").font(.system(size: 11)).foregroundColor(T.dim).frame(width: 56, alignment: .leading)
                    Picker("", selection: $model.maxHeight) {
                        Text("S").tag(PanelHeight.compact); Text("M").tag(PanelHeight.medium)
                        Text("L").tag(PanelHeight.tall); Text("Fit").tag(PanelHeight.screen)
                    }.pickerStyle(.segmented).labelsHidden()
                }
            }

            HStack {
                Button { NSWorkspace.shared.open(dashboard) } label: {
                    Label("Web dashboard", systemImage: "safari").font(.system(size: 10.5)).foregroundColor(T.dim)
                }.buttonStyle(.plain)
                Spacer()
                Button { NSApp.terminate(nil) } label: {
                    Label("Quit", systemImage: "power").font(.system(size: 10.5)).foregroundColor(T.dim)
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 4).padding(.top, 2)
        }
    }

    func field(_ name: String, _ hint: String, _ text: Binding<String>) -> some View {
        HStack(spacing: 6) {
            Text(name).font(.system(size: 11)).foregroundColor(T.dim).frame(width: 38, alignment: .leading)
            TextField(hint, text: text).textFieldStyle(.plain).font(.system(size: 11.5)).foregroundColor(T.text)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 7).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(T.stroke, lineWidth: 1))
                .onSubmit(add)
        }
    }

    func add() {
        guard !label.isEmpty, !target.isEmpty, !busy else { return }
        busy = true; error = nil
        model.send("POST", "api/hosts", ["label": label.trimmingCharacters(in: .whitespaces),
                                         "target": target.trimmingCharacters(in: .whitespaces)]) { err in
            busy = false
            if let err { error = err } else { label = ""; target = "" }
        }
    }
}
