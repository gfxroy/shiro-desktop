import Foundation

public struct CommandResult { public let stdout: String; public let stderr: String; public let status: Int32 }

private final class ProcessBox: @unchecked Sendable {
    let lock = NSLock()
    var process: Process?
    var cancelled = false
    private var exceededOutput = false
    func start(_ process: Process) throws {
        try lock.withLock {
            if cancelled { throw CancellationError() }
            self.process = process
            try process.run()
        }
    }
    var wasCancelled: Bool { lock.withLock { cancelled } }
    var outputExceeded: Bool { lock.withLock { exceededOutput } }
    func cancel(outputLimit: Bool = false) {
        let p = lock.withLock { () -> Process? in
            exceededOutput = exceededOutput || outputLimit
            guard !cancelled else { return nil }
            cancelled = true; return process
        }
        if let p, p.isRunning {
            let pid = p.processIdentifier, group = getpgid(pid)
            if group == pid { kill(-pid, SIGTERM) } else { p.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) { if group == pid { kill(-pid, SIGKILL) } else if p.isRunning { kill(pid, SIGKILL) } }
        }
    }
}

public enum ProcessRunner {
    public static func locate(_ name: String) -> String? {
        let paths = ["/opt/homebrew/bin", "/usr/local/bin", NSHomeDirectory() + "/.local/bin", "/usr/bin", "/bin"] + (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        return paths.map { $0 + "/" + name }.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
    public static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval = 90, workingDirectory: URL? = nil, outputLimit: Int = 64_000_000) async throws -> CommandResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler(operation: {
            try await Task.detached { try execute(executable, arguments, timeout: timeout, box: box, workingDirectory: workingDirectory, outputLimit: outputLimit) }.value
        }, onCancel: { box.cancel() })
    }
    private static func execute(_ executable: String, _ arguments: [String], timeout: TimeInterval, box: ProcessBox, workingDirectory: URL?, outputLimit: Int) throws -> CommandResult {
                let process = Process(), out = Pipe(), err = Pipe()
                process.executableURL = URL(fileURLWithPath: executable); process.arguments = arguments
                process.currentDirectoryURL = workingDirectory
                process.standardOutput = out; process.standardError = err
                var env = ProcessInfo.processInfo.environment
                env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
                process.environment = env
                try box.start(process)
                let timer = DispatchWorkItem { box.cancel() }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                let errorGroup = DispatchGroup()
                errorGroup.enter()
                let errorBox = DataBox()
                let budget = OutputBudget(limit: max(1024, outputLimit))
                DispatchQueue.global().async { errorBox.data = collect(err.fileHandleForReading, budget: budget, box: box); errorGroup.leave() }
                let data = collect(out.fileHandleForReading, budget: budget, box: box)
                process.waitUntilExit(); errorGroup.wait(); timer.cancel()
                if box.outputExceeded { throw ShiroError("Command output exceeded its safety limit.") }
                if box.wasCancelled { throw ShiroError("Command stopped or timed out.") }
                return CommandResult(stdout: String(decoding: data, as: UTF8.self), stderr: String(decoding: errorBox.data, as: UTF8.self), status: process.terminationStatus)
    }
    private final class DataBox: @unchecked Sendable { var data = Data() }
    private final class OutputBudget: @unchecked Sendable {
        let lock = NSLock(), limit: Int; var count = 0
        init(limit: Int) { self.limit = limit }
        func accept(_ size: Int) -> Bool { lock.withLock { count += size; return count <= limit } }
    }
    private static func collect(_ handle: FileHandle, budget: OutputBudget, box: ProcessBox) -> Data {
        var result = Data()
        while let chunk = try? handle.read(upToCount: 65536), !chunk.isEmpty {
            if budget.accept(chunk.count) { result.append(chunk) } else { box.cancel(outputLimit: true) }
        }
        return result
    }
    public static func checked(_ executable: String, _ arguments: [String], timeout: TimeInterval = 90) async throws -> String {
        let result = try await run(executable, arguments, timeout: timeout)
        guard result.status == 0 else { throw ShiroError(String((result.stderr.isEmpty ? result.stdout : result.stderr).suffix(3000))) }
        return result.stdout
    }
}
