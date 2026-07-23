//
//  CaskProgressState.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.31.
//

import Foundation

/// Cask progress state when installing, updating or uninstalling
enum CaskProgressState: Equatable, Hashable {
    case idle
    case busy(withTask: String)
    case downloading(percent: Double)
    case success
    case failed(output: String)

    /// A failed operation the user hasn't dismissed yet.
    var isFailed: Bool {
        if case .failed = self { return true }
        return false
    }

    /// An operation that is queued or running (as opposed to idle/succeeded/failed). Drives whether
    /// a card is a live task for the quit prompt, so lingering failed cards don't block termination.
    var isActive: Bool {
        switch self {
        case .busy, .downloading: return true
        case .idle, .success, .failed: return false
        }
    }
}
