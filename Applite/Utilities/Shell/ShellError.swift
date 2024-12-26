//
//  ShellError.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation

enum ShellError: LocalizedError {
    case scriptNotFound
    case checksumMismatch
    case outputDecodingFailed
    case nonZeroExit(command: String, exitCode: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "Required script file not found"
        case .checksumMismatch:
            return "Script checksum mismatch. The file has been modified."
        case .outputDecodingFailed:
            return "Failed to decode command output as UTF-8"
        case .nonZeroExit(let command, let exitCode, let output):
            return "Failed to run shell command.\nCommand: \(command) (exit code: \(exitCode))\nOutput: \(output)"
        }
    }
}
