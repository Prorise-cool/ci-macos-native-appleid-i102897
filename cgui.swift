import Foundation
import AppKit
import CoreGraphics
import ApplicationServices

let args = CommandLine.arguments
func out(_ s: String) { print(s) }
func err(_ s: String) -> Never { FileHandle.standardError.write((s+"\n").data(using:.utf8)!); exit(2) }
guard args.count >= 2 else { err("usage: cgui list|ax|front <name>|key <text>|keycode <n>|click <x> <y>|axdump <pid> [depth]|axfind <pid> <needle>|axset <pid> <needle> <text>|axpress <pid> <needle>|axfocus <pid> <needle>") }
let cmd = args[1]

// ---------------------------------------------------------------- AX helpers
func attr(_ el: AXUIElement, _ k: String) -> CFTypeRef? {
    var v: CFTypeRef?
    if AXUIElementCopyAttributeValue(el, k as CFString, &v) == .success { return v }
    return nil
}
func sattr(_ el: AXUIElement, _ k: String) -> String {
    guard let v = attr(el, k) else { return "" }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return "\(n)" }
    return "<\(type(of: v))>"
}
func axPoint(_ el: AXUIElement) -> CGPoint? {
    guard let v = attr(el, kAXPositionAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var p = CGPoint.zero
    if AXValueGetValue(v as! AXValue, .cgPoint, &p) { return p }
    return nil
}
func axSize(_ el: AXUIElement) -> CGSize? {
    guard let v = attr(el, kAXSizeAttribute), CFGetTypeID(v) == AXValueGetTypeID() else { return nil }
    var s = CGSize.zero
    if AXValueGetValue(v as! AXValue, .cgSize, &s) { return s }
    return nil
}
func axPosStr(_ el: AXUIElement) -> String {
    if let p = axPoint(el), let s = axSize(el) {
        return "pos=\(Int(p.x)),\(Int(p.y)) size=\(Int(s.width))x\(Int(s.height)) center=\(Int(p.x + s.width/2)),\(Int(p.y + s.height/2))"
    }
    return "pos=? size=?"
}
func axEnabled(_ el: AXUIElement) -> String {
    guard let v = attr(el, kAXEnabledAttribute) as? NSNumber else { return "" }
    return "enabled=\(v.boolValue)"
}
func axActions(_ el: AXUIElement) -> String {
    var names: CFArray?
    if AXUIElementCopyActionNames(el, &names) == .success, let a = names as? [String] { return "actions=[\(a.joined(separator: ","))]" }
    return ""
}
func line(_ el: AXUIElement, _ depth: Int) -> String {
    let pad = String(repeating: "  ", count: depth)
    let val = sattr(el, kAXValueAttribute)
    return "\(pad)role=\(sattr(el, kAXRoleAttribute)) sub=\(sattr(el, kAXSubroleAttribute)) title=[\(sattr(el, kAXTitleAttribute))] desc=[\(sattr(el, kAXDescriptionAttribute))] value=[\(val.prefix(80))] id=[\(sattr(el, kAXIdentifierAttribute))] \(axPosStr(el)) \(axEnabled(el)) \(axActions(el))"
}
func kids(_ el: AXUIElement) -> [AXUIElement] {
    (attr(el, kAXChildrenAttribute) as? [AXUIElement]) ?? []
}
func walk(_ el: AXUIElement, _ depth: Int, _ maxDepth: Int, _ visit: (AXUIElement, Int) -> Void) {
    if depth > maxDepth { return }
    visit(el, depth)
    for k in kids(el).prefix(80) { walk(k, depth + 1, maxDepth, visit) }
}
func appEl(_ pid: pid_t) -> AXUIElement { AXUIElementCreateApplication(pid) }

func findMatches(_ pid: pid_t, _ needle: String, _ maxDepth: Int = 14) -> [(AXUIElement, Int)] {
    let n = needle.lowercased()
    var res: [(AXUIElement, Int)] = []
    walk(appEl(pid), 0, maxDepth) { el, d in
        let hay = (sattr(el, kAXTitleAttribute) + "|" + sattr(el, kAXDescriptionAttribute) + "|" + sattr(el, kAXIdentifierAttribute) + "|" + sattr(el, kAXValueAttribute) + "|" + sattr(el, kAXRoleAttribute)).lowercased()
        if hay.contains(n) { res.append((el, d)) }
    }
    return res
}

// ---------------------------------------------------------------- window list
func listWindows() {
    let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    if let arr = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] {
        for w in arr {
            let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
            let pid = w[kCGWindowOwnerPID as String] as? Int ?? 0
            let num = w[kCGWindowNumber as String] as? Int ?? 0
            let layer = w[kCGWindowLayer as String] as? Int ?? 0
            let name = w[kCGWindowName as String] as? String ?? ""
            let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
            out("win=\(num)\tpid=\(pid)\tlayer=\(layer)\towner=\(owner)\tname=\(name.isEmpty ? "-" : name)\tbounds=\(b["X"] ?? 0),\(b["Y"] ?? 0),\(b["Width"] ?? 0),\(b["Height"] ?? 0)")
        }
    }
}

func frontApp(_ name: String) {
    let apps = NSWorkspace.shared.runningApplications
    if let a = apps.first(where: { ($0.localizedName ?? "") == name || ($0.bundleIdentifier ?? "") == name }) {
        out("activate \(a.localizedName ?? "?") pid=\(a.processIdentifier) ok=\(a.activate(options: [.activateAllWindows, .activateIgnoringOtherApps]))")
    } else { out("not running: \(name)") }
}

func postText(_ text: String) {
    let src = CGEventSource(stateID: .hidSystemState)
    var chars = Array(text.utf16)
    if let d = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
        d.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        d.post(tap: .cghidEventTap)
    }
    usleep(15000)
    if let u = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
        u.keyboardSetUnicodeString(stringLength: chars.count, unicodeString: &chars)
        u.post(tap: .cghidEventTap)
    }
    out("typed \(chars.count) utf16 units")
}

func postKeycode(_ code: CGKeyCode) {
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: true)?.post(tap: .cghidEventTap)
    usleep(30000)
    CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: false)?.post(tap: .cghidEventTap)
    out("keycode \(code)")
}

func clickAt(_ x: Double, _ y: Double) {
    let p = CGPoint(x: x, y: y)
    let src = CGEventSource(stateID: .hidSystemState)
    CGEvent(mouseEventSource: src, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(120000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60000)
    CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
    out("clicked \(x),\(y) trusted=\(AXIsProcessTrusted())")
}

func setValue(_ el: AXUIElement, _ s: String) -> Bool {
    AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    usleep(80000)
    let r = AXUIElementSetAttributeValue(el, kAXValueAttribute as CFString, s as CFString)
    return r == .success
}

switch cmd {
case "list": listWindows()
case "ax": out("AXIsProcessTrusted=\(AXIsProcessTrusted())")
case "front": guard args.count > 2 else { err("front <name>") }; frontApp(args[2])
case "key": guard args.count > 2 else { err("key <text>") }; postText(args[2])
case "keycode": guard args.count > 2, let c = UInt16(args[2]) else { err("keycode <n>") }; postKeycode(CGKeyCode(c))
case "click": guard args.count > 3, let x = Double(args[2]), let y = Double(args[3]) else { err("click <x> <y>") }; clickAt(x, y)

case "axdump":
    guard args.count > 2, let pid = Int32(args[2]) else { err("axdump <pid> [depth]") }
    let maxD = args.count > 3 ? (Int(args[3]) ?? 4) : 4
    walk(appEl(pid_t(pid)), 0, maxD) { el, d in out(line(el, d)) }

case "axfind":
    guard args.count > 3, let pid = Int32(args[2]) else { err("axfind <pid> <needle>") }
    let ms = findMatches(pid_t(pid), args[3])
    out("matches=\(ms.count) for [\(args[3])]")
    for (el, d) in ms.prefix(40) { out(line(el, d)) }

case "axset":
    guard args.count > 4, let pid = Int32(args[2]) else { err("axset <pid> <needle> <text>") }
    let ms = findMatches(pid_t(pid), args[3])
    var done = 0
    for (el, d) in ms {
        let role = sattr(el, kAXRoleAttribute)
        if role == "AXTextField" || role == "AXTextArea" {
            let ok = setValue(el, args[4])
            out("set role=\(role) id=[\(sattr(el, kAXIdentifierAttribute))] depth=\(d) ok=\(ok) readback=[\(sattr(el, kAXValueAttribute))]")
            done += 1
            if done >= 1 { break }
        }
    }
    if done == 0 { out("no editable element matched [\(args[3])] (matches=\(ms.count))") }

case "axpress":
    guard args.count > 3, let pid = Int32(args[2]) else { err("axpress <pid> <needle>") }
    let ms = findMatches(pid_t(pid), args[3])
    var pressed = 0
    for (el, d) in ms {
        let acts = axActions(el)
        if acts.contains("AXPress") {
            let r = AXUIElementPerformAction(el, kAXPressAction as CFString)
            out("press depth=\(d) role=\(sattr(el, kAXRoleAttribute)) title=[\(sattr(el, kAXTitleAttribute))] id=[\(sattr(el, kAXIdentifierAttribute))] rc=\(r.rawValue) \(axEnabled(el))")
            pressed += 1
            if pressed >= 1 { break }
        }
    }
    if pressed == 0 { out("no pressable element matched [\(args[3])] (matches=\(ms.count))") }

case "axfocus":
    guard args.count > 3, let pid = Int32(args[2]) else { err("axfocus <pid> <needle>") }
    let ms = findMatches(pid_t(pid), args[3])
    guard let (el, d) = ms.first, let p = axPoint(el), let s = axSize(el) else { out("no element with coords matched [\(args[3])] (matches=\(ms.count))"); exit(0) }
    out("focus target depth=\(d) role=\(sattr(el, kAXRoleAttribute)) id=[\(sattr(el, kAXIdentifierAttribute))] \(axPosStr(el))")
    let _ = AXUIElementSetAttributeValue(el, kAXFocusedAttribute as CFString, kCFBooleanTrue)
    clickAt(Double(p.x + s.width/2), Double(p.y + s.height/2))

default: err("unknown \(cmd)")
}
