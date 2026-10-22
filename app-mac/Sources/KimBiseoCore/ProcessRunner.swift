import Foundation

public struct ProcessOutput {
    public let stdout: Data
    public let stderr: Data
    public let exitCode: Int32
    public let timedOut: Bool
}

/// 하위 프로세스를 실행하고 끝날 때까지 기다린다. 제한 시간을 넘기거나 취소되면 종료시킨다.
public final class ProcessRunner: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Process?

    public init() {}

    public func run(executable: String, arguments: [String], stdin: String? = nil, workDir: URL? = nil,
                    environment: [String: String]? = nil, timeout: TimeInterval) async throws -> ProcessOutput {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let workDir { process.currentDirectoryURL = workDir }
        if let environment { process.environment = environment }
        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        var outData = Data(), errData = Data()
        let readGroup = DispatchGroup()
        readGroup.enter()
        DispatchQueue.global().async { outData = outPipe.fileHandleForReading.readDataToEndOfFile(); readGroup.leave() }
        readGroup.enter()
        DispatchQueue.global().async { errData = errPipe.fileHandleForReading.readDataToEndOfFile(); readGroup.leave() }

        try process.run()
        lock.withLock { current = process }
        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? inPipe.fileHandleForWriting.close()

        var timedOut = false
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning {
            if Date() > deadline { timedOut = true; process.terminate(); break }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        process.waitUntilExit()
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            readGroup.notify(queue: .global()) { done.resume() }
        }
        lock.withLock { current = nil }
        return ProcessOutput(stdout: outData, stderr: errData, exitCode: process.terminationStatus, timedOut: timedOut)
    }

    public func cancel() {
        lock.withLock { current }?.terminate()
    }
}
