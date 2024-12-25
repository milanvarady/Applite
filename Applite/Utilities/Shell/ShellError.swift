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
    case nonZeroExit(status: Int32, output: String)

    var errorDescription: String? {
        switch self {
        case .scriptNotFound:
            return "Required script file not found"
        case .checksumMismatch:
            return "Script checksum mismatch. The file has been modified."
        case .outputDecodingFailed:
            return "Failed to decode command output as UTF-8"
        case .nonZeroExit(let status, let output):
            return "Command failed with exit code \(status): \(output)"
        }
    }
}
