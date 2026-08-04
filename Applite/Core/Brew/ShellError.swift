//
//  ShellError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

enum ShellError: LocalizedError {
    case askpassNotFound
    case outputDecodingFailed
    case coundtGetHomeDirectory
    case nonZeroExit(command: String, exitCode: Int32, output: String)
    case timedOut(command: String, seconds: Duration)

    /// Reaches the user as an alert body (`AlertManager.show(error:title:)`) and as the text on a
    /// failed app card, so every case is localized. The interpolated command/output stay verbatim —
    /// they're brew's own output, not our copy.
    var errorDescription: String? {
        switch self {
        case .askpassNotFound:
            return String(localized: "askpass script not found",
                          comment: "Shell error: the bundled askpass script is missing")
        case .outputDecodingFailed:
            return String(localized: "Failed to decode command output as UTF-8",
                          comment: "Shell error: a command's output wasn't valid text")
        case .coundtGetHomeDirectory:
            return String(localized: "Failed to get home directory",
                          comment: "Shell error: the user's home folder couldn't be resolved")
        case .nonZeroExit(let command, let exitCode, let output):
            return String(localized: "Failed to run shell command.\nCommand: \(command) (exit code: \(exitCode))\nOutput: \(output)",
                          comment: "Shell error: a command exited with an error (command, exit code, output)")
        case .timedOut(let command, let seconds):
            // Format the Duration first: interpolating one straight into a localized string yields
            // its debug description (and a deprecation warning). `.units` is itself localized.
            let deadline = seconds.formatted(.units(allowed: [.minutes, .seconds], width: .wide))
            return String(localized: "Shell command timed out after \(deadline).\nCommand: \(command)",
                          comment: "Shell error: a command ran past its deadline (duration, command)")
        }
    }
}
