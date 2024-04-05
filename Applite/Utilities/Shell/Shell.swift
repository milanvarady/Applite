//
//  Shell.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 16..
//

import Foundation
import OSLog

fileprivate let shellPath = "/bin/zsh"

/// Runs a shell commands
///
/// - Parameters:
///   - command: Command to run
///
/// - Returns: A ``ShellResult`` containing the output and exit status of command
@discardableResult
func shell(_ command: String) -> ShellResult {
    let task = Process()
    let pipe = Pipe()
    let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "shell")

    // Get pinentry script for sudo askpass
    guard let pinentryScript = Bundle.main.path(forResource: "pinentry", ofType: "ksh") else {
        return ShellResult(output: "pinentry.ksh not found", didFail: true)
    }
    
    // Verify pinentry script checksum
    if URL(string: pinentryScript)?.checksumInBase64() != pinentryScriptHash {
        return ShellResult(output: "pinentry.ksh checksum mismatch. The file has been modified.", didFail: true)
    }

    // Set up environment
    var environment: [String: String] = [
        "SUDO_ASKPASS": pinentryScript
    ]

    if let proxySettings = try? NetworkProxyManager.getSystemProxySettings() {
        logger.info("Network proxy is enabled. Type: \(proxySettings.type.rawValue)")
        environment["ALL_PROXY"] = proxySettings.fullString
    }

    task.standardOutput = pipe
    task.standardError = pipe
    task.environment = environment
    task.arguments = ["-l", "-c", command]
    task.executableURL = URL(fileURLWithPath: shellPath)
    task.standardInput = nil

    do {
        try task.run()
    } catch {
        logger.error("Shell run error. Failed to run shell(\(command)).")
        return ShellResult(output: "", didFail: true)
    }
    
    task.waitUntilExit()
    
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    
    if let output = String(data: data, encoding: .utf8) {
        let cleanOutput = output.replacingOccurrences(of: "\\\u{001B}\\[[0-9;]*[a-zA-Z]", with: "", options: .regularExpression)
        return ShellResult(output: cleanOutput, didFail: task.terminationStatus != 0)
    } else {
        logger.error("Shell data error. Failed to get shell(\(command)) output. Most likely due to a UTF-8 decoding failure.")
        return ShellResult(output: "Error: Invalid UTF-8 data", didFail: true)
    }
}

/// Async version of shell command
@discardableResult
func shell(_ command: String) async -> ShellResult {
    return dummyShell(command)
}

// This is needed so we can overload the shell function with an async version
fileprivate func dummyShell(_ command: String) -> ShellResult {
    return shell(command)
}
