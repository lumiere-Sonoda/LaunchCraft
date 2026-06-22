//
//  ShellRunner.swift
//  AutoShell-execer
//
//  プロセスの実行を担当する。
//   - runCapture: 出力をまとめて受け取る（launchctl 呼び出しなどに使用）
//   - stream: 出力を1行ずつ AsyncStream で流す（テスト実行のライブ表示に使用）
//
//  いずれも nonisolated。MainActor から切り離してバックグラウンドで動かす。
//

import Foundation

/// 実行中に発生するイベント
enum RunEvent: Sendable {
    case stdout(String)
    case stderr(String)
    case terminated(Int32)
}

struct CommandResult: Sendable {
    let status: Int32
    let stdout: String
    let stderr: String
}

enum ShellRunner {

    /// コマンドを実行し、終了するまで待って出力をまとめて返す。
    nonisolated static func runCapture(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) async -> CommandResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<CommandResult, Never>) in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let environment { process.environment = environment }
            if let currentDirectory, !currentDirectory.isEmpty {
                process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
            }

            let outPipe = Pipe()
            let errPipe = Pipe()
            process.standardOutput = outPipe
            process.standardError = errPipe

            do {
                try process.run()
            } catch {
                continuation.resume(returning: CommandResult(
                    status: -1, stdout: "", stderr: String(localized: "launchFailed", defaultValue: "起動に失敗: \(error.localizedDescription)")
                ))
                return
            }

            let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()

            continuation.resume(returning: CommandResult(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errData, encoding: .utf8) ?? ""
            ))
        }
    }

    /// コマンドを実行し、出力をストリームで流す。
    /// 戻り値の Process を使えば途中で停止できる。
    nonisolated static func stream(
        executable: String,
        arguments: [String],
        environment: [String: String]? = nil,
        currentDirectory: String? = nil
    ) -> (process: Process, events: AsyncStream<RunEvent>) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let environment { process.environment = environment }
        if let currentDirectory, !currentDirectory.isEmpty {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stream = AsyncStream<RunEvent> { continuation in
            outPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let s = String(data: data, encoding: .utf8) {
                    continuation.yield(.stdout(s))
                }
            }
            errPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty { return }
                if let s = String(data: data, encoding: .utf8) {
                    continuation.yield(.stderr(s))
                }
            }

            process.terminationHandler = { proc in
                // ハンドラを止めて残りを読み切る
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let restOut = outPipe.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: restOut, encoding: .utf8), !s.isEmpty {
                    continuation.yield(.stdout(s))
                }
                let restErr = errPipe.fileHandleForReading.readDataToEndOfFile()
                if let s = String(data: restErr, encoding: .utf8), !s.isEmpty {
                    continuation.yield(.stderr(s))
                }
                continuation.yield(.terminated(proc.terminationStatus))
                continuation.finish()
            }

            do {
                try process.run()
            } catch {
                continuation.yield(.stderr(String(localized: "launchFailed", defaultValue: "起動に失敗: \(error.localizedDescription)") + "\n"))
                continuation.yield(.terminated(-1))
                continuation.finish()
            }
        }

        return (process, stream)
    }
}
