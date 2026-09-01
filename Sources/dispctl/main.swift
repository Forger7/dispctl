import Foundation

let version = "0.1.0"

let usage = """
dispctl \(version) — connect and disconnect macOS displays from the terminal

usage:
  dispctl                        interactive picker
  dispctl list [--json]          list displays
  dispctl off <display>          disconnect (macOS treats it as unplugged)
  dispctl on <display>           reconnect
  dispctl toggle <display>       flip whichever way it is now

  <display> is a UUID prefix, a numeric id, or part of the display name.
  Prefer UUIDs: numeric ids are reassigned across reboots and replugs.

options:
  --session    revert at logout instead of persisting the change
  --version    print version

examples:
  dispctl off F288252F           hand a monitor to another device on a second input
  dispctl on F288252F            take it back
  dispctl on 3                   last resort: reconnect by raw id when macOS has
                                 stopped reporting the display entirely
"""

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("dispctl: \(message)\n".utf8))
    exit(1)
}

func printList(json: Bool) {
    let displays = Displays.all()

    if json {
        let payload = displays.map {
            ["id": .init($0.id), "uuid": .init($0.uuid), "name": .init($0.name),
             "active": .init($0.isActive), "reported": .init(!$0.isGhost)] as [String: JSONValue]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(payload), let text = String(data: data, encoding: .utf8) {
            print(text)
        }
        return
    }

    guard !displays.isEmpty else { print("no displays found"); return }
    let width = max(4, displays.map(\.name.count).max() ?? 4)
    print("ID    STATUS  UUID                                  NAME")
    for display in displays {
        let id = String(display.id).padding(toLength: 6, withPad: " ", startingAt: 0)
        let status = display.status.padding(toLength: 8, withPad: " ", startingAt: 0)
        let name = display.name.padding(toLength: width, withPad: " ", startingAt: 0)
        print("\(id)\(status)\(display.uuid)  \(name)")
    }
    if displays.contains(where: \.isGhost) {
        print("\n* disabled and no longer reported by the system; dispctl remembers it")
    }
}

// MARK: - Entry point

var arguments = Array(CommandLine.arguments.dropFirst())
let permanent = !arguments.contains("--session")
let wantsJSON = arguments.contains("--json")
arguments.removeAll { $0 == "--session" || $0 == "--json" }

guard let command = arguments.first else {
    TUI.run(permanent: permanent)
    exit(0)
}

func target() throws -> Display {
    guard arguments.count > 1 else { fail("\(command) needs a display (try: dispctl list)") }
    return command == "on"
        ? try Displays.resolveForReconnect(arguments[1])
        : try Displays.resolve(arguments[1])
}

do {
    switch command {
    case "list", "ls":
        printList(json: wantsJSON)

    case "off", "on", "toggle":
        let display = try target()
        let enable = command == "toggle" ? !display.isActive : command == "on"
        let changed = try Displays.setEnabled(display, enable, permanent: permanent)
        let state = enable ? "connected" : "disconnected"
        print(changed
            ? "\(display.name) [\(display.shortUUID)] → \(state)"
            : "\(display.name) [\(display.shortUUID)] already \(state)")

    case "--version", "-v", "version":
        print(version)

    case "help", "--help", "-h":
        print(usage)

    default:
        fail("unknown command '\(command)'\n\n\(usage)")
    }
} catch {
    fail("\(error)")
}
