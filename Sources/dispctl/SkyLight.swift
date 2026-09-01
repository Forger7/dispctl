// Binding for the private display-configuration API.
//
// SkyLight.framework exports SLSConfigureDisplayEnabled; CoreGraphics re-exports it as
// CGSConfigureDisplayEnabled. It is what WindowServer uses to bring a display in and out
// of the desktop layout. Undocumented and absent from the public SDK, so it is resolved at
// runtime rather than linked, and we fail loudly if a future macOS moves it.

import CoreGraphics
import Foundation

typealias ConfigureDisplayEnabled =
    @convention(c) (CGDisplayConfigRef?, CGDirectDisplayID, Bool) -> CGError

enum SkyLight {
    private static let candidates = [
        ("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", "SLSConfigureDisplayEnabled"),
        ("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", "CGSConfigureDisplayEnabled"),
    ]

    /// Resolves the configuration symbol, preferring SkyLight's own export.
    static func configureDisplayEnabled() throws -> ConfigureDisplayEnabled {
        for (path, symbol) in candidates {
            guard let handle = dlopen(path, RTLD_LAZY) else { continue }
            if let sym = dlsym(handle, symbol) {
                return unsafeBitCast(sym, to: ConfigureDisplayEnabled.self)
            }
        }
        throw DispctlError.symbolUnavailable
    }

    /// Enables or disables a display inside a single configuration transaction.
    static func setEnabled(_ display: CGDirectDisplayID, _ enabled: Bool, permanent: Bool) throws {
        let configure = try configureDisplayEnabled()

        var config: CGDisplayConfigRef?
        guard CGBeginDisplayConfiguration(&config) == .success, let config else {
            throw DispctlError.configurationFailed("CGBeginDisplayConfiguration")
        }

        let result = configure(config, display, enabled)
        guard result == .success else {
            CGCancelDisplayConfiguration(config)
            throw DispctlError.configureRejected(result)
        }

        let scope: CGConfigureOption = permanent ? .permanently : .forSession
        guard CGCompleteDisplayConfiguration(config, scope) == .success else {
            throw DispctlError.configurationFailed("CGCompleteDisplayConfiguration")
        }
    }
}

enum DispctlError: Error, CustomStringConvertible {
    case symbolUnavailable
    case configurationFailed(String)
    case configureRejected(CGError)
    case noMatch(String)
    case ambiguous(String, Int)
    case lastActiveDisplay

    var description: String {
        switch self {
        case .symbolUnavailable:
            return """
            neither SLSConfigureDisplayEnabled nor CGSConfigureDisplayEnabled could be resolved.
            A macOS update may have moved the symbol. Check with:
              dyld_info -exports /System/Library/PrivateFrameworks/SkyLight.framework/Versions/A/SkyLight | grep -i DisplayEnabled
            """
        case let .configurationFailed(call):
            return "\(call) failed"
        case let .configureRejected(err):
            return "ConfigureDisplayEnabled returned CGError \(err.rawValue)"
        case let .noMatch(query):
            return "no display matches '\(query)' (try: dispctl list)"
        case let .ambiguous(query, count):
            return "'\(query)' matches \(count) displays; use a full or longer UUID prefix"
        case .lastActiveDisplay:
            return "refusing to disable the only remaining active display"
        }
    }
}
