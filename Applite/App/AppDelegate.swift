//
//  AppDelegate.swift
//  Applite
//
//  Created by Milán Várady on 2025.01.01.
//

import Foundation
import AppKit

@MainActor
final class ApplicationDelegate: NSObject, NSApplicationDelegate {
    /// Set by `AppliteApp` so termination can stop running brew tasks.
    weak var caskManager: CaskManager?
    var reopenMainWindow: (() -> Void)?

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard let reopenMainWindow else { return true }
        reopenMainWindow()
        return false
    }

    /// Write the app icon to the fixed path the askpass dialog reads, so the sudo
    /// password prompt shows Applite's icon. See ``AskpassIcon``.
    func applicationDidFinishLaunching(_ notification: Notification) {
        AskpassIcon.write()
    }

    // Close app after last window closed
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// Stop any running brew tasks before quitting so no brew/curl processes are
    /// left running after the app exits.
    ///
    /// We deliberately do not show a quit confirmation here: an `NSAlert` is itself
    /// a window, so when quitting by closing the last window its dismissal re-fires
    /// termination and the dialog loops. There's no clean way around that today —
    /// revisit if SwiftUI gains native control over termination.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Only prompt for genuinely-running work — dismissed-or-not failed cards linger in
        // `activeTasks` (so their error stays reachable) but must not block quitting.
        guard let caskManager,
              caskManager.activeTasks.contains(where: { $0.viewModel.progressState.isActive })
        else { return .terminateNow }

        Task { @MainActor in
            await caskManager.cancelAllAndWait()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }
}
