#if os(macOS)
import Foundation
import Darwin

/// A live pseudo-terminal running a shell process on the Mac.
///
/// Wraps `forkpty`: the child runs the user's login shell attached to a pty, and
/// the parent reads/writes the master side. Raw bytes flow both ways —
/// keystrokes in, screen updates out — so full-screen apps (vim, htop) work. The
/// session is owned by the terminal service, which pumps `onOutput` into the
/// encrypted channel and feeds channel bytes into `write`.
///
/// macOS-only: iOS has no `forkpty` and is always the client side.
public final class PTYSession: @unchecked Sendable {
    /// The master pty file descriptor (parent side).
    private let masterFD: Int32
    /// The shell's process id, for signalling and reaping.
    private let pid: pid_t
    /// Reads (the drain of shell output) and reaping run here.
    private let ioQueue = DispatchQueue(label: "com.fiple.pty.io")
    /// Writes run on their OWN queue, never on `ioQueue`. A large write to a
    /// full pty buffer blocks until the shell drains it — and the shell can
    /// only drain if its echoed output is being read. If writes shared the read
    /// queue, that big write would sit ahead of the read handler and deadlock
    /// (a paste of more than the pty buffer would hang the shell). Separate
    /// queues let reads keep draining while a write is parked.
    private let writeQueue = DispatchQueue(label: "com.fiple.pty.write")
    private var readSource: DispatchSourceRead?
    private var processSource: DispatchSourceProcess?

    /// `closed`/`reaped` are read from `writeQueue` (write/resize/hangup) and
    /// written from `ioQueue`/`close()`, so they're guarded by this lock rather
    /// than confined to one queue.
    private let stateLock = NSLock()
    private var _closed = false
    private var _reaped = false
    private var isClosed: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _closed }
    /// Set once the child has been `waitpid`-reaped. After that the pid may be
    /// recycled by the OS, so signalling it again could hit an innocent process.
    private var isReaped: Bool { stateLock.lock(); defer { stateLock.unlock() }; return _reaped }

    /// Called with each chunk of shell output, on an internal queue.
    public var onOutput: (@Sendable (Data) -> Void)?
    /// Called once when the shell exits, with its exit code (or nil if signalled).
    public var onExit: (@Sendable (Int32?) -> Void)?

    public enum PTYError: Error, Equatable {
        case forkFailed(errno: Int32)
    }

    /// Spawns `shellPath` (default the user's login shell) attached to a fresh
    /// pty of the given size.
    public init(
        shellPath: String? = nil,
        arguments: [String]? = nil,
        cols: Int = 80,
        rows: Int = 24,
        workingDirectory: String? = nil,
        environment: [String: String] = ["TERM": "xterm-256color"]
    ) throws {
        let shell = shellPath ?? ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
        // Default to a login shell so the user's PATH and rc files load.
        let argv = arguments ?? [shell, "-l"]
        // Start in the user's home, like Terminal.app — a GUI app's cwd is `/`,
        // which the forked shell would otherwise inherit. Resolved before the
        // fork so the child only needs an async-signal-safe `chdir`.
        let cwd = workingDirectory ?? FileManager.default.homeDirectoryForCurrentUser.path

        var master: Int32 = 0
        var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)

        let childPID = forkpty(&master, nil, nil, &size)
        if childPID < 0 {
            throw PTYError.forkFailed(errno: errno)
        }

        if childPID == 0 {
            // Child. Move to the home directory, set TERM et al., then exec the
            // shell, replacing this image.
            _ = cwd.withCString { chdir($0) }
            for (key, value) in environment { setenv(key, value, 1) }
            let cArgs: [UnsafeMutablePointer<CChar>?] = argv.map { strdup($0) } + [nil]
            execv(shell, cArgs)
            // execv only returns on failure; the child must not continue.
            _exit(127)
        }

        // Parent.
        self.masterFD = master
        self.pid = childPID
        startReading()
        startReaping()
    }

    /// Writes bytes to the shell's input (keystrokes / pastes from the phone).
    /// Runs on `writeQueue` so a large blocking write never starves the read
    /// drain. A write racing `close()` must not touch the fd afterward — the
    /// number may already belong to a different file.
    public func write(_ data: Data) {
        writeQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            data.withUnsafeBytes { raw in
                var offset = 0
                let base = raw.bindMemory(to: UInt8.self).baseAddress!
                while offset < raw.count {
                    // Re-check before each partial write: a big paste can block
                    // here for a while, and close() may land mid-way.
                    if self.isClosed { break }
                    let n = Darwin.write(self.masterFD, base + offset, raw.count - offset)
                    if n <= 0 { break }
                    offset += n
                }
            }
        }
    }

    /// Updates the pty window size so full-screen apps reflow.
    public func resize(cols: Int, rows: Int) {
        writeQueue.async { [weak self] in
            guard let self, !self.isClosed else { return }
            var size = winsize(ws_row: UInt16(rows), ws_col: UInt16(cols), ws_xpixel: 0, ws_ypixel: 0)
            _ = ioctl(self.masterFD, TIOCSWINSZ, &size)
        }
    }

    /// Sends SIGHUP to the shell — used when a session's grace period lapses.
    public func hangup() {
        writeQueue.async { [weak self] in
            guard let self, !self.isClosed, !self.isReaped else { return }
            kill(self.pid, SIGHUP)
        }
    }

    private func startReading() {
        let source = DispatchSource.makeReadSource(fileDescriptor: masterFD, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var buffer = [UInt8](repeating: 0, count: 8192)
            let n = Darwin.read(self.masterFD, &buffer, buffer.count)
            if n > 0 {
                self.onOutput?(Data(buffer[0..<n]))
            } else {
                // EOF or error — the shell closed its side.
                self.readSource?.cancel()
            }
        }
        source.resume()
        readSource = source
    }

    private func startReaping() {
        let source = DispatchSource.makeProcessSource(identifier: pid, eventMask: .exit, queue: ioQueue)
        source.setEventHandler { [weak self] in
            guard let self else { return }
            var status: Int32 = 0
            waitpid(self.pid, &status, 0)
            self.stateLock.lock(); self._reaped = true; self.stateLock.unlock() // pid free for reuse
            let code: Int32? = (status & 0x7f) == 0 ? (status >> 8) & 0xff : nil
            self.onExit?(code)
            self.processSource?.cancel()
        }
        source.resume()
        processSource = source
    }

    /// Tears down the pty and stops the shell. Idempotent.
    public func close() {
        ioQueue.sync {
            stateLock.lock()
            if _closed { stateLock.unlock(); return }
            _closed = true
            let alreadyReaped = _reaped
            stateLock.unlock()

            readSource?.cancel()
            processSource?.cancel()
            // Only signal a child we still own; a reaped pid may have been
            // recycled to an unrelated process.
            if !alreadyReaped {
                kill(pid, SIGKILL)
                // The exit source was just cancelled, so nothing else will
                // reap this child — without a waitpid it stays a zombie until
                // the app quits. SIGKILL can't be caught, so this returns
                // almost immediately.
                let pid = self.pid
                DispatchQueue.global(qos: .utility).async {
                    var status: Int32 = 0
                    waitpid(pid, &status, 0)
                }
                stateLock.lock(); _reaped = true; stateLock.unlock()
            }
            // A write may be parked on writeQueue blocked on a full pty buffer;
            // closing the fd here unblocks it (its next write returns ≤ 0) and
            // its isClosed re-check bails. Reads are already cancelled.
            Darwin.close(masterFD)
        }
    }
}
#endif
