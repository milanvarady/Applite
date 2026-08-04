//
//  UpdaterViewModel.swift
//  Applite
//
//  Created by Milán Várady on 2026.08.04.
//

import Foundation
import Sparkle

/// Bridges Sparkle's `SPUUpdater` into SwiftUI's observation system.
///
/// `SPUUpdater` is a KVO-compliant `NSObject`, not `@Observable`, so SwiftUI can't track it: a view
/// that reads `updater.automaticallyChecksForUpdates` renders once with whatever the value was then
/// and never hears about a change. The old code worked around that by copying the values into
/// `@State` in `init` — which is a snapshot, so the toggles drifted out of sync whenever anything
/// else moved them (Sparkle's own first-launch "check automatically?" prompt does exactly that)
/// (P3-19). And nothing observed `canCheckForUpdates` at all, so "Check for Updates" stayed live
/// during a check and repeat clicks stacked up with no feedback (P3-18).
///
/// KVO → `@Observable` rather than Combine, per the project's convention.
@MainActor
@Observable
final class UpdaterViewModel {
    /// False while a check is already running. Sparkle documents this as the property to bind a
    /// "Check for Updates" control's enabled state to.
    private(set) var canCheckForUpdates: Bool

    /// Whether the *option* to auto-download may be offered. Sparkle derives this from
    /// `automaticallyChecksForUpdates` **and** the host's `SUAllowsAutomaticUpdates` Info.plist key,
    /// so it's the correct gate — the previous hand-rolled `!automaticallyChecksForUpdates` missed
    /// the plist half.
    private(set) var allowsAutomaticUpdates: Bool

    var automaticallyChecksForUpdates: Bool {
        didSet { write(automaticallyChecksForUpdates, to: \.automaticallyChecksForUpdates) }
    }

    var automaticallyDownloadsUpdates: Bool {
        didSet { write(automaticallyDownloadsUpdates, to: \.automaticallyDownloadsUpdates) }
    }

    private let updater: SPUUpdater
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []

    init(updater: SPUUpdater) {
        self.updater = updater
        self.canCheckForUpdates = updater.canCheckForUpdates
        self.allowsAutomaticUpdates = updater.allowsAutomaticUpdates
        self.automaticallyChecksForUpdates = updater.automaticallyChecksForUpdates
        self.automaticallyDownloadsUpdates = updater.automaticallyDownloadsUpdates

        observations = [
            observe(\.canCheckForUpdates) { $0.canCheckForUpdates = $1 },
            observe(\.allowsAutomaticUpdates) { $0.allowsAutomaticUpdates = $1 },
            observe(\.automaticallyChecksForUpdates) { $0.automaticallyChecksForUpdates = $1 },
            observe(\.automaticallyDownloadsUpdates) { $0.automaticallyDownloadsUpdates = $1 }
        ]
    }

    func checkForUpdates() {
        updater.checkForUpdates()
    }

    /// Mirrors one KVO-compliant `Bool` into our observable copy.
    ///
    /// Only `change.newValue` crosses the boundary — a `Bool`, not the updater — because the KVO
    /// callback is nonisolated while these Sparkle properties are documented main-thread-only.
    private func observe(
        _ keyPath: KeyPath<SPUUpdater, Bool>,
        apply: @escaping @MainActor @Sendable (UpdaterViewModel, Bool) -> Void
    ) -> NSKeyValueObservation {
        updater.observe(keyPath, options: [.new]) { [weak self] _, change in
            guard let newValue = change.newValue else { return }
            Task { @MainActor in
                guard let self else { return }
                apply(self, newValue)
            }
        }
    }

    /// Writes a UI-driven change back to Sparkle, skipping the no-op write that mirroring a KVO
    /// change back would otherwise cause.
    private func write(_ value: Bool, to keyPath: ReferenceWritableKeyPath<SPUUpdater, Bool>) {
        guard updater[keyPath: keyPath] != value else { return }
        updater[keyPath: keyPath] = value
    }
}
