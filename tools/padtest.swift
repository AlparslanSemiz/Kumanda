// Controller tester: prints every button press macOS sees from a game controller.
// Handy when a button "does nothing": it shows whether macOS gets the press at all.
//   swift tools/padtest.swift
// Runs for two minutes, or stop it with Ctrl+C.
import Foundation
import GameController

setvbuf(stdout, nil, _IONBF, 0)
GCController.shouldMonitorBackgroundEvents = true

func hook(_ c: GCController) {
    print("Controller: \(c.vendorName ?? "?") | \(c.productCategory)")
    guard let g = c.extendedGamepad else { print("Not an extended gamepad, no buttons to watch."); return }
    let buttons: [(String, GCControllerButtonInput?)] = [
        ("A", g.buttonA), ("B", g.buttonB), ("X", g.buttonX), ("Y", g.buttonY),
        ("L1", g.leftShoulder), ("R1", g.rightShoulder), ("L2", g.leftTrigger), ("R2", g.rightTrigger),
        ("L3", g.leftThumbstickButton), ("R3", g.rightThumbstickButton),
        ("Menu", g.buttonMenu), ("Options", g.buttonOptions), ("Home", g.buttonHome)]
    for (name, button) in buttons {
        guard let button else { print("\(name): not reported by this controller"); continue }
        button.pressedChangedHandler = { _, _, pressed in print("\(name) \(pressed ? "pressed" : "released")") }
    }
    print("Ready. Press some buttons.")
}

NotificationCenter.default.addObserver(forName: .GCControllerDidConnect, object: nil, queue: .main) { hook($0.object as! GCController) }
GCController.controllers().forEach(hook)
GCController.startWirelessControllerDiscovery {}
DispatchQueue.main.asyncAfter(deadline: .now() + 120) { exit(0) }
RunLoop.main.run()
