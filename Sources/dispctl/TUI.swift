// A small full-screen picker. Hand-rolled against termios and ANSI escapes: the list is
// never more than a handful of rows, which does not justify a curses dependency.

import Darwin
import Foundation

enum TUI {
    private static var savedTermios = termios()

    // MARK: - Terminal setup

    private static func enterRawMode() {
        tcgetattr(STDIN_FILENO, &savedTermios)
        var raw = savedTermios
        // ISIG off so Ctrl-C arrives as a byte and we can restore the terminal ourselves.
        raw.c_lflag &= ~tcflag_t(ECHO | ICANON | ISIG)
        withUnsafeMutableBytes(of: &raw.c_cc) { buffer in
            buffer[Int(VMIN)] = 1
            buffer[Int(VTIME)] = 0
        }
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &raw)
        write("\u{1B}[?1049h\u{1B}[?25l")  // alternate screen, hide cursor
    }

    private static func leaveRawMode() {
        write("\u{1B}[?25h\u{1B}[?1049l")  // show cursor, leave alternate screen
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &savedTermios)
    }

    private static func write(_ string: String) {
        FileHandle.standardOutput.write(Data(string.utf8))
    }

    // MARK: - Input

    private enum Key { case up, down, toggle, refresh, quit, other }

    private static func readKey() -> Key {
        var byte: UInt8 = 0
        guard read(STDIN_FILENO, &byte, 1) == 1 else { return .quit }

        switch byte {
        case 0x1B:  // escape: either a bare Esc or an arrow sequence
            var seq = [UInt8](repeating: 0, count: 2)
            guard read(STDIN_FILENO, &seq, 2) == 2, seq[0] == UInt8(ascii: "[") else { return .quit }
            switch seq[1] {
            case UInt8(ascii: "A"): return .up
            case UInt8(ascii: "B"): return .down
            default: return .other
            }
        case UInt8(ascii: "k"): return .up
        case UInt8(ascii: "j"): return .down
        case UInt8(ascii: " "), 0x0D: return .toggle
        case UInt8(ascii: "r"): return .refresh
        case UInt8(ascii: "q"), 0x03: return .quit
        default: return .other
        }
    }

    // MARK: - Rendering

    private static func render(_ displays: [Display], selected: Int, message: String, permanent: Bool) {
        var out = "\u{1B}[H\u{1B}[2J"  // home, clear
        out += "\u{1B}[1m dispctl\u{1B}[0m \u{1B}[2m— \(permanent ? "persistent" : "session-only") changes\u{1B}[0m\n\n"

        for (index, display) in displays.enumerated() {
            let marker = display.isActive ? "\u{1B}[32m●\u{1B}[0m" : "\u{1B}[31m○\u{1B}[0m"
            let name = display.name.padding(toLength: 22, withPad: " ", startingAt: 0)
            let ghost = display.isGhost ? " \u{1B}[2m(not reported by system)\u{1B}[0m" : ""
            let row = " \(marker) \(name) \u{1B}[2m\(display.shortUUID)  id \(display.id)\u{1B}[0m\(ghost)"

            out += index == selected ? "\u{1B}[7m›\u{1B}[0m\(row)\n" : " \(row)\n"
        }

        out += "\n\u{1B}[2m ↑/↓ or j/k move · space toggles · r refreshes · q quits\u{1B}[0m\n"
        if !message.isEmpty { out += "\n \(message)\n" }
        write(out)
    }

    // MARK: - Loop

    static func run(permanent: Bool) {
        enterRawMode()
        defer { leaveRawMode() }

        var displays = Displays.all()
        var selected = 0
        var message = ""

        while true {
            if displays.isEmpty {
                write("\u{1B}[H\u{1B}[2J no displays found\n")
                _ = readKey()
                return
            }
            selected = min(selected, displays.count - 1)
            render(displays, selected: selected, message: message, permanent: permanent)

            switch readKey() {
            case .quit:
                return
            case .up:
                selected = (selected - 1 + displays.count) % displays.count
                message = ""
            case .down:
                selected = (selected + 1) % displays.count
                message = ""
            case .refresh:
                displays = Displays.all()
                message = ""
            case .toggle:
                let target = displays[selected]
                do {
                    try Displays.setEnabled(target, !target.isActive, permanent: permanent)
                    message = "\u{1B}[32m✓\u{1B}[0m \(target.name) → \(target.isActive ? "disconnected" : "connected")"
                } catch {
                    message = "\u{1B}[31m✗\u{1B}[0m \(error)"
                }
                // Let WindowServer settle before re-reading the layout.
                Thread.sleep(forTimeInterval: 0.6)
                displays = Displays.all()
            case .other:
                message = ""
            }
        }
    }
}
