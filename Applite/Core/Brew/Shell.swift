//
//  Shell.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation
import OSLog
import os

/// Namespace for shell command execution utilities
enum Shell {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Shell")

    /// Executes a shell command asynchronously
    ///
    /// - Parameters:
    ///   - command: The shell command to run
    ///   - pty: Wether to use pseudo-TTY behavior or not
    ///   - timeout: If set, the process is killed after this duration and ``ShellError/timedOut``
    ///     is thrown. Use for commands that could hang (e.g. a login shell sourcing a broken config).
    ///
    /// - Returns: The output of the shell command
    ///
    /// Using the `pty` option can leave unwanted characters in the output, use only when necessary
    @discardableResult
    static func runAsync(_ command: String, pty: Bool = false, timeout: Duration? = nil) async throws -> String {
        try await runProcessAsync(command, pty: pty, timeout: timeout)
    }

    /// Runs a command and awaits its termination handler — **never blocks a thread** on
    /// `waitUntilExit()`. Blocking inside async code (as the old `runAsync` did) starves the
    /// concurrency pool and stalls SwiftUI's main-run-loop updates, so all async runs go through here.
    ///
    /// - Parameter timeout: If set, the process is killed after this duration and
    ///   ``ShellError/timedOut`` is thrown (used for commands that could hang, e.g. a login shell).
    private static func runProcessAsync(_ command: String, pty: Bool, timeout: Duration?) async throws -> String {
        let (task, pipe) = try createProcess(command: command, pty: pty)
        let handle = pipe.fileHandleForReading

        // Drain the pipe *concurrently* (not after exit) so a large output can't fill the ~64 KB
        // pipe buffer and block the child before it exits — which would hang `terminationHandler`
        // (and the continuation) forever. `readabilityHandler` fires on a background queue; the lock
        // makes the append safe against the termination-time tail drain.
        let collected = OSAllocatedUnfairLock<Data>(initialState: Data())
        handle.readabilityHandler = { fileHandle in
            let chunk = fileHandle.availableData
            if !chunk.isEmpty {
                collected.withLock { $0.append(chunk) }
            }
        }

        let watchdog: Task<Void, Never>? = timeout.map { duration in
            Task {
                try? await Task.sleep(for: duration)
                if task.isRunning { task.terminate() }
            }
        }
        defer { watchdog?.cancel() }

        return try await withCheckedThrowingContinuation { continuation in
            task.terminationHandler = { proc in
                handle.readabilityHandler = nil
                // Capture any bytes buffered between the last readability callback and exit.
                let tail = handle.availableData
                let data = collected.withLock { buffer -> Data in
                    if !tail.isEmpty { buffer.append(tail) }
                    return buffer
                }
                let output = String(decoding: data, as: UTF8.self).cleanTerminalOutput()

                // A timeout kills the process with SIGTERM (uncaught signal) — distinguish that
                // from a normal non-zero exit.
                if let timeout, proc.terminationReason == .uncaughtSignal, proc.terminationStatus == SIGTERM {
                    continuation.resume(throwing: ShellError.timedOut(command: command, seconds: timeout))
                } else if proc.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(throwing: ShellError.nonZeroExit(
                        command: command,
                        exitCode: proc.terminationStatus,
                        output: output
                    ))
                }
            }

            do {
                try task.run()
            } catch {
                handle.readabilityHandler = nil
                continuation.resume(throwing: error)
            }
        }
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
            // `stream` is called synchronously, so a plain `Task {}` here would inherit the caller's
            // actor — and callers are `@MainActor`. The reader does blocking process I/O
            // (`FileHandle.bytes`, `waitUntilExit`), which on the main actor freezes the UI for the
            // whole command. Run it detached so it never touches the caller's actor. The non-Sendable
            // `Process`/`Pipe` are created *inside* the task; a lock hands the process back so
            // `onTermination` (which can fire on any thread) can still kill it.
            let processHolder = OSAllocatedUnfairLock<Process?>(initialState: nil)

            let reader = Task.detached {
                let task: Process
                let pipe: Pipe

                do {
                    (task, pipe) = try createProcess(command: command, pty: pty)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                processHolder.withLock { $0 = task }

                // Set by the process's termination handler; lets the read loop's error path tell
                // "we closed the handle to end a hung read" apart from a genuine read failure.
                let processExited = OSAllocatedUnfairLock<Bool>(initialState: false)

                do {
                    let fileHandle = pipe.fileHandleForReading

                    // Force the read loop to end once the process exits. `fileHandle.bytes` blocks
                    // until the pty reaches EOF, but a `script`-wrapped pty can linger after brew has
                    // finished (or AsyncBytes may not observe EOF promptly). A hung loop here would
                    // freeze the cask on its install/"success" state — so it's never marked installed.
                    // Closing our read end on termination guarantees EOF.
                    task.terminationHandler = { _ in
                        processExited.withLock { $0 = true }
                        try? fileHandle.close()
                    }

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
                    // A read error *after* the process exited is the termination handler closing the
                    // handle to break a hung read — not a real failure. Finish on the true exit status
                    // instead of surfacing a spurious error. Anything else propagates.
                    if processExited.withLock({ $0 }) {
                        task.waitUntilExit()
                        if task.terminationStatus != 0 {
                            continuation.finish(throwing: ShellError.nonZeroExit(
                                command: command,
                                exitCode: task.terminationStatus,
                                output: "n/a (streamed output)"
                            ))
                        } else {
                            continuation.finish()
                        }
                    } else {
                        logger.error("Stream error: \(error.localizedDescription)")
                        continuation.finish(throwing: error)
                    }
                }
            }

            // Terminate the process if the consumer cancels (or otherwise stops iterating).
            //
            // This is a hard kill, not a graceful cancellation: `terminate()` sends SIGTERM
            // to the `script` wrapper, which closes the pty and SIGHUPs the foreground
            // process group (brew + curl). brew does NOT run its cooperative SIGINT-cancel
            // path here — SIGINT can't be used because `script` ignores it (so a real Ctrl-C
            // passes through to the child instead of killing the wrapper). The hard kill is
            // safe for the download phase: brew downloads to `*.incomplete` temp files and
            // only renames them on success, and its cache locks are OS `flock`s that the
            // kernel releases on process death. Worst case is a resumable leftover temp file.
            continuation.onTermination = { _ in
                reader.cancel()
                processHolder.withLock { proc in
                    if proc?.isRunning == true { proc?.terminate() }
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
        // Locate the bundled askpass script. Its integrity is guaranteed by the app's
        // code signature (the bundle's CodeResources seal covers every resource), so no
        // separate checksum is needed here.
        guard let scriptPath = Bundle.main.path(forResource: "askpass", ofType: "js") else {
            throw ShellError.askpassNotFound
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
            "HOME": homeDirectory,
            "HOMEBREW_NO_ASK": "1", // Brew 6+ enables ask mode (confirmation prompts) by default; Applite drives brew non-interactively
            "HOMEBREW_NO_ENV_HINTS": "1", // Suppress advisory hint lines so they don't clutter the parsed output stream
            // Load-bearing for the CLT-free annex: without this every brew command tries a
            // git-based self-update, which needs git (absent without Command Line Tools) and
            // would pop the macOS CLT install dialog. Applite keeps the annex fresh by
            // re-fetching the tarball instead (see AnnexBrewManager.refreshAnnexBrew).
            "HOMEBREW_NO_AUTO_UPDATE": "1",
            // Pin brew to the system curl (always present on macOS, works without CLT) so it
            // never probes for a Homebrew-installed curl. Cask downloads and the portable-ruby
            // fetch both go through this. Combined with API mode (HOMEBREW_NO_INSTALL_FROM_API
            // left unset) this keeps git off the cask install path entirely.
            "HOMEBREW_CURL_PATH": "/usr/bin/curl"
        ]

        // The annex has no real git (no CLT). Point brew at a shim so its `git --version`
        // availability check passes; brew still curls the cask download. Only for the annex — a
        // user's own brew keeps its real git so git-source casks and `brew update` still work.
        //
        // No `HOMEBREW_DEVELOPER` needed anymore: brew 6.0.12 (PR #23061) enabled the FFI
        // quarantine/xattr/trash helpers for all users and deleted the Swift fallback scripts, so
        // casks install and uninstall/zap without ever shelling out to Swift or `xcrun` — the last
        // two CLT-dialog triggers on a machine without Command Line Tools — with no developer flag.
        // Brew 6.0.10 had already dropped the earlier triggers (the fatal ARM dev-tools check and
        // the `xcrun -find` fallback in `DevelopmentTools.locate`). Not setting the flag is also
        // safer: it would otherwise turn some deprecated-DSL warnings into hard errors.
        if BrewPaths.selectedBrewOption == .annex {
            GitShim.ensureInstalled()
            environment["HOMEBREW_GIT_PATH"] = GitShim.executable.path(percentEncoded: false)
            // Disable bootsnap for the annex. Its load-path cache is keyed only on the Ruby
            // version + installed gems (see brew's startup/bootsnap.rb) — NOT the brew version — and
            // lives under HOMEBREW_CACHE, which survives an annex wipe. Because the annex tracks
            // `master` and is refreshed by re-extracting the tarball *over* the tree, brew's own Ruby
            // files change while that cache key stays constant, so a stale entry makes brew report an
            // on-disk file as "cannot load such file" (e.g. `lock_file/formula_lock`). A version pin
            // hid this by keeping the files byte-identical; unpinned, we must bypass the cache.
            environment["HOMEBREW_NO_BOOTSNAP"] = "1"
        }

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
