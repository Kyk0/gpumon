// GPU Monitor: desktop widget for the gpumon backend.
// `--snapshot out.png [status.json]` renders the panel to an image, `--icon out.png` renders the app icon.
import AppKit
import SwiftUI

// MARK: - Window & app

final class WidgetWindow: NSPanel {
    override var canBecomeKey: Bool { true }

    // There's no Edit menu, so ⌘V/⌘C/⌘X/⌘A/⌘Z would do nothing in the Settings text fields.
    // Route them to the focused field directly.
    override func performKeyEquivalent(with e: NSEvent) -> Bool {
        let mods = e.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods == .command || mods == [.command, .shift], let k = e.charactersIgnoringModifiers?.lowercased() {
            let sel: Selector? = mods == .command
                ? ["x": #selector(NSText.cut(_:)), "c": #selector(NSText.copy(_:)), "v": #selector(NSText.paste(_:)),
                   "a": #selector(NSText.selectAll(_:)), "z": Selector(("undo:"))][k]
                : (k == "z" ? Selector(("redo:")) : nil)
            if let sel, NSApp.sendAction(sel, to: nil, from: self) { return true }
        }
        return super.performKeyEquivalent(with: e)
    }
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
        updateRoom()
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: win, queue: .main) { [weak self] _ in self?.updateRoom() }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.updateRoom() }
        win.orderFrontRegardless()
        model.refresh()
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.model.refresh() }
        // GPUMON_SELFTEST=out.png: capture the live window after it settles, print its geometry, exit.
        if let out = ProcessInfo.processInfo.environment["GPUMON_SELFTEST"] {
            model.settings = ProcessInfo.processInfo.environment["GPUMON_SELFTEST_SETTINGS"] != nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [self] in
                let v = win.contentView!
                if let rep = v.bitmapImageRepForCachingDisplay(in: v.bounds) {
                    v.cacheDisplay(in: v.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: out))
                }
                print("frame", win.frame, "room", model.room)
                func scrolls(_ v: NSView) -> [NSScrollView] { (v as? NSScrollView).map { [$0] } ?? v.subviews.flatMap(scrolls) }
                for sv in scrolls(v) { print("scroll visible", sv.contentView.bounds.height, "document", sv.documentView?.frame.height ?? 0) }
                exit(0)
            }
        }
    }

    func updateRoom() {
        guard let scr = (win.screen ?? NSScreen.main)?.visibleFrame else { return }
        let room = (win.frame.maxY - scr.minY - 12).rounded()
        if abs(room - model.room) >= 1 { model.room = room }
    }

    // Grow/shrink with content while keeping the top edge where the user put it.
    // Resizing from inside a SwiftUI layout pass can re-trigger layout, so coalesce requests and apply
    // them once on the next run-loop turn, ignoring sub-2pt jitter.
    var pendingHeight: CGFloat?
    func resize(height: CGFloat) {
        let h = height.rounded(.up)
        guard h > 0 else { return }
        let scheduled = pendingHeight != nil
        pendingHeight = h
        if scheduled { return }
        DispatchQueue.main.async { [self] in
            guard let h = pendingHeight else { return }
            pendingHeight = nil
            var f = win.frame
            guard abs(f.height - h) >= 2 else { return }
            f.origin.y += f.height - h
            f.size = NSSize(width: panelWidth, height: h)
            win.setFrame(f, display: true, animate: false)
        }
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
