//
//  Shell.swift
//  Applite
//
//  Created by Milán Várady on 2022. 10. 16..
//

import Foundation
import os

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
    let logger = Logger()
    
    task.standardOutput = pipe
    task.standardError = pipe
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
        return ShellResult(output: output, didFail: task.terminationStatus != 0)
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
