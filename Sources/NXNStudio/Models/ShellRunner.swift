import Foundation

// MARK: - Shell result

struct ShellResult: Sendable {
    let code: Int32
    var output: String = ""
    var errorText: String = ""

    var succeeded: Bool { code == 0 }
    var combined: String {
        [output, errorText]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Line collector

/// Splits a stream into lines (LF or CR, so progress bars update in place) and
/// keeps the complete text for later inspection.
final class OutputCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer = [UInt8]()
    private var collected = ""
    /// Keeps the tail of the stream: logs are for reading, not archiving.
    private static let maxCollectedBytes = 2 * 1024 * 1024
    private let onLine: (@Sendable (String) -> Void)?

    init(onLine: (@Sendable (String) -> Void)? = nil) {
        self.onLine = onLine
    }

    func feed(_ data: Data) {
        guard !data.isEmpty else { return }
        lock.lock()
        buffer.append(contentsOf: data)

        var start = 0
        var index = 0
        while index < buffer.count {
            let byte = buffer[index]
            if byte == 10 || byte == 13 {
                if index > start {
                    emit(Array(buffer[start..<index]))
                }
                start = index + 1
            }
            index += 1
        }
        if start > 0 { buffer.removeFirst(start) }
        lock.unlock()
    }

    func finish() {
        lock.lock()
        if !buffer.isEmpty {
            emit(buffer)
            buffer.removeAll()
        }
        lock.unlock()
    }

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    private func emit(_ bytes: [UInt8]) {
        let line = String(decoding: bytes, as: UTF8.self)
        guard !line.isEmpty else { return }
        collected += line + "\n"
        if collected.utf8.count > Self.maxCollectedBytes {
            collected = String(collected.suffix(Self.maxCollectedBytes))
        }
        onLine?(line)
    }
}

// MARK: - Runner

enum ShellRunner {
    /// Runs a command through `/usr/bin/env`, streams its output line by line and
    /// returns once the process has exited and both pipes reached EOF.
    static func run(
        _ command: [String],
        in directory: URL? = nil,
        extraEnvironment: [String: String] = [:],
        onLaunch: (@Sendable (Int32) -> Void)? = nil,
        onProcess: (@Sendable (Process) -> Void)? = nil,
        onLine: (@Sendable (String) -> Void)? = nil
    ) async -> ShellResult {
        guard let executable = command.first else {
            return ShellResult(code: 2, errorText: "Commande vide")
        }

        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        process.currentDirectoryURL = directory
        process.environment = environment(extra: extraEnvironment)

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = FileHandle.nullDevice

        let outCollector = OutputCollector(onLine: onLine)
        let errCollector = OutputCollector(onLine: onLine)

        let (termination, continuation) = AsyncStream<Int32>.makeStream()
        process.terminationHandler = { proc in
            continuation.yield(proc.terminationStatus)
            continuation.finish()
        }

        do {
            try process.run()
            onLaunch?(process.processIdentifier)
            onProcess?(process)
        } catch {
            errCollector.feed(Data("Impossible de lancer \(executable): \(error.localizedDescription)".utf8))
            errCollector.finish()
            continuation.yield(127)
            continuation.finish()
            return ShellResult(code: 127, errorText: errCollector.output)
        }

        let outHandle = outPipe.fileHandleForReading
        let errHandle = errPipe.fileHandleForReading
        let outTask = Task.detached { await drain(outHandle, into: outCollector) }
        let errTask = Task.detached { await drain(errHandle, into: errCollector) }

        var code: Int32 = 0
        for await status in termination { code = status }
        await outTask.value
        await errTask.value
        outCollector.finish()
        errCollector.finish()

        return ShellResult(
            code: code,
            output: outCollector.output,
            errorText: errCollector.output
        )
    }

    /// Small synchronous variant for short, non-interactive helpers
    /// (hdiutil, ditto) where streaming is not needed.
    static func runSync(_ command: [String]) -> ShellResult {
        guard let executable = command.first else {
            return ShellResult(code: 2, errorText: "Commande vide")
        }
        let process = Process()
        if executable.contains("/") {
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = Array(command.dropFirst())
        } else {
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = command
        }
        process.environment = environment()
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return ShellResult(code: 127, errorText: error.localizedDescription)
        }
        // Drain both pipes concurrently: reading one to EOF while the other
        // fills its buffer would deadlock the child.
        final class Box: @unchecked Sendable {
            let lock = NSLock()
            var data = Data()
            func store(_ value: Data) { lock.lock(); data = value; lock.unlock() }
            var value: Data { lock.lock(); defer { lock.unlock() }; return data }
        }
        let outs = Box()
        let errs = Box()
        let group = DispatchGroup()
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outs.store(outHandle.readDataToEndOfFile())
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errs.store(errHandle.readDataToEndOfFile())
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return ShellResult(
            code: process.terminationStatus,
            output: String(decoding: outs.value, as: UTF8.self),
            errorText: String(decoding: errs.value, as: UTF8.self)
        )
    }

    private static func drain(_ handle: FileHandle, into collector: OutputCollector) async {
        while true {
            let data: Data?
            do {
                data = try handle.read(upToCount: 65_536)
            } catch {
                break
            }
            guard let data, !data.isEmpty else { break }
            collector.feed(data)
        }
    }

    static func environment(extra: [String: String] = [:]) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let additions = [
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/.dotnet",
            "/usr/local/share/dotnet",
        ]
        // Prepend the toolchains: a Finder-launched app has a minimal PATH and
        // must prefer Homebrew's python3 over /usr/bin/python3.
        var path = additions
        for entry in (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":")
            .map(String.init)
        where !path.contains(entry) {
            path.append(entry)
        }
        env["PATH"] = path.joined(separator: ":")
        env.merge(extra) { _, new in new }
        return env
    }

    static func pretty(_ command: [String]) -> String {
        command.map { token in
            token.contains(" ") || token.contains("(") || token.contains(")")
                ? "\"\(token)\""
                : token
        }.joined(separator: " ")
    }
}
