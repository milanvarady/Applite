//
//  AlertManager.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.26.
//

import Foundation
import OSLog
import SwiftUI

/// One alert's content: what to say, and which buttons to offer.
struct AppAlert: Identifiable {
    /// An alert button. `handler` runs before the alert closes; SwiftUI dismisses on any button tap.
    struct Action: Identifiable {
        let id = UUID()
        let title: LocalizedStringKey
        let role: ButtonRole?
        let handler: (() -> Void)?

        init(_ title: LocalizedStringKey, role: ButtonRole? = nil, handler: (() -> Void)? = nil) {
            self.title = title
            self.role = role
            self.handler = handler
        }

        /// Plain acknowledgment. Carries `.cancel` so Esc closes the alert too.
        /// Main-actor isolated because `handler` is not `Sendable` — alerts are UI, built and
        /// presented on the main actor only.
        @MainActor static let ok = Action("OK", role: .cancel)
    }

    let id = UUID()
    let title: LocalizedStringKey
    let message: String
    let actions: [Action]

    /// Same words twice is noise, not news — see `AlertManager.enqueue`.
    func hasSameContent(as other: AppAlert) -> Bool {
        title == other.title && message == other.message
    }
}

/// The alert surface for **one window**: a queue of alerts presented one at a time by the
/// `.alertManager(_:)` modifier at that window's root.
///
/// Per-window, root-level ownership is the point (F5/P3-5). The shared instance used to be bound
/// inside `AppView` — i.e. once per cask card in the grid — so a single failure flipped an
/// `isPresented` that dozens of live views were watching: SwiftUI presented from an arbitrary card,
/// or from none at all on a screen that mounts no cards (the migration screen). `show()` also
/// overwrote whatever was on screen, so a batch's "these failed" summary could be silently replaced
/// by the next failure. Queueing fixes the second half of that.
@MainActor
@Observable
final class AlertManager {
    /// Bound by `.alertManager(_:)`. Stored rather than derived from `current` so the content can
    /// outlive the dismissal animation — SwiftUI re-reads it while the alert fades out, and clearing
    /// it there flashes an empty dialog.
    var isPresented: Bool = false

    /// Content of the alert on screen, or of the one that just closed.
    private(set) var current: AppAlert?

    /// Raised while another alert was on screen; presented in turn as each is dismissed.
    private(set) var pending: [AppAlert] = []

    /// Cap on queued alerts. A failing batch can raise a burst of them; past this we drop and log
    /// rather than marching the user through an unbounded stack of dialogs.
    static let maxPending = 3

    /// SwiftUI ignores an alert raised while the previous one is still animating away, so a
    /// presentation that lands inside this window of a dismissal waits its turn instead.
    private static let settleDelay: Duration = .milliseconds(350)

    private let clock = ContinuousClock()
    private var lastDismissal: ContinuousClock.Instant?
    private var drainTask: Task<Void, Never>?

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier!,
        category: String(describing: AlertManager.self)
    )

    /// Presents an alert, or queues it if one is already up.
    func show(
        title: LocalizedStringKey,
        message: String = "",
        actions: [AppAlert.Action] = [.ok]
    ) {
        enqueue(
            AppAlert(
                title: title,
                message: message.limitedToLines(20, suffix: "..."),
                // An alert with no buttons can't be dismissed — always leave a way out.
                actions: actions.isEmpty ? [.ok] : actions
            )
        )
        presentNext()
    }

    /// Presents an alert describing `error`.
    func show(
        error: Error,
        title: LocalizedStringKey,
        actions: [AppAlert.Action] = [.ok]
    ) {
        show(title: title, message: error.localizedDescription, actions: actions)
    }

    /// Called by `.alertManager(_:)` whenever the presentation flag drops — by a button tap, by Esc,
    /// or by SwiftUI itself — so the queue drains from one place regardless of how the alert closed.
    func alertDismissed() {
        lastDismissal = clock.now
        presentNext()
    }

    private func enqueue(_ alert: AppAlert) {
        // Every cask in a failing batch reporting the same broken brew should be one alert, not N.
        let onScreen = isPresented ? current : nil
        let alreadyQueued = ([onScreen].compactMap { $0 } + pending).contains { $0.hasSameContent(as: alert) }
        guard !alreadyQueued else { return }

        guard pending.count < Self.maxPending else {
            Self.logger.error("Dropping alert, queue full: \(String(describing: alert.title)) — \(alert.message)")
            return
        }

        pending.append(alert)
    }

    /// The one path to the screen. Every alert goes through here — whether it arrived while the
    /// window was clear or behind three others — so the settle window after a dismissal is honored
    /// in all cases, not just when a queue had already formed.
    private func presentNext() {
        guard !isPresented, !pending.isEmpty, drainTask == nil else { return }

        // Straight to the screen unless a dismissal is still animating out.
        guard let sinceDismissal = lastDismissal?.duration(to: clock.now),
              sinceDismissal < Self.settleDelay else {
            current = pending.removeFirst()
            isPresented = true
            return
        }

        drainTask = Task {
            try? await Task.sleep(for: Self.settleDelay - sinceDismissal)
            drainTask = nil
            presentNext()
        }
    }
}
