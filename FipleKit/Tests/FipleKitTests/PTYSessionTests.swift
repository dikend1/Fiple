#if os(macOS)
import Foundation
import Testing
@testable import FipleKit

@Suite("PTY session", .serialized, .timeLimit(.minutes(1)))
struct PTYSessionTests {
    /// Collects pty output across callbacks in a thread-safe way.
    private final class Sink: @unchecked Sendable {
        private let lock = NSLock()
        private var data = Data()
        func append(_ chunk: Data) { lock.lock(); data.append(chunk); lock.unlock() }
        func text() -> String { lock.lock(); defer { lock.unlock() }; return String(decoding: data, as: UTF8.self) }
    }

    @Test("Bytes written to the pty come back out (echo round-trip via cat)")
    func echoRoundTrip() async throws {
        let sink = Sink()
        // `cat` echoes stdin to stdout; the pty line discipline also echoes
        // input, so "ping" is guaranteed to appear in the output stream.
        let pty = try PTYSession(shellPath: "/bin/cat", arguments: ["/bin/cat"])
        pty.onOutput = { sink.append($0) }

        pty.write(Data("ping\n".utf8))

        try await waitUntil(timeout: 5) { sink.text().contains("ping") }
        #expect(sink.text().contains("ping"))
        pty.close()
    }

    @Test("The shell window can be resized without error")
    func resizeDoesNotCrash() async throws {
        let pty = try PTYSession(shellPath: "/bin/cat", arguments: ["/bin/cat"])
        pty.resize(cols: 120, rows: 40)
        // Give the async ioctl a moment; the assertion is simply that we survive.
        try await Task.sleep(nanoseconds: 200_000_000)
        pty.close()
    }

    @Test("Closing stdin ends the process and reports an exit code")
    func exitOnEOF() async throws {
        let exitCode = ExitBox()
        let pty = try PTYSession(shellPath: "/bin/cat", arguments: ["/bin/cat"])
        pty.onExit = { exitCode.set($0) }

        // Ctrl-D (EOT) on a fresh line signals EOF to cat, which then exits 0.
        pty.write(Data([0x04]))

        try await waitUntil(timeout: 5) { exitCode.isSet() }
        #expect(exitCode.value() == 0)
        pty.close()
    }

    // MARK: - helpers

    private final class ExitBox: @unchecked Sendable {
        private let lock = NSLock()
        private var code: Int32?
        private var wasSet = false
        func set(_ c: Int32?) { lock.lock(); code = c; wasSet = true; lock.unlock() }
        func isSet() -> Bool { lock.lock(); defer { lock.unlock() }; return wasSet }
        func value() -> Int32? { lock.lock(); defer { lock.unlock() }; return code }
    }

    private func waitUntil(timeout: TimeInterval, _ condition: @Sendable () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}
#endif
