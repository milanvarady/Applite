//
//  Shell.swift
//  Applite
//
//  Created by Milán Várady on 2024.12.25.
//

import Foundation
import OSLog
import os

/// Namespace for shell command execution utilities.
///
/// Commands run in one of two ways:
/// - **argv execution** (``run(_:_:pty:timeout:)`` / ``stream(_:_:pty:)`` and the brew helpers):
///   the executable is launched directly with an argument array — there is **no `/bin/sh -c`**, so
///   nothing in `arguments` is ever parsed by a shell. This is the *only* safe path for commands
///   whose arguments include untrusted values (third-party cask tokens, user-entered brew/appdir
///   paths). Even the pty variant funnels the argv through `exec "$0" "$@"`, never string-splicing.
/// - **shell-script execution** (``runShellScript(_:pty:timeout:)`` / ``streamShellScript(_:pty:)``):
///   runs `/bin/sh -c <script>`. Reserved for fixed, trusted script *literals* that genuinely need
///   shell features (globs, pipes, `$HOME`, `set -o pipefail`). Never interpolate untrusted input
///   into such a script — that reopens the injection hole the argv path exists to prevent.
enum Shell {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "Shell")

    // MARK: - Argv execution (no shell — injection-proof)

    /// Runs an executable directly with an argv array and returns its combined output.
    ///
    /// - Parameters:
    ///   - executableURL: The program to run.
    ///   - arguments: Argument vector, passed verbatim — no shell parsing, quoting, or word-splitting.
    ///   - pty: Run inside a pseudo-TTY (needed for brew's live progress output).
    ///   - timeout: If set, the process is killed after this duration and ``ShellError/timedOut`` is
    ///     thrown. Use for commands that could hang (e.g. a `brew --version` probe against a broken path).
    @discardableResult
    static func run(_ executableURL: URL, _ arguments: [String], pty: Bool = false, timeout: Duration? = nil) async throws -> String {
        try await runProcessAsync(executableURL: executableURL, arguments: arguments, pty: pty, timeout: timeout)
    }

    /// Streams an executable's output line-by-line. Argv-based; see ``run(_:_:pty:timeout:)``.
    static func stream(_ executableURL: URL, _ arguments: [String], pty: Bool = false) -> AsyncThrowingStream<String, Error> {
        makeStream(executableURL: executableURL, arguments: arguments, pty: pty)
    }

    // MARK: - Brew convenience

    /// Runs the currently-selected `brew` with `arguments`. Argv-based, so tokens/paths are safe.
    @discardableResult
    static func runBrewCommand(_ arguments: [String], pty: Bool = false, timeout: Duration? = nil) async throws -> String {
        try await run(BrewPaths.currentBrewExecutable, arguments, pty: pty, timeout: timeout)
    }

    /// Streams the currently-selected `brew` with `arguments`. Argv-based, so tokens/paths are safe.
    static func streamBrewCommand(_ arguments: [String], pty: Bool = false) -> AsyncThrowingStream<String, Error> {
        stream(BrewPaths.currentBrewExecutable, arguments, pty: pty)
    }

    // MARK: - Shell-script escape hatch (trusted literals only)

    /// Runs `/bin/sh -c <script>`. See the type doc: **fixed, trusted literals only** — never
    /// interpolate untrusted input (cask tokens, user paths) into `script`.
    @discardableResult
    static func runShellScript(_ script: String, pty: Bool = false, timeout: Duration? = nil) async throws -> String {
        try await run(URL(fileURLWithPath: "/bin/sh"), ["-c", script], pty: pty, timeout: timeout)
    }

    /// Streams `/bin/sh -c <script>`. See ``runShellScript(_:pty:timeout:)`` for the safety contract.
    static func streamShellScript(_ script: String, pty: Bool = false) -> AsyncThrowingStream<String, Error> {
        stream(URL(fileURLWithPath: "/bin/sh"), ["-c", script], pty: pty)
    }

    // MARK: - Process implementation

    /// How long a process gets to honor SIGTERM before it is killed outright.
    ///
    /// `terminate()` is a *request*, not a guarantee: a brew wedged in a syscall — or a `script`
    /// wrapper whose child ignored the pty hangup — can outlive it. That matters most at quit, where
    /// the survivor is reparented to launchd and keeps running with no Applite left to stop it
    /// (P3-10). Anything that waits for a clean unwind must allow **more** than this — see
    /// `BrewService.cancelAllAndWait`.
    static let terminationGrace: Duration = .seconds(1)

    /// How long a stream's pipe must stay *silent* after the process exits before we force EOF by
    /// closing our read end. Idle-based rather than a fixed delay, so a slow drain is never cut off —
    /// see the read loop in ``makeStream(executableURL:arguments:pty:)``.
    private static let eofIdleTimeout: Duration = .milliseconds(750)
    private static let eofIdlePollInterval: Duration = .milliseconds(150)

    /// Asks the process to stop, and makes sure it does.
    ///
    /// SIGTERM first so brew can unwind normally, then SIGKILL if it's still alive after
    /// ``terminationGrace``. The liveness re-check reads `isRunning` rather than trusting the cached
    /// pid, so a pid recycled by the OS after the process was reaped can never be signalled.
    static func terminateThenKill(_ process: Process) {
        guard process.isRunning else { return }
        process.terminate()

        let pid = process.processIdentifier
        Task.detached {
            try? await Task.sleep(for: terminationGrace)
            guard process.isRunning else { return }
            kill(pid, SIGKILL)
        }
    }

    /// Runs a process and awaits its termination handler — **never blocks a thread** on
    /// `waitUntilExit()`. Blocking inside async code starves the concurrency pool and stalls
    /// SwiftUI's main-run-loop updates, so all non-streaming runs go through here.
    ///
    /// Cancelling the awaiting `Task` terminates the process (SIGTERM) so a hung brew can't wedge
    /// the serial queue forever; a `timeout`, when set, does the same after the given duration.
    private static func runProcessAsync(executableURL: URL, arguments: [String], pty: Bool, timeout: Duration?) async throws -> String {
        try Task.checkCancellation()

        let displayCommand = ([executableURL.path(percentEncoded: false)] + arguments).joined(separator: " ")
        let (task, pipe) = try createProcess(executableURL: executableURL, arguments: arguments, pty: pty)
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
                terminateThenKill(task)
            }
        }
        defer { watchdog?.cancel() }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                task.terminationHandler = { proc in
                    handle.readabilityHandler = nil
                    // Capture any bytes buffered between the last readability callback and exit.
                    let tail = handle.availableData
                    let data = collected.withLock { buffer -> Data in
                        if !tail.isEmpty { buffer.append(tail) }
                        return buffer
                    }
                    let output = String(decoding: data, as: UTF8.self).cleanTerminalOutput()

                    // A timeout / cancellation kills the process with SIGTERM, escalating to
                    // SIGKILL if it ignores that (see `terminateThenKill`) — distinguish both from
                    // a normal non-zero exit.
                    if proc.terminationReason == .uncaughtSignal,
                       proc.terminationStatus == SIGTERM || proc.terminationStatus == SIGKILL {
                        if let timeout {
                            continuation.resume(throwing: ShellError.timedOut(command: displayCommand, seconds: timeout))
                        } else {
                            continuation.resume(throwing: CancellationError())
                        }
                    } else if proc.terminationStatus == 0 {
                        continuation.resume(returning: output)
                    } else {
                        continuation.resume(throwing: ShellError.nonZeroExit(
                            command: displayCommand,
                            exitCode: proc.terminationStatus,
                            output: output
                        ))
                    }
                }

                do {
                    try task.run()
                    // Cover the narrow race where cancellation arrived after the handler was
                    // installed but before the process was running.
                    if Task.isCancelled { terminateThenKill(task) }
                } catch {
                    handle.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            terminateThenKill(task)
        }
    }

    /// Streams a process's output line-by-line as an ``AsyncThrowingStream``.
    /// The consumer cancelling its task (or otherwise stopping iteration) terminates the process.
    private static func makeStream(executableURL: URL, arguments: [String], pty: Bool) -> AsyncThrowingStream<String, Error> {
        let displayCommand = ([executableURL.path(percentEncoded: false)] + arguments).joined(separator: " ")

        return AsyncThrowingStream { continuation in
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
                    (task, pipe) = try createProcess(executableURL: executableURL, arguments: arguments, pty: pty)
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

                    // Read in chunks via `readabilityHandler` rather than `fileHandle.bytes`.
                    // AsyncBytes hands over one byte at a time, which is slow enough that a fast
                    // writer builds a backlog in the pipe — and the handler reports EOF as an empty
                    // read, which is what lets the drain below end on its own.
                    let (chunks, chunkFeed) = AsyncStream<Data>.makeStream()

                    // When bytes last arrived, and whether the pipe has reached EOF. The watchdog
                    // below uses these to tell "still draining" apart from "the writer is gone but
                    // our read never ended".
                    let clock = ContinuousClock()
                    let lastRead = OSAllocatedUnfairLock<ContinuousClock.Instant>(initialState: clock.now)
                    let reachedEOF = OSAllocatedUnfairLock<Bool>(initialState: false)

                    fileHandle.readabilityHandler = { handle in
                        let data = handle.availableData
                        lastRead.withLock { $0 = clock.now }
                        if data.isEmpty {
                            handle.readabilityHandler = nil
                            reachedEOF.withLock { $0 = true }
                            chunkFeed.finish()
                        } else {
                            chunkFeed.yield(data)
                        }
                    }

                    // Do NOT close the read end the moment the process exits. Whatever it wrote just
                    // before exiting is still sitting in the pipe, and closing discards it: that
                    // truncated the 161 KB tap-cask JSON to 63% (it failed to parse, so taps silently
                    // never appeared), and on the pty path it can cut brew's trailing "successfully
                    // installed" marker — turning a successful install into a reported failure.
                    //
                    // The close still has to exist, because a `script`-wrapped pty can linger after
                    // brew finishes and leave the read hanging, which would strand a cask on its
                    // install state forever. So wait for the pipe to go *quiet* instead: once nothing
                    // has arrived for `eofIdleTimeout`, force EOF. Idle-based, not a fixed delay, so
                    // a drain that's still making progress is never cut off no matter how big it is.
                    task.terminationHandler = { _ in
                        processExited.withLock { $0 = true }

                        Task.detached {
                            while !reachedEOF.withLock({ $0 }) {
                                try? await Task.sleep(for: eofIdlePollInterval)
                                if reachedEOF.withLock({ $0 }) { return }
                                let idle = lastRead.withLock { clock.now - $0 }
                                if idle >= eofIdleTimeout {
                                    // End the stream *here*, don't just close the handle: closing it
                                    // stops `readabilityHandler` from firing rather than delivering a
                                    // final empty read, so waiting for the handler to report EOF would
                                    // hang the read loop forever — a worse failure than the truncation
                                    // this whole watchdog exists to avoid.
                                    //
                                    // And deliberately do NOT close the descriptor here. An already
                                    // dispatched `readabilityHandler` can be inside `availableData`
                                    // at this exact moment, and that raises an ObjC
                                    // `NSFileHandleOperationException` on a closed descriptor —
                                    // uncatchable from Swift, i.e. a crash. Clearing the handler and
                                    // finishing the stream is enough to release the read loop; the
                                    // descriptor closes with the `Pipe` when it deallocs.
                                    fileHandle.readabilityHandler = nil
                                    reachedEOF.withLock { $0 = true }
                                    chunkFeed.finish()
                                    return
                                }
                            }
                        }
                    }

                    defer { fileHandle.readabilityHandler = nil }

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

                    // Same frame state machine as before, now fed from chunks instead of
                    // one-byte-at-a-time AsyncBytes.
                    for await chunk in chunks {
                        for byte in chunk {
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
                    }

                    flushFrame()

                    task.waitUntilExit()

                    if task.terminationStatus != 0 {
                        continuation.finish(
                            throwing: ShellError.nonZeroExit(
                                command: displayCommand,
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
                                command: displayCommand,
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
                    if let proc { terminateThenKill(proc) }
                }
            }
        }
    }

    /// Builds a configured (but not yet started) ``Process`` running `executableURL` with `arguments`.
    ///
    /// - Parameter pty: When `true`, the executable runs inside a pseudo-TTY via `/usr/bin/script`.
    ///   We need this because some brew commands run in quiet mode if they detect they're not in an
    ///   interactive environment.
    ///
    /// Argv safety: even the pty path never string-splices `arguments`. It runs
    /// `/bin/sh -c 'stty …; exec "$0" "$@"' <executable> <args…>`, where the shameless little script
    /// is a fixed literal and the (possibly untrusted) executable + arguments arrive as positional
    /// parameters that `exec "$0" "$@"` forwards verbatim — no shell parsing of their contents.
    private static func createProcess(executableURL: URL, arguments: [String], pty: Bool) throws -> (Process, Pipe) {
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
            //
            // `exec "$0" "$@"` then replaces the shell with the target executable, passing its
            // arguments verbatim — the untrusted executable path/args are positional parameters,
            // never part of the script text, so there's nothing for the shell to (mis)interpret.
            let sizedExec = #"stty rows 50 cols 200 2>/dev/null; exec "$0" "$@""#
            task.executableURL = URL(fileURLWithPath: "/usr/bin/script")
            task.arguments = ["-q", "/dev/null", "/bin/sh", "-c", sizedExec, executableURL.path(percentEncoded: false)] + arguments
        } else {
            task.executableURL = executableURL
            task.arguments = arguments
        }

        return (task, pipe)
    }
}
