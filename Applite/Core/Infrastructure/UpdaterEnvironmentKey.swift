//
//  UpdaterEnvironmentKey.swift
//  Applite
//
//  Created by Milán Várady on 2026.06.24.
//

import SwiftUI
import Sparkle

/// Exposes the app-wide ``UpdaterViewModel`` through the environment so views (e.g. the "Applite"
/// self-card) can reuse the single app-level updater instead of constructing their own
/// ``SPUStandardUpdaterController``.
///
/// Carries the view model rather than the raw `SPUUpdater` so every consumer observes the same
/// live state — `SPUUpdater` itself is KVO-only and invisible to SwiftUI (P3-18/P3-19).
///
/// Optional because the macOS 14 deployment target rules out the `@Entry` macro
/// and there is no sensible non-nil default updater.
private struct UpdaterEnvironmentKey: EnvironmentKey {
    static let defaultValue: UpdaterViewModel? = nil
}

extension EnvironmentValues {
    var updater: UpdaterViewModel? {
        get { self[UpdaterEnvironmentKey.self] }
        set { self[UpdaterEnvironmentKey.self] = newValue }
    }
}
