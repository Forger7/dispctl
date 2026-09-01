// Display enumeration, identity and persisted state.

import AppKit
import CoreGraphics
import Foundation

struct Display {
    let id: CGDirectDisplayID
    let uuid: String
    let name: String
    let isActive: Bool
    /// True when the display is remembered as disabled but the system no longer reports it.
    let isGhost: Bool

    var shortUUID: String { String(uuid.prefix(8)) }
    var status: String { isGhost ? "off*" : (isActive ? "on" : "off") }
}

enum Displays {
    // MARK: - Enumeration

    static func online() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetOnlineDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    static func uuid(of id: CGDirectDisplayID) -> String {
        guard let ref = CGDisplayCreateUUIDFromDisplayID(id) else { return "-" }
        return CFUUIDCreateString(nil, ref.takeRetainedValue()) as String? ?? "-"
    }

    /// NSScreen only reports active displays, so names are best-effort.
    private static func names() -> [CGDirectDisplayID: String] {
        var map: [CGDirectDisplayID: String] = [:]
        for screen in NSScreen.screens {
            let key = NSDeviceDescriptionKey("NSScreenNumber")
            if let number = screen.deviceDescription[key] as? NSNumber {
                map[number.uint32Value] = screen.localizedName
            }
        }
        return map
    }

    /// All displays the system reports, plus any we disabled that it has since stopped reporting.
    static func all() -> [Display] {
        let nameMap = names()
        let remembered = State.load()
        let onlineIDs = online()

        var displays = onlineIDs.sorted().map { id in
            let uuid = uuid(of: id)
            return Display(
                id: id,
                uuid: uuid,
                name: nameMap[id] ?? remembered[uuid]?.name ?? "Unknown display",
                isActive: CGDisplayIsActive(id) != 0,
                isGhost: false
            )
        }

        let known = Set(onlineIDs)
        for (uuid, entry) in remembered where !known.contains(entry.id) {
            displays.append(
                Display(id: entry.id, uuid: uuid, name: entry.name, isActive: false, isGhost: true)
            )
        }
        return displays
    }

    // MARK: - Resolution

    /// Accepts a UUID prefix, a numeric display id, or a case-insensitive name substring.
    /// UUIDs are the stable choice: numeric ids are reassigned across reboots and replugs.
    static func resolve(_ query: String) throws -> Display {
        let needle = query.lowercased()
        let matches = all().filter { display in
            display.uuid.lowercased().hasPrefix(needle)
                || String(display.id) == query
                || display.name.lowercased().contains(needle)
        }

        switch matches.count {
        case 1: return matches[0]
        case 0: throw DispctlError.noMatch(query)
        default: throw DispctlError.ambiguous(query, matches.count)
        }
    }

    /// Reconnecting must work even when the system has stopped reporting the display and we
    /// have no remembered entry for it. A raw numeric id is the last-resort escape hatch.
    static func resolveForReconnect(_ query: String) throws -> Display {
        if let display = try? resolve(query) { return display }
        if let id = CGDirectDisplayID(query) {
            return Display(id: id, uuid: uuid(of: id), name: "display \(id)", isActive: false, isGhost: true)
        }
        throw DispctlError.noMatch(query)
    }

    // MARK: - Mutation

    /// Returns false when the display was already in the requested state.
    @discardableResult
    static func setEnabled(_ display: Display, _ enabled: Bool, permanent: Bool) throws -> Bool {
        // WindowServer rejects a no-op transaction, so short-circuit rather than surface an
        // error. Repeat invocations should be safe to bind to a key or a script.
        if display.isActive == enabled, !display.isGhost {
            reconcileState(display, enabled: enabled)
            return false
        }

        if !enabled {
            let activeCount = all().filter(\.isActive).count
            if activeCount <= 1, display.isActive { throw DispctlError.lastActiveDisplay }
        }

        try SkyLight.setEnabled(display.id, enabled, permanent: permanent)
        reconcileState(display, enabled: enabled)
        return true
    }

    /// Remember disabled displays: once off, the system may stop listing them entirely, and we
    /// would otherwise have no id left to switch them back on with.
    private static func reconcileState(_ display: Display, enabled: Bool) {
        var state = State.load()
        if enabled {
            // Purge by id as well as UUID: a blind reconnect by raw id has no UUID to key on,
            // since the system was not reporting the display at the time of the call.
            state.removeValue(forKey: display.uuid)
            state = state.filter { $0.value.id != display.id }
        } else {
            state[display.uuid] = State.Entry(id: display.id, name: display.name)
        }
        State.save(state)
    }
}

// MARK: - Persisted state

enum State {
    struct Entry: Codable {
        let id: CGDirectDisplayID
        let name: String
    }

    static var url: URL {
        let base = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local/state/dispctl", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("disabled.json")
    }

    static func load() -> [String: Entry] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        if let decoded = try? JSONDecoder().decode([String: Entry].self, from: data) {
            return decoded
        }
        // Pre-0.1 files stored a bare display id per UUID. Migrate rather than discard:
        // dropping this state would strand a disabled display with no id to switch it back on.
        if let legacy = try? JSONDecoder().decode([String: CGDirectDisplayID].self, from: data) {
            return legacy.mapValues { Entry(id: $0, name: "Unknown display") }
        }
        return [:]
    }

    static func save(_ state: [String: Entry]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(state) { try? data.write(to: url) }
    }
}
