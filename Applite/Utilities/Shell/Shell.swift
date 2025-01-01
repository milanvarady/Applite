//
//  Shell.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation
import OSLog

/// Namespace for shell command execution utilities
enum Shell {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Shell")

    /// MD5 checksum of the askpass script.
    /// We want to make sure the script isn't modified by any outside actor
    private static let askpassChecksum = "fAl63ShrMp8Sp9HIj/FYYA=="

    /// Executes a shell command synchronously
    ///
    /// - Parameters:
    ///   - command: The shell command to run
    ///   - pty: Wether to use pseudo-TTY behavior or not
    ///
    /// - Returns: The output of the shell command
    ///
    /// Using the `pty` option can leave unwanted characters in the output, use only when necessary
    @discardableResult
    static func run(_ command: String, pty: Bool = false) throws -> String {
        let (task, pipe) = try createProcess(command: command, pty: pty)

        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let output = String(data: data, encoding: .utf8) else {
            throw ShellError.outputDecodingFailed
        }

        let cleanOutput = output.cleanTerminalOutput()

        guard task.terminationStatus == 0 else {
            throw ShellError.nonZeroExit(
                command: command,
                exitCode: task.terminationStatus,
                output: cleanOutput
            )
        }

        return cleanOutput
    }

    /// Executes a shell command asynchronously
    ///
    /// - Parameters:
    ///   - command: The shell command to run
    ///   - pty: Wether to use pseudo-TTY behavior or not
    ///
    /// - Returns: The output of the shell command
    ///
    /// Using the `pty` option can leave unwanted characters in the output, use only when necessary
    @discardableResult
    static func runAsync(_ command: String, pty: Bool = false) async throws -> String {
        // Simply mark it as async and use the same implementation
        try run(command)
    }

    /// Executes a brew command asynchronously
    ///
    /// - Parameters:
    ///   - command: The shell command to run
    ///   - pty: Wether to use pseudo-TTY behavior or not
    ///
    /// - Returns: The output of the shell command
    ///
    /// Using the `pty` option can leave unwanted characters in the output, use only when necessary
    @discardableResult
    static func runBrewCommand(_ brewCommand: String, arguments: [String] = [], pty: Bool = false) async throws -> String {
        let command = "\(BrewPaths.currentBrewExecutable) \(brewCommand) --cask \(arguments.joined(separator: " "))"
        return try await runAsync(command)
    }

    /// Executes a shell command and streams the output line-by-line
    ///
    /// - Parameters:
    ///   - command: The shell command to run
    ///   - pty: Wether to use pseudo-TTY behavior or not
    ///
    /// - Returns: An ``AsyncThrowingStream`` that yields the output in real time
    ///
    /// Using the `pty` option can leave unwanted characters in the output, use only when necessary
    static func stream(_ command: String, pty: Bool = false) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (task, pipe) = try createProcess(command: command, pty: pty)
                    let fileHandle = pipe.fileHandleForReading

                    try task.run()

                    for try await line in fileHandle.bytes.lines {
                        let cleanOutput = line.cleanTerminalOutput()
                        continuation.yield(cleanOutput)
                    }

                    task.waitUntilExit()

                    if task.terminationStatus != 0 {
                        continuation.finish(
                            throwing: ShellError.nonZeroExit(
                                command: command,
                                exitCode: task.terminationStatus,
                                output: "n/a (streamed output)"
                            )
                        )
                    } else {
                        continuation.finish()
                    }
                } catch {
                    logger.error("Stream error: \(error.localizedDescription)")
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Initializes a shell process with a given command
    ///
    /// - Parameters:
    ///   - command: The shell command to run
    ///   - pty: Wether to use pseudo-TTY behavior or not
    ///
    /// - Returns: The initialized ``Process`` and ``Pipe`` object
    ///
    /// We need the `pty` option because some brew commands run in quiet mode if it detects its not in a interactive environment
    private static func createProcess(command: String, pty: Bool) throws -> (Process, Pipe) {
        // Verify askpass script
        guard let scriptPath = Bundle.main.path(forResource: "askpass", ofType: "js") else {
            throw ShellError.askpassNotFound
        }

        if URL(string: scriptPath)?.checksumInBase64() != askpassChecksum {
            throw ShellError.askpassChecksumMismatch
        }

        guard let homeDirectory = ProcessInfo.processInfo.environment["HOME"] else {
            throw ShellError.coundtGetHomeDirectory
        }

        let task = Process()
        let pipe = Pipe()

        // Set up environment
        var environment: [String: String] = [
            "SUDO_ASKPASS": scriptPath,
            "TERM": "xterm-256color", // Ensure terminal emulation
            "HOME": homeDirectory
        ]

        if let proxySettings = try? NetworkProxyManager.getSystemProxySettings() {
            logger.info("Network proxy is enabled. Type: \(proxySettings.type.rawValue)")
            environment["ALL_PROXY"] = proxySettings.fullString
        }

        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = environment

        if pty {
            // Use `script` for pseudo-TTY behavior
            task.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            task.arguments = ["-q", "/dev/null", "/bin/sh", "-c", command]
        } else {
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", command]
        }

        return (task, pipe)
    }
}
