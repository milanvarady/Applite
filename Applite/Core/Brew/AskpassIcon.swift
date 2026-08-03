//
//  AskpassIcon.swift
//  Applite
//
//  Created by Milán Várady on 2026.08.03.
//

import AppKit
import OSLog

/// Writes Applite's app icon to its Application Support folder so the askpass dialog
/// (`askpass.js`) can display it — making it clear which app is requesting the
/// password. The dialog runs in a separate `osascript` process and can't reach
/// Applite's bundle, so we hand it the icon via this file instead.
enum AskpassIcon {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "AskpassIcon")

    /// Location the icon is written to. Must match the path `askpass.js` computes
    /// (Application Support → `Applite/prompt-icon.png`).
    static let iconURL = AppPaths.applicationSupport.appending(path: "prompt-icon.png")

    /// Refreshes the on-disk icon PNG. Reads the app icon on the main actor (an AppKit
    /// requirement), then encodes and writes it off the main thread so launch isn't
    /// blocked. Best-effort: on failure the dialog falls back to the system caution
    /// icon. Call once at launch.
    @MainActor
    static func write() {
        guard let tiff = (NSApplication.shared.applicationIconImage ?? NSImage()).tiffRepresentation else {
            Self.logger.error("Failed to read app icon for askpass dialog")
            return
        }

        Task.detached(priority: .utility) {
            encodeAndWrite(tiff: tiff)
        }
    }

    /// Encodes the TIFF data to PNG and writes it to ``iconURL``. Runs off the main
    /// actor — it touches no AppKit UI state, only the `Data` handed in.
    private static func encodeAndWrite(tiff: Data) {
        guard let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            Self.logger.error("Failed to encode app icon PNG for askpass dialog")
            return
        }

        do {
            try AppPaths.createApplicationSupportIfNeeded()
            try png.write(to: iconURL)
        } catch {
            Self.logger.error("Failed to write askpass icon: \(error.localizedDescription)")
        }
    }
}
