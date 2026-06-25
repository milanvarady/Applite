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
    static func runBrewCommand(_ arguments: [String], pty: Bool = false) async throws -> String {
        let command = "\(BrewPaths.currentBrewExecutable.quotedPath()) \(arguments.joined(separator: " "))"
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

                    // Homebrew redraws its live download progress in place using cursor-move
                    // escapes (ESC[0G / ESC[nF), not newlines, so `bytes.lines` would buffer
                    // every progress frame into a single chunk until the download finished.
                    // Split the byte stream into frames on newlines, carriage returns, AND
                    // cursor-repositioning escapes so each redraw surfaces as its own line.
                    var frame: [UInt8] = []
                    var inEscape = false
                    var escapeIsCSI = false

                    func flushFrame() {
                        guard !frame.isEmpty else { return }
                        let text = String(decoding: frame, as: UTF8.self).cleanTerminalOutput()
                        frame.removeAll(keepingCapacity: true)
                        if !text.isEmpty {
                            continuation.yield(text)
                        }
                    }

                    for try await byte in fileHandle.bytes {
                        if inEscape {
                            if !escapeIsCSI {
                                // First byte after ESC determines the escape type.
                                escapeIsCSI = (byte == UInt8(ascii: "["))
                                // A non-CSI escape (ESC + one char) ends immediately; drop it.
                                if !escapeIsCSI { inEscape = false }
                                continue
                            }

                            // Inside a CSI sequence — runs until a final byte (0x40...0x7E).
                            if (0x40...0x7E).contains(byte) {
                                inEscape = false
                                escapeIsCSI = false

                                // Cursor-repositioning finals mark an in-place redraw → frame boundary.
                                switch byte {
                                case UInt8(ascii: "A"), UInt8(ascii: "B"), UInt8(ascii: "E"),
                                     UInt8(ascii: "F"), UInt8(ascii: "G"), UInt8(ascii: "H"),
                                     UInt8(ascii: "d"):
                                    flushFrame()
                                default:
                                    break   // color / clear / cursor-visibility — strip and continue
                                }
                            }
                            continue
                        }

                        switch byte {
                        case 0x1B:              // ESC — start of an escape sequence (stripped)
                            inEscape = true
                            escapeIsCSI = false
                        case 0x0A, 0x0D:        // \n or \r — frame boundary
                            flushFrame()
                        default:
                            frame.append(byte)
                        }
                    }

                    flushFrame()

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

        if let mirrorEnvironmentVariables = MirrorEnvironment.getEnvironmentVariables() {
            logger.info("Mirror enabled. API domain: \(mirrorEnvironmentVariables["HOMEBREW_API_DOMAIN"] ?? "not set")")
            environment.merge(mirrorEnvironmentVariables) { (_, new) in new }
        }

        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = environment

        if pty {
            // Use `script` for pseudo-TTY behavior.
            //
            // A GUI app has no controlling terminal, so the pty reports its window
            // size (`stty size`) as `0 0`. Homebrew then treats the terminal width as
            // 0 and suppresses its live download progress (the byte counters and bar
            // we scrape). Forcing a sane window size first re-enables that output.
            let ptyCommand = "stty rows 50 cols 200 2>/dev/null; \(command)"
            task.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            task.arguments = ["-q", "/dev/null", "/bin/sh", "-c", ptyCommand]
        } else {
            task.executableURL = URL(fileURLWithPath: "/bin/sh")
            task.arguments = ["-c", command]
        }

        return (task, pipe)
    }
}
