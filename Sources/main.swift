// Kumanda — use a game controller as a mouse on the Mac desktop.
// Left stick moves the pointer, right stick scrolls, buttons click and press keys.
// Steps aside on its own while a game is in front, so games get the controller alone.
import AppKit
import GameController
import ServiceManagement

func log(_ s: String) {
    FileHandle.standardError.write(Data("\(Date()) \(s)\n".utf8))
}

// MARK: - Settings

enum Prefs {
    static let d = UserDefaults.standard
    static var enabled: Bool { get { d.object(forKey: "enabled") as? Bool ?? true } set { d.set(newValue, forKey: "enabled") } }
    static var speed: Double { get { d.object(forKey: "speed") as? Double ?? 1.0 } set { d.set(newValue, forKey: "speed") } }
    /// Glide to the nearest button once the stick rests.
    static var snap: Bool { get { d.object(forKey: "snap") as? Bool ?? true } set { d.set(newValue, forKey: "snap") } }
    /// Seconds the stick must rest before gliding.
    static var snapDelay: Double { get { d.object(forKey: "snapDelay") as? Double ?? 1.0 } set { d.set(newValue, forKey: "snapDelay") } }
    /// Face button layout: "auto", "xbox" (A at the bottom) or "nintendo" (A on the right).
    static var layout: String { get { d.string(forKey: "layout") ?? "auto" } set { d.set(newValue, forKey: "layout") } }

    /// Extra apps where Kumanda pauses, one bundle id per line.
    static let gamesFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/kumanda/games.txt")
    static func userGames() -> Set<String> {
        guard let s = try? String(contentsOf: gamesFile, encoding: .utf8) else { return [] }
        return Set(s.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty && !$0.hasPrefix("#") })
    }
    static func setUserGame(_ id: String, _ on: Bool) {
        var g = userGames()
        if on { g.insert(id) } else { g.remove(id) }
        try? FileManager.default.createDirectory(at: gamesFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? (g.sorted().joined(separator: "\n") + "\n").write(to: gamesFile, atomically: true, encoding: .utf8)
    }
}

// MARK: - Synthetic input

enum Out {
    static let src = CGEventSource(stateID: .hidSystemState)

    static var location: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    static func displays() -> [CGRect] {
        var n: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &n)
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(n))
        CGGetActiveDisplayList(n, &ids, &n)
        return ids.map { CGDisplayBounds($0) }
    }

    /// Keeps the pointer on a screen: it may cross into a neighbouring display, never into the gaps.
    static func clamp(_ p: CGPoint, from old: CGPoint) -> CGPoint {
        let ds = displays()
        if ds.contains(where: { $0.contains(p) }) { return p }
        let home = ds.first(where: { $0.contains(old) }) ?? ds.first ?? .zero
        return CGPoint(x: min(max(p.x, home.minX), home.maxX - 1), y: min(max(p.y, home.minY), home.maxY - 1))
    }

    static func move(to p: CGPoint, dragging button: CGMouseButton?) {
        let type: CGEventType
        switch button {
        case .left?: type = .leftMouseDragged
        case .right?: type = .rightMouseDragged
        default: type = .mouseMoved
        }
        CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: p, mouseButton: button ?? .left)?.post(tap: .cghidEventTap)
    }

    static func mouse(_ button: CGMouseButton, down: Bool, clicks: Int) {
        let type: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        let e = CGEvent(mouseEventSource: src, mouseType: type, mouseCursorPosition: location, mouseButton: button)
        e?.setIntegerValueField(.mouseEventClickState, value: Int64(clicks))
        e?.post(tap: .cghidEventTap)
    }

    static func scroll(dy: Int32, dx: Int32) {
        CGEvent(scrollWheelEvent2Source: src, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    static func key(_ code: CGKeyCode, _ flags: CGEventFlags = []) {
        for down in [true, false] {
            let e = CGEvent(keyboardEventSource: src, virtualKey: code, keyDown: down)
            e?.flags = flags
            e?.post(tap: .cghidEventTap)
        }
    }
}

enum Key {
    static let left: CGKeyCode = 123, right: CGKeyCode = 124, down: CGKeyCode = 125, up: CGKeyCode = 126
    static let escape: CGKeyCode = 53, ret: CGKeyCode = 36, space: CGKeyCode = 49, tab: CGKeyCode = 48
}

// MARK: - Face buttons by position

/// Face buttons named by where they sit, not by the letter printed on them.
/// Xbox and PlayStation pads report A/cross at the bottom. Nintendo-style pads
/// (and 8BitDo in D/Switch mode) report by label, so A is on the right.
struct Face {
    let south, east, west, north: GCControllerButtonInput

    static func nintendoLayout(_ c: GCController?) -> Bool {
        switch Prefs.layout {
        case "xbox": return false
        case "nintendo": return true
        default:
            let name = ((c?.vendorName ?? "") + " " + (c?.productCategory ?? "")).lowercased()
            if name.contains("dualshock") || name.contains("dualsense") || name.contains("xbox") { return false }
            return ["8bitdo", "switch", "nintendo", "joy-con"].contains { name.contains($0) }
        }
    }

    init(_ pad: GCExtendedGamepad, nintendo: Bool) {
        if nintendo { south = pad.buttonB; east = pad.buttonA; west = pad.buttonY; north = pad.buttonX }
        else { south = pad.buttonA; east = pad.buttonB; west = pad.buttonX; north = pad.buttonY }
    }
}

// MARK: - Dictation

/// Starts or stops Dikte (github.com/yusufipk/dikte) through its command line.
enum Dictation {
    static let paths = [FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/dikte").path,
                        "/Applications/Dikte.app/Contents/MacOS/Dikte"]
    static var available: Bool { paths.contains { FileManager.default.isExecutableFile(atPath: $0) } }
    static func toggle() {
        guard let p = paths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else { log("dikte not found"); return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: p)
        task.arguments = ["toggle"]
        task.standardOutput = FileHandle.nullDevice; task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { log("dikte: \(error)") }
    }
}

// MARK: - Snap to the nearest button

/// Finds the clickable thing (button, link, checkbox, menu item…) nearest to a point,
/// using the Accessibility API. Looks in rings around the pointer up to `radius`.
enum Snap {
    static let system: AXUIElement = {
        let s = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(s, 0.05)
        return s
    }()
    static let radius: CGFloat = 90
    static let roles: Set<String> = ["AXButton", "AXLink", "AXCheckBox", "AXRadioButton", "AXPopUpButton", "AXMenuButton",
                                     "AXMenuItem", "AXMenuBarItem", "AXTab", "AXTextField", "AXTextArea", "AXComboBox",
                                     "AXSearchField", "AXSlider", "AXDisclosureTriangle", "AXIncrementor", "AXDockItem", "AXCell"]

    private static func attr<T>(_ e: AXUIElement, _ name: String) -> T? {
        var v: CFTypeRef?
        guard AXUIElementCopyAttributeValue(e, name as CFString, &v) == .success else { return nil }
        return v as? T
    }

    private static func frame(_ e: AXUIElement) -> CGRect? {
        guard let pv: AXValue = attr(e, kAXPositionAttribute), let sv: AXValue = attr(e, kAXSizeAttribute) else { return nil }
        var p = CGPoint.zero, s = CGSize.zero
        AXValueGetValue(pv, .cgPoint, &p); AXValueGetValue(sv, .cgSize, &s)
        return CGRect(origin: p, size: s)
    }

    private static func pressable(_ e: AXUIElement) -> Bool {
        var names: CFArray?
        guard AXUIElementCopyActionNames(e, &names) == .success, let list = names as? [String] else { return false }
        return list.contains(kAXPressAction)
    }

    /// The clickable element at a point (or its nearest clickable parent), with its frame.
    static func clickable(at p: CGPoint) -> CGRect? {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &hit) == .success, var e = hit else { return nil }
        for _ in 0..<3 {
            let role: String = attr(e, kAXRoleAttribute) ?? ""
            if roles.contains(role) || pressable(e), let f = frame(e), f.width > 2, f.height > 2,
               f.width < 700, f.height < 240 {   // skip big containers that happen to be pressable
                return f
            }
            guard let parent: AXUIElement = attr(e, kAXParentAttribute) else { break }
            e = parent
        }
        return nil
    }

    /// Centre of the nearest clickable element, or nil if the pointer is already on one or nothing is near.
    static func target(near p: CGPoint) -> CGPoint? {
        if clickable(at: p) != nil { return nil }
        var best: (d: CGFloat, f: CGRect)?
        var seen: [CGRect] = []
        for r in stride(from: CGFloat(10), through: radius, by: 10) {
            let n = max(8, Int(r / 6))
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi
                let q = CGPoint(x: p.x + r * CGFloat(cos(a)), y: p.y + r * CGFloat(sin(a)))
                guard let f = clickable(at: q), !seen.contains(f) else { continue }
                seen.append(f)
                let dx = max(f.minX - p.x, 0, p.x - f.maxX), dy = max(f.minY - p.y, 0, p.y - f.maxY)
                let d = hypot(dx, dy)
                if best == nil || d < best!.d { best = (d, f) }
            }
            if let b = best, b.d <= r { break }   // nothing further out can be closer
        }
        guard let b = best, b.d <= radius else { return nil }
        return CGPoint(x: b.f.midX, y: b.f.midY)
    }

    /// Chrome and Electron apps build their accessibility tree only when asked.
    static func wake(_ app: NSRunningApplication?) {
        guard let pid = app?.processIdentifier else { return }
        AXUIElementSetAttributeValue(AXUIElementCreateApplication(pid), "AXManualAccessibility" as CFString, kCFBooleanTrue)
    }
}

// MARK: - Controller → mouse

final class Engine {
    private var timer: Timer?
    private var last = CACurrentMediaTime()
    private var carry = CGPoint.zero        // sub-pixel pointer movement
    private var scrollCarry = CGPoint.zero  // sub-pixel scrolling
    private var prev: [String: Bool] = [:]
    private var held: CGMouseButton?        // mouse button currently held down by A or B
    private var lastClick: (button: CGMouseButton, time: CFTimeInterval, at: CGPoint, count: Int)?
    private var repeatKey: (code: CGKeyCode, flags: CGEventFlags, next: CFTimeInterval)?
    private var gameCache: [String: Bool] = [:]
    private var userGames = Prefs.userGames()
    // Snap: after the stick rests, glide to the nearest button.
    private var idleSince = CACurrentMediaTime()
    private var stickMoved = false          // only snap after Kumanda moved the pointer, never after the trackpad
    private var glide: (from: CGPoint, to: CGPoint, start: CFTimeInterval)?
    private var r3Combo = false             // R3 was part of the L3 + R3 on/off combo

    var onStateChange: (() -> Void)?
    private(set) var paused = false

    var controller: GCController? { GCController.current ?? GCController.controllers().first(where: { $0.extendedGamepad != nil }) }

    func start() {
        GCController.shouldMonitorBackgroundEvents = true
        let nc = NotificationCenter.default
        for n in [Notification.Name.GCControllerDidConnect, .GCControllerDidDisconnect, .GCControllerDidBecomeCurrent] {
            nc.addObserver(forName: n, object: nil, queue: .main) { [weak self] _ in
                log("controllers: \(GCController.controllers().map { $0.vendorName ?? "?" })")
                self?.releaseAll(); self?.onStateChange?()
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] n in
            Snap.wake(n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            self?.onStateChange?()
        }
        Snap.wake(NSWorkspace.shared.frontmostApplication)
        GCController.startWirelessControllerDiscovery {}
        timer = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func reloadGames() { userGames = Prefs.userGames(); gameCache = [:] }

    /// A game is in front: Horizon, anything the App Store files under Games, or the user's own list.
    func isGame(_ app: NSRunningApplication?) -> Bool {
        guard let app, let id = app.bundleIdentifier else { return false }
        if userGames.contains(id) { return true }
        if let c = gameCache[id] { return c }
        var game = id.hasPrefix("dev.horizon.game")
        if !game, let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary {
            let cat = (info["LSApplicationCategoryType"] as? String ?? "").lowercased()
            game = cat.contains("games") || (info["GCSupportsControllerUserInteraction"] as? Bool ?? false)
        }
        gameCache[id] = game
        return game
    }

    private func releaseAll() {
        if let b = held { Out.mouse(b, down: false, clicks: lastClick?.count ?? 1); held = nil }
        repeatKey = nil
        carry = .zero; scrollCarry = .zero
        glide = nil; stickMoved = false
    }

    private func edge(_ name: String, _ pressed: Bool) -> (down: Bool, up: Bool) {
        let was = prev[name] ?? false
        prev[name] = pressed
        return (pressed && !was, !pressed && was)
    }

    private func tick() {
        let now = CACurrentMediaTime()
        let dt = min(now - last, 0.05)
        last = now
        guard let pad = controller?.extendedGamepad else { return }

        // L3 + R3 together switches Kumanda on and off, even while it's off.
        let combo = pad.leftThumbstickButton?.isPressed == true && pad.rightThumbstickButton?.isPressed == true
        if combo { r3Combo = true }
        if edge("combo", combo).down {
            Prefs.enabled.toggle()
            log("toggled: \(Prefs.enabled)")
            releaseAll(); onStateChange?()
        }

        let nowPaused = !Prefs.enabled || isGame(NSWorkspace.shared.frontmostApplication) || !AXIsProcessTrusted()
        if nowPaused != paused {
            paused = nowPaused
            if paused { releaseAll() }
            onStateChange?()
        }
        let face = Face(pad, nintendo: Face.nintendoLayout(controller))
        if paused {
            // Keep edge state current so nothing fires the moment we resume.
            for (n, b) in buttons(pad, face) { _ = edge(n, b.isPressed) }
            return
        }

        let moving = movePointer(pad, dt: dt)
        let scrolling = scroll(pad, dt: dt)
        handleButtons(pad, face, now: now)
        snapIfResting(now: now, busy: moving || scrolling || held != nil)
    }

    // Once the stick has rested for a moment, glide onto the nearest button, if one is close.
    private func snapIfResting(now: CFTimeInterval, busy: Bool) {
        if busy { idleSince = now; glide = nil; return }
        if let g = glide {
            let t = min(1, (now - g.start) / 0.15)
            let e = 1 - pow(1 - t, 3)                      // ease out
            Out.move(to: CGPoint(x: g.from.x + (g.to.x - g.from.x) * e, y: g.from.y + (g.to.y - g.from.y) * e), dragging: nil)
            if t >= 1 { glide = nil }
            return
        }
        guard Prefs.snap, stickMoved, now - idleSince >= Prefs.snapDelay else { return }
        stickMoved = false
        let from = Out.location
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let to = Snap.target(near: from)
            DispatchQueue.main.async {
                // Only if nobody touched the pointer meanwhile.
                guard let self, let to, self.held == nil, hypot(Out.location.x - from.x, Out.location.y - from.y) < 1 else { return }
                self.glide = (from, to, CACurrentMediaTime())
            }
        }
    }

    // Stick → pointer. A curved response gives fine control near the centre and speed at the edge.
    @discardableResult
    private func movePointer(_ pad: GCExtendedGamepad, dt: Double) -> Bool {
        let x = Double(pad.leftThumbstick.xAxis.value), y = Double(pad.leftThumbstick.yAxis.value)
        let mag = min(1, hypot(x, y))
        let dead = 0.12
        guard mag > dead else { carry = .zero; return false }
        stickMoved = true
        let t = (mag - dead) / (1 - dead)
        var speed = (120 + 1500 * t * t) * Prefs.speed           // points per second
        speed *= 1 - 0.75 * Double(pad.leftTrigger.value)        // LT: precision
        speed *= 1 + 1.5 * Double(pad.rightTrigger.value)        // RT: fast
        carry.x += CGFloat(x / mag * speed * dt)
        carry.y -= CGFloat(y / mag * speed * dt)                 // screen y grows downward
        let step = CGPoint(x: carry.x.rounded(.towardZero), y: carry.y.rounded(.towardZero))
        guard step != .zero else { return true }
        carry.x -= step.x; carry.y -= step.y
        let old = Out.location
        Out.move(to: Out.clamp(CGPoint(x: old.x + step.x, y: old.y + step.y), from: old), dragging: held)
        return true
    }

    @discardableResult
    private func scroll(_ pad: GCExtendedGamepad, dt: Double) -> Bool {
        let x = Double(pad.rightThumbstick.xAxis.value), y = Double(pad.rightThumbstick.yAxis.value)
        let mag = min(1, hypot(x, y))
        guard mag > 0.15 else { scrollCarry = .zero; return false }
        let t = (mag - 0.15) / 0.85
        let speed = (150 + 2200 * t * t) * Prefs.speed
        scrollCarry.y += CGFloat(y / mag * speed * dt)           // stick up = scroll up
        scrollCarry.x -= CGFloat(x / mag * speed * dt)
        let dy = Int32(scrollCarry.y), dx = Int32(scrollCarry.x)
        guard dy != 0 || dx != 0 else { return true }
        scrollCarry.y -= CGFloat(dy); scrollCarry.x -= CGFloat(dx)
        Out.scroll(dy: dy, dx: dx)
        return true
    }

    private func buttons(_ pad: GCExtendedGamepad, _ f: Face) -> [(String, GCControllerButtonInput)] {
        var list: [(String, GCControllerButtonInput)] = [
            ("south", f.south), ("east", f.east), ("west", f.west), ("north", f.north),
            ("lb", pad.leftShoulder), ("rb", pad.rightShoulder), ("menu", pad.buttonMenu),
            ("up", pad.dpad.up), ("down", pad.dpad.down), ("left", pad.dpad.left), ("right", pad.dpad.right),
        ]
        if let o = pad.buttonOptions { list.append(("view", o)) }
        if let h = pad.buttonHome { list.append(("home", h)) }
        if let r3 = pad.rightThumbstickButton { list.append(("r3", r3)) }
        return list
    }

    private func handleButtons(_ pad: GCExtendedGamepad, _ f: Face, now: CFTimeInterval) {
        // Bottom face button = left click (hold to drag), right face button = right click,
        // whatever letter is printed on them.
        for (name, button, mb) in [("south", f.south, CGMouseButton.left), ("east", f.east, .right)] {
            let e = edge(name, button.isPressed)
            if e.down && held == nil {
                let at = Out.location
                var count = 1
                if let lc = lastClick, lc.button == mb, now - lc.time < NSEvent.doubleClickInterval, hypot(lc.at.x - at.x, lc.at.y - at.y) < 6 {
                    count = lc.count + 1
                }
                lastClick = (mb, now, at, count)
                held = mb
                Out.mouse(mb, down: true, clicks: count)
            } else if e.up && held == mb {
                Out.mouse(mb, down: false, clicks: lastClick?.count ?? 1)
                held = nil
            }
        }

        if edge("west", f.west.isPressed).down { Out.key(Key.escape) }
        if edge("north", f.north.isPressed).down { Out.key(Key.space, .maskCommand) }        // Raycast / Spotlight

        // Dictation: Home, or a press of the right stick (not when it was part of the on/off combo).
        if let h = pad.buttonHome, edge("home", h.isPressed).down { Dictation.toggle() }
        if let r3 = pad.rightThumbstickButton {
            let e = edge("r3", r3.isPressed)
            if e.down { r3Combo = pad.leftThumbstickButton?.isPressed == true }
            if e.up { if !r3Combo { Dictation.toggle() }; r3Combo = false }
        }
        if edge("menu", pad.buttonMenu.isPressed).down { Out.key(Key.ret) }
        if edge("lb", pad.leftShoulder.isPressed).down { Out.key(Key.left, .maskControl) }   // previous Space
        if edge("rb", pad.rightShoulder.isPressed).down { Out.key(Key.right, .maskControl) } // next Space
        if let v = pad.buttonOptions, edge("view", v.isPressed).down {
            NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Mission Control.app"), configuration: .init())
        }

        // D-pad = arrow keys, repeating while held like a keyboard.
        var anyArrow = false
        for (name, b, code) in [("up", pad.dpad.up, Key.up), ("down", pad.dpad.down, Key.down),
                                ("left", pad.dpad.left, Key.left), ("right", pad.dpad.right, Key.right)] {
            let e = edge(name, b.isPressed)
            if e.down { Out.key(code); repeatKey = (code, [], now + 0.4) }
            if b.isPressed { anyArrow = true }
            if e.up, repeatKey?.code == code { repeatKey = nil }
        }
        if !anyArrow { repeatKey = nil }
        if let r = repeatKey, now >= r.next {
            Out.key(r.code, r.flags)
            repeatKey?.next = now + 0.06
        }
    }
}

// MARK: - Menu bar

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let engine = Engine()
    var item: NSStatusItem!

    func applicationDidFinishLaunching(_ n: Notification) {
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu(); menu.delegate = self; item.menu = menu
        if !AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue(): true] as CFDictionary) {
            log("Accessibility not granted yet")
        }
        engine.onStateChange = { [weak self] in self?.refreshIcon() }
        engine.start()
        refreshIcon()
        // Accessibility can be granted while we run; pick it up without a restart.
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.refreshIcon() }
        log("Kumanda started")
    }

    func refreshIcon() {
        let connected = engine.controller != nil
        let active = connected && !engine.paused
        let name = !connected ? "gamecontroller" : active ? "gamecontroller.fill" : "gamecontroller"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Kumanda")
        img?.isTemplate = true
        item.button?.image = img
        item.button?.appearsDisabled = !active
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        // Opening a status menu doesn't activate us, so this is the app the user was in.
        let front = NSWorkspace.shared.frontmostApplication

        if let c = engine.controller {
            var title = c.vendorName ?? "Kontrolcü"
            if let b = c.battery, b.batteryState != .unknown || b.batteryLevel > 0 {
                title += " · pil %\(Int((b.batteryLevel * 100).rounded()))" + (b.batteryState == .charging ? " ⚡︎" : "")
            }
            menu.addItem(disabled(title))
        } else {
            menu.addItem(disabled("Kontrolcü bağlı değil"))
        }
        if !AXIsProcessTrusted() {
            menu.addItem(withTitle: "Erişilebilirlik izni ver…", action: #selector(openAX), keyEquivalent: "").target = self
        } else if Prefs.enabled && engine.isGame(front) {
            menu.addItem(disabled("Oyun önde, kontrolcü oyunda (\(front?.localizedName ?? ""))"))
        }
        menu.addItem(.separator())

        let on = menu.addItem(withTitle: "Etkin", action: #selector(toggleEnabled), keyEquivalent: "")
        on.target = self; on.state = Prefs.enabled ? .on : .off

        if let f = front, let id = f.bundleIdentifier, id != Bundle.main.bundleIdentifier {
            let g = menu.addItem(withTitle: "\(f.localizedName ?? id) açıkken durdur", action: #selector(toggleGame), keyEquivalent: "")
            g.target = self; g.representedObject = id
            g.state = Prefs.userGames().contains(id) ? .on : .off
            if engine.isGame(f) && !Prefs.userGames().contains(id) { g.state = .mixed; g.isEnabled = false; g.title = "\(f.localizedName ?? id): oyun olarak tanındı" }
        }

        let speed = NSMenuItem(title: "Hız", action: nil, keyEquivalent: "")
        let sm = NSMenu()
        for (t, v) in [("Yavaş", 0.6), ("Normal", 1.0), ("Hızlı", 1.5)] {
            let i = sm.addItem(withTitle: t, action: #selector(setSpeed(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = v; i.state = abs(Prefs.speed - v) < 0.01 ? .on : .off
        }
        speed.submenu = sm
        menu.addItem(speed)

        let snap = menu.addItem(withTitle: "Yakındaki düğmeye kay", action: #selector(toggleSnap), keyEquivalent: "")
        snap.target = self; snap.state = Prefs.snap ? .on : .off
        let delay = NSMenuItem(title: "Kayma beklemesi", action: nil, keyEquivalent: "")
        let dm = NSMenu()
        for v in [0.5, 1.0, 1.5, 2.0] {
            let i = dm.addItem(withTitle: String(format: "%.1f sn", v).replacingOccurrences(of: ".", with: ","), action: #selector(setSnapDelay(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = v; i.state = abs(Prefs.snapDelay - v) < 0.01 ? .on : .off
        }
        delay.submenu = dm; delay.isEnabled = Prefs.snap
        menu.addItem(delay)

        let layout = NSMenuItem(title: "Tuş düzeni", action: nil, keyEquivalent: "")
        let lm = NSMenu()
        let auto = Face.nintendoLayout(engine.controller) ? "Nintendo" : "Xbox"
        for (t, v) in [("Otomatik (şu an \(auto))", "auto"), ("Xbox / PlayStation: A altta", "xbox"), ("Nintendo / 8BitDo D modu: A sağda", "nintendo")] {
            let i = lm.addItem(withTitle: t, action: #selector(setLayout(_:)), keyEquivalent: "")
            i.target = self; i.representedObject = v; i.state = Prefs.layout == v ? .on : .off
        }
        layout.submenu = lm
        menu.addItem(layout)

        let keys = NSMenuItem(title: "Tuşlar", action: nil, keyEquivalent: "")
        let km = NSMenu()
        let dikte = Dictation.available ? "dikte aç / kapat" : "dikte (Dikte kurulu değil)"
        for line in ["Sol çubuk: imleç (durunca yakındaki düğmeye kayar)", "Sağ çubuk: kaydırma",
                     "Alttaki tuş: sol tık (basılı tut = sürükle)", "Sağdaki tuş: sağ tık",
                     "Soldaki tuş: Esc", "Üstteki tuş: ⌘ Boşluk (Raycast)", "Menü ☰: Enter", "Görünüm ⧉: Mission Control",
                     "LB / RB: önceki / sonraki masaüstü", "Yön tuşları: ok tuşları",
                     "LT basılı: hassas, RT basılı: hızlı", "Sağ çubuğa bas ya da Home: \(dikte)",
                     "İki çubuğa birlikte bas: aç / kapat"] {
            km.addItem(disabled(line))
        }
        keys.submenu = km
        menu.addItem(keys)

        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Girişte başlat", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self; login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Kumanda'dan çık", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private func disabled(_ t: String) -> NSMenuItem { let i = NSMenuItem(title: t, action: nil, keyEquivalent: ""); i.isEnabled = false; return i }

    @objc func toggleEnabled() { Prefs.enabled.toggle(); refreshIcon() }
    @objc func setSpeed(_ s: NSMenuItem) { Prefs.speed = s.representedObject as? Double ?? 1 }
    @objc func toggleSnap() { Prefs.snap.toggle() }
    @objc func setSnapDelay(_ s: NSMenuItem) { Prefs.snapDelay = s.representedObject as? Double ?? 1 }
    @objc func setLayout(_ s: NSMenuItem) { Prefs.layout = s.representedObject as? String ?? "auto" }
    @objc func toggleGame(_ s: NSMenuItem) {
        guard let id = s.representedObject as? String else { return }
        Prefs.setUserGame(id, s.state != .on)
        engine.reloadGames(); refreshIcon()
    }
    @objc func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else { try SMAppService.mainApp.register() }
        } catch { log("login item: \(error)") }
    }
    @objc func openAX() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}

let app = NSApplication.shared
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
