//
//  UpdaterEnvironmentKey.swift
//  Applite
//
//  Created by Milán Várady on 2026.06.24.
//

import SwiftUI
import Sparkle

/// Exposes the app-wide Sparkle ``SPUUpdater`` through the environment so views
/// (e.g. the "Applite" self-card) can reuse the single app-level updater instead
/// of constructing their own ``SPUStandardUpdaterController``.
///
/// Optional because the macOS 14 deployment target rules out the `@Entry` macro
/// and there is no sensible non-nil default updater.
private struct UpdaterEnvironmentKey: EnvironmentKey {
    static let defaultValue: SPUUpdater? = nil
}

extension EnvironmentValues {
    var updater: SPUUpdater? {
        get { self[UpdaterEnvironmentKey.self] }
        set { self[UpdaterEnvironmentKey.self] = newValue }
    }
}
