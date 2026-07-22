// Dấu — demo app macOS native (SwiftUI). Gọi engine Rust qua libdau_demo.a.
// Chỉ để thử/review trên macOS; bộ gõ hệ thống thật chạy trên Linux (Fcitx5).
import SwiftUI
import AppKit

// MARK: - Bridge tới engine (đọc buffer tĩnh)

enum Dau {
    static func bufString(_ len: UInt32) -> String {
        if len == 0 { return "" }
        guard let p = demo_buf_ptr() else { return "" }
        return String(decoding: UnsafeBufferPointer(start: p, count: Int(len)), as: UTF8.self)
    }
    static func process(_ scalar: UInt32) -> String { bufString(demo_process(scalar)) }
    static func onBreak(_ scalar: UInt32) -> String { bufString(demo_on_break(scalar)) }
    static func escape() -> String { bufString(demo_escape()) }
    static func reset() { demo_reset() }
    static func setMethod(vni: Bool) { demo_set_method(vni ? 1 : 0) }
    static func setAutoCap(_ on: Bool) { demo_set_auto_cap(on ? 1 : 0) }
    static func setAutoRestore(_ on: Bool) { demo_set_auto_restore(on ? 1 : 0) }
}

let brandRed = Color(red: 0xDA/255, green: 0x25/255, blue: 0x1D/255)
let brandOrange = Color(red: 0xF4/255, green: 0x79/255, blue: 0x1F/255)

// MARK: - View bắt phím

final class KeyView: NSView {
    var onKey: ((NSEvent) -> Void)?
    override var acceptsFirstResponder: Bool { true }
    override func keyDown(with event: NSEvent) { onKey?(event) }
    override func viewDidMoveToWindow() { window?.makeFirstResponder(self) }
}

struct KeyCapture: NSViewRepresentable {
    var onKey: (NSEvent) -> Void
    func makeNSView(context: Context) -> KeyView {
        let v = KeyView(); v.onKey = onKey
        DispatchQueue.main.async { v.window?.makeFirstResponder(v) }
        return v
    }
    func updateNSView(_ nsView: KeyView, context: Context) { nsView.onKey = onKey }
}

// MARK: - App state (shared giữa window và tray)

final class Model: ObservableObject {
    static let shared = Model()

    @Published var committed = ""
    @Published var preedit = ""
    @Published var enabled = true { didSet { if !enabled { Dau.reset(); preedit = "" } } }
    @Published var vni = false { didSet { Dau.setMethod(vni: vni); resetAll() } }
    @Published var autoCap = false { didSet { Dau.setAutoCap(autoCap) } }
    @Published var autoRestore = true { didSet { Dau.setAutoRestore(autoRestore) } }

    let breaks: [Character: String] = [" ": " ", ".": ".", ",": ",", "!": "!", "?": "?", ";": ";", ":": ":"]

    func resetAll() { committed = ""; preedit = ""; Dau.reset() }

    func handle(_ event: NSEvent) {
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) { return }
        // Chế độ EN (tray tắt): gõ thẳng, không qua engine — như UniKey tắt tiếng Việt.
        if !enabled {
            switch event.keyCode {
            case 36: committed += "\n"; return
            case 51: if !committed.isEmpty { committed.removeLast() }; return
            default:
                if let ch = event.characters, ch.count == 1 { committed += ch }
                return
            }
        }
        switch event.keyCode {
        case 53: committed += Dau.escape(); preedit = ""; return          // Esc
        case 51: Dau.reset(); preedit = ""; return                        // Delete
        case 36: committed += Dau.onBreak(10) + "\n"; preedit = ""; return // Return
        default: break
        }
        guard let ch = event.characters?.first, event.characters?.count == 1 else { return }
        let scalar = ch.unicodeScalars.first!.value
        if let sep = breaks[ch] {
            committed += Dau.onBreak(scalar) + sep; preedit = ""
        } else {
            preedit = Dau.process(scalar)
        }
    }

    func feed(_ s: String) {
        resetAll()
        for ch in s {
            let scalar = ch.unicodeScalars.first!.value
            if let sep = breaks[ch] { committed += Dau.onBreak(scalar) + sep; preedit = "" }
            else { preedit = Dau.process(scalar) }
        }
    }
}

// MARK: - UI cửa sổ chính

struct ContentView: View {
    @ObservedObject var m = Model.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            configCard
            typingCard
            Text("Engine Rust thật (cùng core của addon Fcitx5 Linux) · tray VI/EN trên menu bar")
                .font(.caption).foregroundColor(.secondary)
        }
        .padding(24)
        .frame(width: 620)
        .background(KeyCapture(onKey: m.handle).allowsHitTesting(false))
    }

    var header: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 14)
                .fill(LinearGradient(colors: [brandRed, brandOrange], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 56, height: 56)
                .overlay(Text("d́").font(.system(size: 30, weight: .bold)).foregroundColor(.white))
            VStack(alignment: .leading, spacing: 2) {
                Text("Dấu").font(.system(size: 26, weight: .bold))
                Text("Bộ gõ tiếng Việt — demo engine trên macOS").font(.subheadline).foregroundColor(.secondary)
            }
            Spacer()
            Text("v0.1.0").font(.caption).padding(.horizontal, 8).padding(.vertical, 3)
                .background(Capsule().fill(brandRed.opacity(0.12))).foregroundColor(brandRed)
        }
    }

    var configCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CẤU HÌNH").font(.caption2).bold().foregroundColor(.secondary)
            Toggle(isOn: $m.enabled) { Text("Bật tiếng Việt (VI)") }.tint(brandRed)
            HStack {
                Text("Kiểu gõ"); Spacer()
                Picker("", selection: $m.vni) { Text("Telex").tag(false); Text("VNI").tag(true) }
                    .pickerStyle(.segmented).frame(width: 160)
            }
            Toggle(isOn: $m.autoCap) { Text("Tự viết hoa đầu câu") }.tint(brandOrange)
            Toggle(isOn: $m.autoRestore) { Text("Tự phục hồi tiếng Anh") }.tint(brandOrange)
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
    }

    var typingCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("GÕ THỬ (bấm phím trên bàn phím)").font(.caption2).bold().foregroundColor(.secondary)
            ScrollView {
                (Text(m.committed).foregroundColor(.white)
                 + Text(m.preedit).foregroundColor(.white).underline(true, color: brandOrange))
                .font(.system(size: 18, design: .monospaced))
                .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
            }
            .frame(height: 130).padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.06, green: 0.07, blue: 0.09)))
            HStack {
                ForEach(["tieengs ", "Vieejt Nam ", "hoaf khoer thuyr ", "nguoiwf "], id: \.self) { ex in
                    Button(ex.trimmingCharacters(in: .whitespaces)) { m.feed(ex) }
                        .buttonStyle(.bordered).controlSize(.small)
                }
            }
            Text("Space/dấu câu = commit từ · Esc = khôi phục tiếng Anh · Delete = xoá từ đang gõ")
                .font(.caption2).foregroundColor(.secondary)
        }
        .padding(16).background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.controlBackgroundColor)))
    }
}

// MARK: - Tray menu (menu bar extra, kiểu UniKey)

struct TrayMenu: View {
    @ObservedObject var m = Model.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button(m.enabled ? "✓ Tiếng Việt (VI)" : "Tiếng Việt (VI)") { m.enabled = true }
        Button(!m.enabled ? "✓ Tiếng Anh (EN)" : "Tiếng Anh (EN)") { m.enabled = false }
        Divider()
        Picker("Kiểu gõ", selection: $m.vni) {
            Text("Telex").tag(false)
            Text("VNI").tag(true)
        }
        Toggle("Tự viết hoa đầu câu", isOn: $m.autoCap)
        Toggle("Tự phục hồi tiếng Anh", isOn: $m.autoRestore)
        Divider()
        Button("Mở cửa sổ demo…") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Text("Dấu v0.1.0 — demo macOS")
        Button("Thoát Dấu") { NSApp.terminate(nil) }
    }
}

// MARK: - App entry

@main
struct DauDemoApp: App {
    @ObservedObject var m = Model.shared
    init() { Dau.setMethod(vni: false); Dau.setAutoCap(false); Dau.setAutoRestore(true) }

    var body: some Scene {
        Window("Dấu — Demo", id: "main") { ContentView() }
            .windowResizability(.contentSize)
        MenuBarExtra {
            TrayMenu()
        } label: {
            // Nhãn tray kiểu UniKey: VI (đang bật) / EN (tắt)
            Text(m.enabled ? "VI" : "EN")
                .font(.system(size: 12, weight: .heavy, design: .rounded))
        }
        .menuBarExtraStyle(.menu)
    }
}
