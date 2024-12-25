//
//  Shell.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation
import OSLog

/// Namespace for shell command execution utilities
public enum Shell {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Shell")
    private static let askpassChecksum = "fAl63ShrMp8Sp9HIj/FYYA=="

    /// Executes a shell command synchronously
    static func run(_ command: String) throws -> String {
        let (task, pipe) = try createProcess(command: command)

        try task.run()
        task.waitUntilExit()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()

        guard let output = String(data: data, encoding: .utf8) else {
            throw ShellError.outputDecodingFailed
        }

        let cleanOutput = output.cleanANSIEscapeCodes()

        guard task.terminationStatus == 0 else {
            throw ShellError.nonZeroExit(status: task.terminationStatus, output: cleanOutput)
        }

        return cleanOutput
    }

    /// Executes a shell command asynchronously
    static func runAsync(_ command: String) async throws -> String {
        // Simply mark it as async and use the same implementation
        try run(command)
    }

    /// Executes a shell command and streams the output
    static func stream(_ command: String) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let (task, pipe) = try createProcess(command: command)
                    let fileHandle = pipe.fileHandleForReading

                    try task.run()

                    for try await line in fileHandle.bytes.lines {
                        let cleanOutput = line.cleanANSIEscapeCodes()
                        continuation.yield(cleanOutput)
                    }

                    task.waitUntilExit()

                    if task.terminationStatus != 0 {
                        continuation.finish(throwing: ShellError.nonZeroExit(status: task.terminationStatus, output: ""))
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

    /// Creates a shell process with a given command
    private static func createProcess(command: String) throws -> (Process, Pipe) {
        // Verify askpass script
        guard let scriptPath = Bundle.main.path(forResource: "askpass", ofType: "js") else {
            throw ShellError.scriptNotFound
        }

        if URL(string: scriptPath)?.checksumInBase64() != askpassChecksum {
            throw ShellError.checksumMismatch
        }

        let task = Process()
        let pipe = Pipe()

        // Set up environment
        var environment: [String: String] = [
            "SUDO_ASKPASS": scriptPath
        ]

        if let proxySettings = try? NetworkProxyManager.getSystemProxySettings() {
            logger.info("Network proxy is enabled. Type: \(proxySettings.type.rawValue)")
            environment["ALL_PROXY"] = proxySettings.fullString
        }

        task.standardOutput = pipe
        task.standardError = pipe
        task.environment = environment
        task.arguments = ["-l", "-c", command]
        task.executableURL = URL(fileURLWithPath: "/bin/zsh")
        task.standardInput = nil

        return (task, pipe)
    }
}
